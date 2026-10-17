import FixaKit
import MapKit
import PhotosUI
import SwiftUI

struct ReportScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    private enum Section: Int, Comparable {
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
                        FxSectionHeader(String(localized: "What's wrong?"))
                        FxTextEditor(
                            title: String(localized: "What's wrong?"),
                            text: $model.draft.description,
                            prompt: String(localized: "For example: the light by the bus stop has been out since Monday. Write in any language."),
                            issue: model.issue(for: .description)?.message,
                            minHeight: 140,
                            showsTitle: false
                        )
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
                FxPrimaryButton(title: String(localized: "Review"), systemImage: "arrow.forward") {
                    review(scrollingWith: proxy)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .fxScreenBackground()
        .navigationTitle(Text("New report"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.error, trigger: failedReviews)
        .sensoryFeedback(.impact(weight: .light), trigger: cameraTaps)
        .sensoryFeedback(.selection, trigger: phraseTaps)
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

    /// Goes to Review, or scrolls to the first section with an issue (inline messages show there).
    private func review(scrollingWith proxy: ScrollViewProxy) {
        guard !model.goToReview() else { return }
        failedReviews += 1
        guard let first = model.issues.map({ Section($0.field) }).min() else { return }
        withAnimation(Fx.Motion.select) {
            proxy.scrollTo(first, anchor: .top)
        }
    }

    // MARK: Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Fx.Space.s) {
            FxSectionHeader(String(localized: "Problem"))
            Menu {
                ForEach(spec.tiles, id: \.id) { tile in
                    Button {
                        model.select(tile: tile)
                    } label: {
                        Label(tile.title.resolve(), systemImage: tile.symbol)
                    }
                }
            } label: {
                FxCard {
                    HStack(spacing: Fx.Space.m) {
                        let tile = spec.tile(id: model.draft.tileID)
                        Image(systemName: tile?.symbol ?? "questionmark.circle")
                            .font(Fx.Font.headline)
                            .foregroundStyle(Fx.Color.sea)
                            .accessibilityHidden(true)
                        Text(tile?.title.resolve() ?? String(localized: "Choose a problem"))
                            .font(Fx.Font.headline)
                            .foregroundStyle(Fx.Color.ink)
                        Spacer(minLength: Fx.Space.s)
                        Text("Change")
                            .font(Fx.Font.callout)
                            .foregroundStyle(Fx.Color.sea)
                    }
                    .frame(minHeight: Fx.minTarget)
                }
            }
            .buttonStyle(FxPressStyle())
            if let issue = model.issue(for: .category) {
                issueText(issue.message)
            }
        }
    }

    // MARK: Photos

