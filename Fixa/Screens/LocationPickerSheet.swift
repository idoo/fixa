import FixaKit
import MapKit
import SwiftUI

/// Tap the map to place the pin, search an address, or use the current location.
struct LocationPickerSheet: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var pin: CLLocationCoordinate2D?
    @State private var address = ""
    @State private var position: MapCameraPosition
    @State private var search: AddressSearch
    @State private var isLocating = false
    @State private var locationProblem: String?
    @State private var geocodeTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    init(spec: AdapterSpec) {
        self.spec = spec
        let region = spec.municipality.region.mapRegion
        _position = State(initialValue: .region(region))
        _search = State(initialValue: AddressSearch(region: region))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                if !search.suggestions.isEmpty, searchFocused {
                    suggestionList
                } else {
                    map
                }
                footer
            }
            .background(Fx.Color.paper)
            .navigationTitle(Text("Where is it?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadFromDraft)
    }

    // MARK: Parts

    private var searchField: some View {
        HStack(spacing: Fx.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Fx.Color.ink2)
                .accessibilityHidden(true)
            TextField(
                String(localized: "Search for an address or place"),
                text: Binding(get: { search.query }, set: { search.query = $0 })
            )
            .focused($searchFocused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Fx.Color.ink2)
                        .frame(width: Fx.minTarget, height: Fx.minTarget)
                }
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .font(Fx.Font.body)
        .padding(.horizontal, Fx.Space.m)
        .frame(minHeight: Fx.minTarget)
        .fxOutline(RoundedRectangle(cornerRadius: Fx.Radius.s), fill: Fx.Color.card)
        .padding(Fx.Space.l)
    }

    private var suggestionList: some View {
        List(search.suggestions) { suggestion in
            Button {
                choose(suggestion)
            } label: {
                VStack(alignment: .leading, spacing: Fx.Space.xs) {
                    Text(suggestion.title)
                        .font(Fx.Font.body)
                        .foregroundStyle(Fx.Color.ink)
                    if !suggestion.subtitle.isEmpty {
                        Text(suggestion.subtitle)
                            .font(Fx.Font.footnote)
                            .foregroundStyle(Fx.Color.ink2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
            }
            .listRowBackground(Fx.Color.card)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let pin {
                    Marker(address, coordinate: pin)
                        .tint(Fx.Color.sea)
                }
                UserAnnotation()
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    setPin(coordinate, address: nil)
                }
            }
            .accessibilityLabel(Text("Map. Tap to place the pin where the problem is."))
            .overlay(alignment: .bottomTrailing) {
                FxIconButton(
                    systemImage: "location",
                    label: isLocating ? String(localized: "Finding you…") : String(localized: "Use my location"),
                    isLoading: isLocating
                ) {
                    useMyLocation()
                }
                // Sit above the Maps logo / legal row so they never collide (narrow screens, RTL).
                .padding(.horizontal, Fx.Space.l)
                .padding(.bottom, Fx.Space.xxl)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Fx.Space.m) {
            if let pin, !spec.municipality.region.contains(Coordinate(pin)) {
                FxBanner(
                    kind: .warning,
                    title: String(localized: "Outside \(spec.municipality.name)"),
                    message: String(localized: "This spot looks outside the municipality. Move the pin if that's wrong.")
                )
            }
            if let locationProblem {
                FxBanner(kind: .info, title: locationProblem)
            }
            HStack(spacing: Fx.Space.s) {
                Image(systemName: pin == nil ? "hand.tap" : "mappin.and.ellipse")
                    .foregroundStyle(Fx.Color.sea)
                    .accessibilityHidden(true)
                Text(pinSummary)
                    .font(Fx.Font.callout)
                    .foregroundStyle(pin == nil ? Fx.Color.ink2 : Fx.Color.ink)
                Spacer(minLength: 0)
            }
            FxPrimaryButton(title: String(localized: "Use this place"), systemImage: "checkmark") {
                confirm()
            }
            .disabled(pin == nil)
            .opacity(pin == nil ? 0.5 : 1)
        }
        .padding(Fx.Space.l)
        .background(Fx.Color.paper)
    }

    private var pinSummary: String {
        guard pin != nil else { return String(localized: "Tap the map where the problem is.") }
        return address.isEmpty ? String(localized: "Finding the address…") : address
    }

    // MARK: Actions

    private func loadFromDraft() {
        guard let coordinate = model.draft.coordinate else { return }
        pin = coordinate.clLocation
        address = model.draft.locationText
        position = .region(MKCoordinateRegion(center: coordinate.clLocation, latitudinalMeters: 600, longitudinalMeters: 600))
    }

    private func setPin(_ coordinate: CLLocationCoordinate2D, address knownAddress: String?) {
        pin = coordinate
        geocodeTask?.cancel()
        if let knownAddress {
            address = knownAddress
            return
        }
        address = ""
        geocodeTask = Task {
            let text = await ReverseGeocoder.address(for: coordinate)
            guard !Task.isCancelled else { return }
            address = text ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        }
    }

    private func choose(_ suggestion: AddressSearch.Suggestion) {
        searchFocused = false
        Task {
            guard let (coordinate, text) = await search.resolve(suggestion) else { return }
            setPin(coordinate, address: text)
            position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
            search.query = ""
        }
    }

    private func useMyLocation() {
        guard !isLocating else { return }
        isLocating = true
        locationProblem = nil
        Task {
            defer { isLocating = false }
            do {
                let coordinate = try await LocationProvider.currentCoordinate()
                setPin(coordinate, address: nil)
                position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400))
            } catch LocationProvider.Failure.denied {
                locationProblem = String(localized: "Location is off for Fixa. You can turn it on in Settings, or tap the map instead.")
            } catch {
                locationProblem = String(localized: "Couldn't find your location. Tap the map instead.")
            }
        }
    }

    private func confirm() {
        guard let pin else { return }
        model.draft.coordinate = Coordinate(pin)
        model.draft.locationText = address
        dismiss()
    }
}
