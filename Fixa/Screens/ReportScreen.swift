import FixaKit
import MapKit
import PhotosUI
import SwiftUI

struct ReportScreen: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var isLoadingPhotos = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Fx.Space.xl) {
                categorySection
                photoSection
                locationSection
                FxTextEditor(
                    title: String(localized: "What's wrong?"),
                    text: $model.draft.description,
                    prompt: String(localized: "For example: the light by the bus stop has been out since Monday. Write in any language."),
                    issue: model.issue(for: .description)?.message,
                    minHeight: 140
                )
                feedbackSection
                if model.showIssues, !model.issues.isEmpty {
                    FxBanner(
                        kind: .error,
                        title: String(localized: "A few things are missing"),
                        message: String(localized: "Check the marked fields above.")
                    )
                }
                FxPrimaryButton(title: String(localized: "Review"), systemImage: "arrow.forward") {
                    model.goToReview()
                }
            }
            .padding(Fx.Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .fxScreenBackground()
        .navigationTitle(Text("New report"))
        .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: Fx.Space.s) {
            FxSectionHeader(
                String(localized: "Photos"),
                subtitle: String(localized: "Up to 3. They are combined into one picture.")
            )
            if !model.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Fx.Space.s) {
                        ForEach(Array(model.photos.enumerated()), id: \.offset) { index, image in
                            thumbnail(image, index: index)
                        }
                    }
                }
            }
            if model.photos.count < AppModel.maxPhotos {
                HStack(spacing: Fx.Space.s) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: AppModel.maxPhotos - model.photos.count,
                        matching: .images
                    ) {
                        FxSecondaryLabel(title: String(localized: "Choose photos"), systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(FxPressStyle())
                    .accessibilityLabel(Text("Choose photos"))
                    if CameraPicker.isAvailable {
                        FxSecondaryButton(title: String(localized: "Take photo"), systemImage: "camera") {
                            isCameraPresented = true
                        }
                    }
                }
            }
            if isLoadingPhotos {
                ProgressView()
            }
        }
    }

    private func thumbnail(_ image: UIImage, index: Int) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: Fx.Radius.s))
            .overlay(alignment: .topTrailing) {
                Button {
                    model.removePhoto(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Fx.Font.headline)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .frame(width: Fx.minTarget, height: Fx.minTarget)
                }
                .accessibilityLabel(Text("Remove photo \(index + 1)"))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Photo \(index + 1)"))
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isLoadingPhotos = true
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            model.addPhotos(images)
            pickerItems = []
            isLoadingPhotos = false
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
        return VStack(alignment: .leading, spacing: Fx.Space.m) {
            FxToggleRow(
                title: String(localized: "I want a reply"),
                subtitle: String(localized: "The municipality can contact you about this."),
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
                FxTextField(
                    title: String(localized: "First name (optional)"),
                    text: $model.draft.contact.firstName
                )
                FxTextField(
                    title: String(localized: "Last name (optional)"),
                    text: $model.draft.contact.lastName
                )
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
