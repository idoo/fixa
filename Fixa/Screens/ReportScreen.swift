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
                            .foregroundStyle(Fx.Color.accent)
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
            .buttonStyle(.plain)
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
                                .tint(Fx.Color.accent)
                        }
                        .id(coordinate.key)
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    HStack(spacing: Fx.Space.s) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Fx.Color.accent)
                            .accessibilityHidden(true)
                        Text(locationSummary)
                            .font(Fx.Font.body)
                            .foregroundStyle(model.draft.coordinate == nil ? Fx.Color.inkSoft : Fx.Color.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: Fx.Space.s)
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(Fx.Color.inkSoft)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Fx.minTarget)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the map"))
            if let issue = model.issue(for: .location) {
                issueText(issue.message)
            }
        }
    }

    private var locationSummary: String {
        if model.draft.coordinate == nil {
            return String(localized: "Choose the place on a map")
        }
        let text = model.draft.locationText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? String(localized: "Pin placed on the map") : text
    }

    // MARK: Feedback

    private var feedbackSection: some View {
        @Bindable var model = model
        let nameLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Fx.Space.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Fx.Space.s))
        return VStack(alignment: .leading, spacing: Fx.Space.m) {
            FxSectionHeader(String(localized: "Reply"), subtitle: String(localized: "Optional"))
            FxToggleRow(
                title: String(localized: "Contact me about this"),
                isOn: $model.draft.wantsFeedback.animation()
            )
            if model.draft.wantsFeedback {
                FxTextField(
                    title: String(localized: "E-mail"),
                    text: $model.draft.contact.email,
                    prompt: String(localized: "name@example.com"),
                    kind: .email,
                    issue: model.issue(for: .email)?.message
                )
                nameLayout {
                    FxTextField(
                        title: String(localized: "First name (optional)"),
                        text: $model.draft.contact.firstName
                    )
                    FxTextField(
                        title: String(localized: "Last name (optional)"),
                        text: $model.draft.contact.lastName
                    )
                }
                FxTextField(
                    title: String(localized: "Phone (optional)"),
                    text: $model.draft.contact.phone,
                    kind: .phone,
                    issue: model.issue(for: .phone)?.message
                )
                Text("Saved on this phone for next time.")
                    .font(Fx.Font.footnote)
                    .foregroundStyle(Fx.Color.inkSoft)
            }
        }
    }

    private func issueText(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(Fx.Font.footnote)
            .foregroundStyle(Fx.Color.accent)
    }
}
