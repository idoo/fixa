import FixaKit
import MapKit
import PhotosUI
import SwiftUI

struct ReportScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.fxHaptics) private var haptics
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
            .fxBottomBar {
                FxPrimaryButton(title: String(localized: "Review", bundle: L10n.bundle, locale: L10n.locale), systemImage: "arrow.forward") {
                    review(scrollingWith: proxy)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .fxScreenBackground()
        .navigationTitle(Text("New report"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.error, trigger: failedReviews) { _, _ in haptics }
        .sensoryFeedback(.impact(weight: .light), trigger: cameraTaps) { _, _ in haptics }
        .sensoryFeedback(.selection, trigger: phraseTaps) { _, _ in haptics }
        .onAppear { replyInline = !model.profileIsReady }
        .task { await model.prefillLocationIfAllowed() }
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
        guard let firstIssue = issues.first else { return }
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
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pendingPhotos = min(items.count, AppModel.maxPhotos - model.photos.count)
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            model.addPhotos(images)
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
                            .lineLimit(3)
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
            if let issue {
                issueText(issue)
            }
        }
    }

    private var locationSummary: String {
        if model.draft.coordinate == nil {
            return model.isFindingLocation
                ? String(localized: "Finding you…", bundle: L10n.bundle, locale: L10n.locale)
                : String(localized: "Choose the place on a map", bundle: L10n.bundle, locale: L10n.locale)
        }
        let text = model.draft.locationText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? String(localized: "Pin placed on the map", bundle: L10n.bundle, locale: L10n.locale) : text
    }

    // MARK: Quick phrases

    /// Chips read in the app's language but add the Swedish phrase: the municipality reads Swedish.
    private var quickPhrases: some View {
        let phrases = QuickPhrases.phrases(forTile: model.draft.tileID)
        return FlowLayout(spacing: Fx.Space.s) {
            ForEach(phrases, id: \.self) { phrase in
                let added = model.draft.description.localizedCaseInsensitiveContains(phrase.swedish)
                Button {
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
    /// `label` is in the app's language; `swedish` is what goes into the description.
    struct Phrase: Hashable {
        let label: String
        let swedish: String
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
            [phrase("Broken play equipment"), phrase("Fallen tree or branch"), phrase("Overflowing bins")]
        case "water":
            [phrase("Water leaking in the street"), phrase("Drain is blocked"), phrase("Bad smell")]
        default:
            [phrase("Dangerous"), phrase("Been like this for a while"), phrase("Getting worse")]
        }
    }

    /// The app's compiled Swedish strings; nil only if the sv localization is missing from the bundle.
    private static let swedishBundle: Bundle? = Bundle.main
        .path(forResource: "sv", ofType: "lproj")
        .flatMap(Bundle.init(path:))

    private static func phrase(_ resource: LocalizedStringResource) -> Phrase {
        let label = L10n.bundle.localizedString(forKey: resource.key, value: resource.key, table: nil)
        let swedish = swedishBundle?.localizedString(forKey: resource.key, value: label, table: nil) ?? label
        return Phrase(label: label, swedish: swedish)
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