    private var photoSection: some View {
        let room = AppModel.maxPhotos - model.photos.count - pendingPhotos
        return VStack(alignment: .leading, spacing: Fx.Space.s) {
            FxSectionHeader(
                String(localized: "Photos"),
                subtitle: String(localized: "Optional, up to 3")
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Fx.Space.s) {
                    ForEach(Array(model.photos.enumerated()), id: \.offset) { index, image in
                        FxPhotoSlot(
                            image: image,
                            label: String(localized: "Photo \(index + 1)"),
                            removeLabel: String(localized: "Remove photo \(index + 1)")
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
                            FxPhotoSlot(addTitle: String(localized: "Choose photos"), systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(FxPressStyle())
                        .accessibilityLabel(Text("Choose photos"))
                        if CameraPicker.isAvailable {
                            Button {
                                cameraTaps += 1
                                isCameraPresented = true
                            } label: {
                                FxPhotoSlot(addTitle: String(localized: "Take photo"), systemImage: "camera")
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
        VStack(alignment: .leading, spacing: Fx.Space.s) {
            FxSectionHeader(String(localized: "Where?"))
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
                        Spacer(minLength: Fx.Space.s)
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(Fx.Color.ink2)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Fx.minTarget)
                }
            }
            .buttonStyle(FxPressStyle())
            .accessibilityHint(Text("Opens the map"))
            if let issue = model.issue(for: .location) {
                issueText(issue.message)
            }
        }
    }

    private var locationSummary: String {
        if model.draft.coordinate == nil {
            return model.isFindingLocation
                ? String(localized: "Finding you…")
                : String(localized: "Choose the place on a map")
        }
        let text = model.draft.locationText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? String(localized: "Pin placed on the map") : text
    }

    // MARK: Quick phrases

    private var quickPhrases: some View {
        let phrases = QuickPhrases.phrases(forTile: model.draft.tileID)
        return FlowLayout(spacing: Fx.Space.s) {
            ForEach(phrases, id: \.self) { phrase in
                let added = model.draft.description.localizedCaseInsensitiveContains(phrase)
                Button {
                    guard !added else { return }
                    model.draft.description = QuickPhrases.append(phrase, to: model.draft.description)
                    phraseTaps += 1
                } label: {
                    HStack(spacing: Fx.Space.xs) {
                        Image(systemName: added ? "checkmark" : "plus")
                            .font(Fx.Font.footnote.weight(.bold))
                            .accessibilityHidden(true)
                        Text(phrase)
                            .font(Fx.Font.callout)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(added ? Fx.Color.sea : Fx.Color.ink)
                    .padding(.horizontal, Fx.Space.m)
                    .frame(minHeight: Fx.minTarget)
                    .background(Fx.Color.card, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(added ? Fx.Color.sea : Fx.Color.line, lineWidth: added ? Fx.Border.emphasis : Fx.Border.hairline)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(FxPressStyle())
                .accessibilityLabel(Text(phrase))
                .accessibilityHint(added ? Text("") : Text("Adds this to the description"))
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
                withAnimation(Fx.Motion.select) { model.draft.wantsFeedback = isOn }
            }
        )
        return VStack(alignment: .leading, spacing: Fx.Space.m) {
            FxSectionHeader(String(localized: "Reply"), subtitle: String(localized: "Optional"))
            FxToggleRow(
                title: String(localized: "Contact me about this"),
                isOn: wantsReply
            )
            if model.draft.wantsFeedback, !replyInline {
                replySummary
            } else if model.draft.wantsFeedback {
                // Typed straight into the profile, so it is there next time.
                FxTextField(
                    title: String(localized: "E-mail"),
                    text: $model.profile.email,
                    prompt: String(localized: "name@example.com"),
                    kind: .email,
                    issue: model.issue(for: .email)?.message
                )
                nameLayout {
                    FxTextField(
                        title: String(localized: "First name (optional)"),
                        text: $model.profile.firstName
                    )
                    FxTextField(
                        title: String(localized: "Last name (optional)"),
                        text: $model.profile.lastName
                    )
                }
                FxTextField(
                    title: String(localized: "Phone (optional)"),
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
            model.path.append(.profile)
        } label: {
            FxCard {
                HStack(spacing: Fx.Space.m) {
                    Image(systemName: "envelope")
                        .font(Fx.Font.headline)
                        .foregroundStyle(Fx.Color.sea)
                        .accessibilityHidden(true)
                    Text("Reply to \(email)")
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Fx.Space.s)
                    Text("Change")
                        .font(Fx.Font.callout)
                        .foregroundStyle(Fx.Color.sea)
                }
                .frame(minHeight: Fx.minTarget)
            }
        }
        .buttonStyle(FxPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens your profile to change it"))
    }

    private func issueText(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(Fx.Font.footnote)
            .foregroundStyle(Fx.Color.error)
    }
}

// MARK: - Quick phrases

/// Short phrases per tile that a tap adds to the description. App-side on purpose: the adapter
/// stays a description of the e-service, and these are only typing help.
enum QuickPhrases {
    static func phrases(forTile tileID: String?) -> [String] {
        switch tileID {
        case "streetlight":
            [String(localized: "Completely dark"), String(localized: "Flickering"), String(localized: "On during the day")]
        case "pothole":
            [String(localized: "Deep hole"), String(localized: "In the cycle lane"), String(localized: "Dangerous for cyclists")]
        case "winter":
            [String(localized: "Not ploughed"), String(localized: "Slippery, needs gritting"), String(localized: "Snow blocks the path")]
        case "sign":
            [String(localized: "Sign has fallen over"), String(localized: "Barrier is broken"), String(localized: "Sign is hard to see")]
        case "graffiti":
            [String(localized: "Offensive text"), String(localized: "Broken glass"), String(localized: "On a school or playground")]
        case "park":
            [String(localized: "Broken play equipment"), String(localized: "Fallen tree or branch"), String(localized: "Overflowing bins")]
        case "water":
            [String(localized: "Water leaking in the street"), String(localized: "Drain is blocked"), String(localized: "Bad smell")]
        default:
            [String(localized: "Dangerous"), String(localized: "Been like this for a while"), String(localized: "Getting worse")]
        }
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
