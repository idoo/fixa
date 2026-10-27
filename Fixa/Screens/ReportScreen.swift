import FixaKit
import MapKit
import PhotosUI
import SwiftUI

struct ReportScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.openURL) private var openURL
    @Environment(\.fxReduceMotion) private var reduceMotion
    /// VoiceOver focus goes to the first section with an issue when Review fails.
    @AccessibilityFocusState private var a11yFocus: Section?
    /// Keyboard focus for the description and e-mail when they are the first issue.
    @FocusState private var keyboardFocus: Section?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var cameraTaps = 0
    /// Photos picked but still loading; each reserves a slot in the row.
    @State private var pendingPhotos = 0
    /// Bumped when Review is tapped with issues: drives the error haptic.
    @State private var failedReviews = 0
    /// Reply fields inline (no usable profile yet) or the one-line profile summary. Decided when the
    /// screen appears or the toggle turns on, so the fields don't collapse while an e-mail is typed.
    @State private var replyInline = true
    /// Bumped by quick-phrase chips: drives the selection haptic.
    @State private var phraseTaps = 0
    /// Bumped when an acute water chip is tapped: scrolls up to the call card.
    @State private var acuteTaps = 0
    /// Where a picked photo was taken (inside the municipality), read from the original file
    /// before it is re-encoded without metadata.
    @State private var photoPlace: Coordinate?

    /// Form sections, top to bottom: required first, optional last.
    private enum Section: Int, Comparable, Hashable {
        case problem, place, details, photos, reply

        init(_ field: ValidationIssue.Field) {
            switch field {
            case .category: self = .problem
            case .location: self = .place
            case .description: self = .details
            case .email, .phone: self = .reply
            }
        }

        static func < (lhs: Section, rhs: Section) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Fx.Space.xl) {
                    if let emergency = waterEmergency {
                        waterCallCard(emergency)
                            .id(Self.callCardID)
                    }
                    categorySection
                        .id(Section.problem)
                    locationSection
                        .id(Section.place)
                    VStack(alignment: .leading, spacing: Fx.Space.s) {
                        FxSectionHeader(String(localized: "What's wrong?", bundle: L10n.bundle, locale: L10n.locale))
                        FxTextEditor(
                            title: String(localized: "What's wrong?", bundle: L10n.bundle, locale: L10n.locale),
                            text: $model.draft.description,
                            prompt: String(localized: "For example: the light by the bus stop has been out since Monday. Write in any language.", bundle: L10n.bundle, locale: L10n.locale),
                            issue: model.issue(for: .description)?.message,
                            minHeight: 140,
                            showsTitle: false
                        )
                        .focused($keyboardFocus, equals: .details)
                        .accessibilityFocused($a11yFocus, equals: .details)
                        .accessibilityIdentifier("report.description")
                        quickPhrases
                    }
                    .id(Section.details)
                    photoSection
                        .id(Section.photos)
                    feedbackSection
                        .id(Section.reply)
                }
                .padding(Fx.Space.l)
            }
            .onChange(of: acuteTaps) { _, _ in
                withAnimation(reduceMotion ? nil : Fx.Motion.select) {
                    proxy.scrollTo(Self.callCardID, anchor: .top)
                }
                AccessibilityNotification.Announcement(acuteHint).post()
            }
            .fxBottomBar {
                FxPrimaryButton(title: String(localized: "Review", bundle: L10n.bundle, locale: L10n.locale), systemImage: "arrow.forward") {
                    review(scrollingWith: proxy)
                }
                .accessibilityIdentifier("report.review")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .fxScreenBackground()
        .navigationTitle(Text("New report"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.error, trigger: failedReviews) { _, _ in haptics }
        .sensoryFeedback(.impact(weight: .light), trigger: cameraTaps) { _, _ in haptics }
        .sensoryFeedback(.selection, trigger: phraseTaps) { _, _ in haptics }
        .onAppear {
            replyInline = !model.profileIsReady
        }
        // A translation belongs to one text: Review makes a new one for the changed description.
        .onChange(of: model.draft.description) { _, _ in
            if model.draft.translation != nil { model.draft.translation = nil }
        }
        .task { await model.prefillLocationIfAllowed() }
        .onChange(of: model.photos.isEmpty) { _, isEmpty in
            if isEmpty { photoPlace = nil }
        }
        .onChange(of: pickerItems) { _, items in
            loadPicked(items)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { image in
                model.addPhotos([image])
            }
            .ignoresSafeArea()
        }
    }

    /// Goes to Review, or scrolls to the first section with an issue (inline messages show there),
    /// moves VoiceOver there and says what to fix.
    private func review(scrollingWith proxy: ScrollViewProxy) {
        guard !model.goToReview() else { return }
        failedReviews += 1
        let issues = model.issues.sorted { Section($0.field) < Section($1.field) }
        guard let firstIssue = issues.first else {
            // Nothing to fix in the fields: the pin is in another kommun.
            if let other = model.outsideMunicipalityName {
                withAnimation(reduceMotion ? nil : Fx.Motion.select) {
                    proxy.scrollTo(Section.place, anchor: .top)
                }
                a11yFocus = .place
                AccessibilityNotification.Announcement(outsideMessage(other)).post()
            }
            return
        }
        let first = Section(firstIssue.field)
        withAnimation(reduceMotion ? nil : Fx.Motion.select) {
            proxy.scrollTo(first, anchor: .top)
        }
        a11yFocus = first
        if first == .details || (first == .reply && replyInline && model.draft.wantsFeedback) {
            keyboardFocus = first
        }
        AccessibilityNotification.Announcement(
            String(localized: "Fix \(issues.count) things before review. \(firstIssue.message)", bundle: L10n.bundle, locale: L10n.locale)
        ).post()
    }

    // MARK: Acute water

    private static let callCardID = "report.callCard"

    /// The emergency lines, only for the water tile: the kommun takes acute water and sewer faults by phone.
    private var waterEmergency: AdapterSpec.Emergency? {
        guard spec.tile(id: model.draft.tileID)?.categoryID == "water" else { return nil }
        return spec.emergency
    }

    /// An acute chip ("Water leaking in the street", "Drain is blocked") is in the description.
    private var acutePicked: Bool {
        QuickPhrases.phrases(forTile: model.draft.tileID).contains { phrase in
            phrase.acute && model.draft.description.localizedCaseInsensitiveContains(phrase.swedish)
        }
    }

    private var acuteHint: String {
        String(localized: "This sounds urgent. Call instead of sending a report.", bundle: L10n.bundle, locale: L10n.locale)
    }

    /// Time-aware call card at the top of the water report; outlined once an acute chip is picked.
    private func waterCallCard(_ emergency: AdapterSpec.Emergency) -> some View {
        let highlighted = acutePicked
        return TimelineView(.everyMinute) { context in
            let contact = EmergencyRouter.contact(for: context.date, emergency: emergency)
            let digits = contact.phone.filter(\.isNumber)
            // Number first and unbreakable (NBSP, non-breaking hyphen): if the line wraps, only the name moves.
            let number = contact.phone.replacingOccurrences(of: " ", with: "\u{00A0}").replacingOccurrences(of: "-", with: "\u{2011}")
            VStack(alignment: .leading, spacing: Fx.Space.s) {
                FxCallRow(
                    title: String(localized: "No water, sewage backing up or flooding? Call now", bundle: L10n.bundle, locale: L10n.locale),
                    detail: "\(number.ltrIsolated) · \(contact.title.resolve(L10n.locale))",
                    accessibilityValue: "\(contact.phone), \(contact.title.resolve(L10n.locale))"
                ) {
                    if let url = URL(string: "tel:\(digits)") {
                        openURL(url)
                    }
                }
                .overlay {
                    if highlighted {
                        RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous)
                            .strokeBorder(Fx.Color.error, lineWidth: Fx.Border.emphasis)
                            .allowsHitTesting(false)
                    }
                }
                if highlighted {
                    Label(acuteHint, systemImage: "phone.arrow.up.right")
                        .font(Fx.Font.callout.weight(.semibold))
                        .foregroundStyle(Fx.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("report.callCard")
    }

    /// Title, Spacer and "Change" side by side; stacked at accessibility text sizes.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Fx.Space.xs))
            : AnyLayout(HStackLayout(spacing: Fx.Space.m))
    }

    // MARK: Category

    private var categorySection: some View {
        let tile = spec.tile(id: model.draft.tileID)
        let title = tile?.title.resolve(L10n.locale) ?? String(localized: "Choose a problem", bundle: L10n.bundle, locale: L10n.locale)
        let issue = model.issue(for: .category)?.message
        return VStack(alignment: .leading, spacing: Fx.Space.s) {
            FxSectionHeader(String(localized: "Problem", bundle: L10n.bundle, locale: L10n.locale))
            Menu {
                ForEach(spec.tiles, id: \.id) { tile in
                    Button {
                        model.select(tile: tile)
                    } label: {
                        Label(tile.title.resolve(L10n.locale), systemImage: tile.symbol)
                    }
                }
            } label: {
                FxCard {
                    rowLayout {
                        Image(systemName: tile?.symbol ?? "questionmark.circle")
                            .font(Fx.Font.headline)
                            .foregroundStyle(Fx.Color.sea)
                            .accessibilityHidden(true)
                        Text(title)
                            .font(Fx.Font.headline)
                            .foregroundStyle(Fx.Color.ink)
                            .multilineTextAlignment(.leading)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Spacer(minLength: Fx.Space.s)
                        }
                        Text("Change")
                            .font(Fx.Font.callout)
                            .foregroundStyle(Fx.Color.sea)
                    }
                    .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
                }
            }
            .buttonStyle(FxPressStyle())
            .accessibilityLabel(Text("Problem: \(title)"))
            .accessibilityValue(issue.map { Text($0) } ?? Text(""))
            .accessibilityInputLabels([Text("Change problem"), Text("Problem")])
            .accessibilityFocused($a11yFocus, equals: .problem)
            if let note = tile?.responsibility?.resolve(L10n.locale) {
                Text(note)
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("report.responsibility")
            }
            ForEach(tile?.links ?? [], id: \.self) { link in
                FxIconRow(systemImage: "safari", text: link.title.resolve(L10n.locale), link: link.url)
                    .accessibilityHint(Text("Opens in Safari"))
            }
            if let issue {
                issueText(issue)
            }
        }
    }

    // MARK: Photos

    private var photoSection: some View {
        let room = AppModel.maxPhotos - model.photos.count - pendingPhotos
        return VStack(alignment: .leading, spacing: Fx.Space.s) {
            FxSectionHeader(
                String(localized: "Photos", bundle: L10n.bundle, locale: L10n.locale),
                subtitle: String(localized: "Optional, up to 3", bundle: L10n.bundle, locale: L10n.locale)
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Fx.Space.s) {
                    ForEach(Array(model.photos.enumerated()), id: \.offset) { index, image in
                        FxPhotoSlot(
                            image: image,
                            label: String(localized: "Photo \(index + 1)", bundle: L10n.bundle, locale: L10n.locale),
                            removeLabel: String(localized: "Remove photo \(index + 1)", bundle: L10n.bundle, locale: L10n.locale)
                        ) {
                            model.removePhoto(at: index)
                        }
                    }
                    ForEach(0..<pendingPhotos, id: \.self) { _ in
                        FxPhotoSlot.loading
                    }
                    if room > 0 {
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: AppModel.maxPhotos - model.photos.count,
                            matching: .images
                        ) {
                            FxPhotoSlot(addTitle: String(localized: "Choose photos", bundle: L10n.bundle, locale: L10n.locale), systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(FxPressStyle())
                        .accessibilityLabel(Text("Choose photos"))
                        if CameraPicker.isAvailable {
                            Button {
                                cameraTaps += 1
                                isCameraPresented = true
                            } label: {
                                FxPhotoSlot(addTitle: String(localized: "Take photo", bundle: L10n.bundle, locale: L10n.locale), systemImage: "camera")
                            }
                            .buttonStyle(FxPressStyle())
                            .accessibilityLabel(Text("Take photo"))
                        }
                    }
                }
            }
            .scrollClipDisabled()
            Text("Avoid faces and number plates.")
                .font(Fx.Font.footnote)
                .foregroundStyle(Fx.Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pendingPhotos = min(items.count, AppModel.maxPhotos - model.photos.count)
        Task {
            var images: [UIImage] = []
            var place: Coordinate?
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                    // Read from the original data: the photo itself is re-encoded without GPS.
                    if place == nil, let found = PhotoLocation.coordinate(in: data), spec.municipality.region.contains(found) {
                        place = found
                    }
                }
            }
            model.addPhotos(images)
            if let place { photoPlace = place }
            pickerItems = []
            pendingPhotos = 0
        }
    }

    // MARK: Location

    private var locationSection: some View {
        let issue = model.issue(for: .location)?.message
        return VStack(alignment: .leading, spacing: Fx.Space.s) {
            FxSectionHeader(String(localized: "Where?", bundle: L10n.bundle, locale: L10n.locale))
            Button {
                model.isLocationPickerPresented = true
            } label: {
                FxCard {
                    if let coordinate = model.draft.coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coordinate.clLocation,
                            latitudinalMeters: 400,
                            longitudinalMeters: 400
                        )), interactionModes: []) {
                            Marker(model.draft.locationText, coordinate: coordinate.clLocation)
                                .tint(Fx.Color.sea)
                        }
                        .id(coordinate.key)
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    HStack(spacing: Fx.Space.s) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Fx.Color.sea)
                            .accessibilityHidden(true)
                        Text(locationSummary)
                            .font(Fx.Font.body)
                            .foregroundStyle(model.draft.coordinate == nil ? Fx.Color.ink2 : Fx.Color.ink)
                            .multilineTextAlignment(.leading)
                            // Wraps word by word at every text size; never shrinks or clips.
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Fx.Space.s)
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(Fx.Color.ink2)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Fx.minTarget)
                }
            }
            .buttonStyle(FxPressStyle())
            .accessibilityLabel(Text("Place: \(locationSummary)"))
            .accessibilityValue(issue.map { Text($0) } ?? Text(""))
            .accessibilityHint(Text("Opens the map"))
            .accessibilityInputLabels([Text("Place"), Text("Map")])
            .accessibilityFocused($a11yFocus, equals: .place)
            .accessibilityIdentifier("report.place")
            if let issue {
                issueText(issue)
            }
            if let other = model.outsideMunicipalityName {
                FxBanner(kind: .warning, title: outsideMessage(other))
                    .accessibilityIdentifier("report.outside")
            }
            if let photoPlace, photoPlace != model.draft.coordinate,
               model.draft.coordinate == nil || model.pinIsAutomatic {
                Button {
                    usePhotoPlace(photoPlace)
                } label: {
                    Label {
                        Text("Use the place where the photo was taken")
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "photo")
                            .accessibilityHidden(true)
                    }
                    .font(Fx.Font.callout.weight(.semibold))
                    .foregroundStyle(Fx.Color.sea)
                    .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(FxPressStyle())
                .accessibilityHint(Text("Puts the pin where the photo was taken"))
                .accessibilityIdentifier("report.photoPlace")
            }
            placeTextField
        }
    }

    /// The place in words: prefilled with the pin's address, editable, and enough on its own.
    private var placeTextField: some View {
        let title = String(localized: "Describe the place", bundle: L10n.bundle, locale: L10n.locale)
        let text = Binding(
            get: { model.draft.locationText },
            set: { newValue in
                model.draft.locationText = newValue
                // A typed place is never overwritten by a later pin's address (AppModel, picker, photo).
                model.placeTextIsTyped = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
        let focused = keyboardFocus == .place
        return VStack(alignment: .leading, spacing: Fx.Space.xs) {
            Text(title)
                .font(Fx.Font.subheadline)
                .foregroundStyle(Fx.Color.ink)
                .accessibilityHidden(true)
            TextField(
                text: text,
                prompt: Text("For example: by the bus stop on Skolvägen").foregroundStyle(Fx.Color.ink2),
                axis: .vertical
            ) {
                Text(title)
            }
            .lineLimit(1...6)
            .font(Fx.Font.body)
            .foregroundStyle(Fx.Color.ink)
            .textInputAutocapitalization(.sentences)
            .focused($keyboardFocus, equals: .place)
            .padding(.horizontal, Fx.Space.m)
            .padding(.vertical, Fx.Space.s)
            .frame(minHeight: Fx.minTarget + 4)
            .fxOutline(
                RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous),
                outline: focused ? Fx.Color.sea : Fx.Color.fieldBorder,
                width: focused ? Fx.Border.emphasis : Fx.Border.hairline
            )
            .accessibilityLabel(Text(title))
            .accessibilityHint(Text("Sent as written. Enough on its own if you don't put a pin on the map."))
            .accessibilityIdentifier("report.placeText")
        }
    }

    /// One tap: the pin goes where the photo was taken; the address fills in unless the resident typed one.
    private func usePhotoPlace(_ place: Coordinate) {
        model.draft.coordinate = place
        if !model.placeTextIsTyped { model.draft.locationText = "" }
        Task {
            let address = await ReverseGeocoder.address(for: place.clLocation)
            guard model.draft.coordinate == place else { return }
            if !model.placeTextIsTyped { model.draft.locationText = address ?? "" }
            let announcement = address.map { String(localized: "Pin placed: \($0)", bundle: L10n.bundle, locale: L10n.locale) }
                ?? String(localized: "Pin placed on the map", bundle: L10n.bundle, locale: L10n.locale)
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    /// The map card's line: the pin's state. The address itself is in "Describe the place".
    private var locationSummary: String {
        if model.draft.coordinate == nil {
            return model.isFindingLocation
                ? String(localized: "Finding you…", bundle: L10n.bundle, locale: L10n.locale)
                : String(localized: "Choose the place on a map", bundle: L10n.bundle, locale: L10n.locale)
        }
        if model.pinIsAutomatic {
            return String(localized: "Your current location. Move the pin to the problem.", bundle: L10n.bundle, locale: L10n.locale)
        }
        return String(localized: "Pin placed on the map", bundle: L10n.bundle, locale: L10n.locale)
    }

    /// The pin is in another kommun: the report belongs there, so Review stays closed.
    private func outsideMessage(_ kommun: String) -> String {
        String(localized: "This place is in \(kommun). Report it to that kommun.", bundle: L10n.bundle, locale: L10n.locale)
    }

    // MARK: Quick phrases

    /// Chips read in the app's language but add the Swedish phrase: the municipality reads Swedish.
    private var quickPhrases: some View {
        let phrases = QuickPhrases.phrases(forTile: model.draft.tileID)
        return FlowLayout(spacing: Fx.Space.s) {
            ForEach(phrases, id: \.self) { phrase in
                let added = model.draft.description.localizedCaseInsensitiveContains(phrase.swedish)
                Button {
                    // Acute water chips point at the call card first; the phrase is still added.
                    if phrase.acute { acuteTaps += 1 }
                    guard !added else { return }
                    model.draft.description = QuickPhrases.append(phrase.swedish, to: model.draft.description)
                    phraseTaps += 1
                } label: {
                    HStack(spacing: Fx.Space.xs) {
                        Image(systemName: added ? "checkmark" : "plus")
                            .font(Fx.Font.footnote.weight(.bold))
                            .accessibilityHidden(true)
                        Text(phrase.label)
                            .font(Fx.Font.callout)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(added ? Fx.Color.sea : Fx.Color.ink)
                    .padding(.horizontal, Fx.Space.m)
                    .frame(minHeight: Fx.minTarget)
                    .background(Fx.Color.card, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(added ? Fx.Color.sea : Fx.Color.fieldBorder, lineWidth: added ? Fx.Border.emphasis : Fx.Border.hairline)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(FxPressStyle())
                .accessibilityLabel(Text(phrase.label))
                .accessibilityHint(added ? Text("") : Text("Adds it to the description in Swedish"))
                .accessibilityAddTraits(added ? .isSelected : [])
            }
        }
    }

    // MARK: Feedback

    private var feedbackSection: some View {
        @Bindable var model = model
        let nameLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Fx.Space.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Fx.Space.s))
        let wantsReply = Binding(
            get: { model.draft.wantsFeedback },
            set: { isOn in
                if isOn { replyInline = !model.profileIsReady }
                withAnimation(reduceMotion ? nil : Fx.Motion.select) { model.draft.wantsFeedback = isOn }
            }
        )
        return VStack(alignment: .leading, spacing: Fx.Space.m) {
            FxSectionHeader(String(localized: "Reply", bundle: L10n.bundle, locale: L10n.locale), subtitle: String(localized: "Optional", bundle: L10n.bundle, locale: L10n.locale))
            FxToggleRow(
                title: String(localized: "Reply to me by e-mail", bundle: L10n.bundle, locale: L10n.locale),
                isOn: wantsReply
            )
            if model.draft.wantsFeedback, !replyInline {
                replySummary
            } else if model.draft.wantsFeedback {
                // Typed straight into the profile, so it is there next time.
                FxTextField(
                    title: String(localized: "E-mail", bundle: L10n.bundle, locale: L10n.locale),
                    text: $model.profile.email,
                    prompt: String(localized: "name@example.com", bundle: L10n.bundle, locale: L10n.locale),
                    kind: .email,
                    issue: model.issue(for: .email)?.message
                )
                .focused($keyboardFocus, equals: .reply)
                .accessibilityFocused($a11yFocus, equals: .reply)
                nameLayout {
                    FxTextField(
                        title: String(localized: "First name (optional)", bundle: L10n.bundle, locale: L10n.locale),
                        text: $model.profile.firstName
                    )
                    FxTextField(
                        title: String(localized: "Last name (optional)", bundle: L10n.bundle, locale: L10n.locale),
                        text: $model.profile.lastName
                    )
                }
                FxTextField(
                    title: String(localized: "Phone (optional)", bundle: L10n.bundle, locale: L10n.locale),
                    text: $model.profile.phone,
                    kind: .phone,
                    issue: model.issue(for: .phone)?.message
                )
                Text("Saved on this phone for next time.")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.ink2)
            }
        }
    }

    /// "Reply to anna@example.se · Change": the saved profile stands in for the four fields.
    private var replySummary: some View {
        let email = model.profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            model.path.append(.contactDetails)
        } label: {
            FxCard {
                rowLayout {
                    Image(systemName: "envelope")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.sea)
                        .accessibilityHidden(true)
                    Text("Reply to \(email.ltrIsolated)")
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink)
                        .multilineTextAlignment(.leading)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: Fx.Space.s)
                    }
                    Text("Change")
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.sea)
                }
                .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
            }
        }
        .buttonStyle(FxPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens your contact details to change them"))
        .accessibilityInputLabels([Text("Change reply details"), Text("Reply")])
        .accessibilityFocused($a11yFocus, equals: .reply)
    }

    /// Report-level issues are read as the control's value, so the text itself is hidden from VoiceOver.
    private func issueText(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(Fx.Font.footnote)
            .foregroundStyle(Fx.Color.error)
            .accessibilityHidden(true)
    }
}

// MARK: - Quick phrases

/// Short phrases per tile that a tap adds to the description. App-side on purpose: the adapter
/// stays a description of the e-service, and these are only typing help.
enum QuickPhrases {
    /// `label` is in the app's language; `swedish` is what goes into the description. `acute`: a fault
    /// the kommun takes by phone, so the Report screen points at its call card.
    struct Phrase: Hashable {
        let label: String
        let swedish: String
        var acute = false
    }

    static func phrases(forTile tileID: String?) -> [Phrase] {
        switch tileID {
        case "streetlight":
            [phrase("Completely dark"), phrase("Flickering"), phrase("On during the day")]
        case "pothole":
            [phrase("Deep hole"), phrase("In the cycle lane"), phrase("Dangerous for cyclists")]
        case "winter":
            [phrase("Not ploughed"), phrase("Slippery, needs gritting"), phrase("Snow blocks the path")]
        case "sign":
            [phrase("Sign has fallen over"), phrase("Barrier is broken"), phrase("Sign is hard to see")]
        case "graffiti":
            [phrase("Offensive text"), phrase("Broken glass"), phrase("On a school or playground")]
        case "park":
            [phrase("Broken play equipment"), phrase("Fallen tree or branch"), phrase("Litter bin full")]
        case "water":
            [phrase("Water leaking in the street", acute: true), phrase("Drain is blocked", acute: true), phrase("Bad smell")]
        default:
            [phrase("Dangerous"), phrase("Been like this for a while"), phrase("Getting worse")]
        }
    }

    /// The app's compiled Swedish strings; nil only if the sv localization is missing from the bundle.
    private static let swedishBundle: Bundle? = Bundle.main
        .path(forResource: "sv", ofType: "lproj")
        .flatMap(Bundle.init(path:))

    private static func phrase(_ resource: LocalizedStringResource, acute: Bool = false) -> Phrase {
        let label = L10n.bundle.localizedString(forKey: resource.key, value: resource.key, table: nil)
        let swedish = swedishBundle?.localizedString(forKey: resource.key, value: label, table: nil) ?? label
        return Phrase(label: label, swedish: swedish, acute: acute)
    }

    /// Adds `phrase` as its own sentence: "Out since Monday" + "Flickering" → "Out since Monday. Flickering".
    static func append(_ phrase: String, to text: String) -> String {
        let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = base.last else { return phrase }
        return ".!?…؟".contains(last) ? "\(base) \(phrase)" : "\(base). \(phrase)"
    }
}

/// Wraps chips onto as many lines as they need. SwiftUI mirrors the placement for right-to-left.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            // A chip wider than the line (large Dynamic Type) wraps its own text instead.
            if size.width > maxWidth {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > maxWidth, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            row.sizes.append(size)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
