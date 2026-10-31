import FixaKit
import MapKit
import SwiftUI
import UIKit

/// Centre-pin location picker: the pin stays in the middle and the map moves under it.
/// Place it by moving the map, tapping a spot (re-centres there), searching an address,
/// or the full-width "Use my current location" row under the search field.
struct LocationPickerSheet: View {
    let spec: AdapterSpec
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.fxHaptics) private var haptics
    @Environment(\.fxReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The placed spot; nil until the user places it (or a saved draft brings one).
    @State private var pin: CLLocationCoordinate2D?
    @State private var address = ""
    @State private var position: MapCameraPosition
    /// The camera centre after the last move, i.e. where the drawn pin points.
    @State private var centre: CLLocationCoordinate2D
    @State private var cameraDistance: Double
    /// Where a programmatic camera move is heading; its camera-change end must not count as the user's move.
    @State private var pendingCentre: CLLocationCoordinate2D?
    @State private var search: AddressSearch
    @State private var locate: LocateState = .idle
    @State private var locateTask: Task<Void, Never>?
    @State private var geocodeTask: Task<Void, Never>?
    @State private var didAutoLocate = false
    @State private var foundCount = 0
    /// The other kommun the pin is in, from reverse geocoding; nil while inside or unknown.
    @State private var otherKommun: String?
    @FocusState private var searchFocused: Bool
    /// Height of the search + locate controls; the list (and the map at accessibility sizes) starts below it.
    @State private var controlsHeight: CGFloat = 0

    /// Opening view when nothing is known yet: Gustavsberg centrum at about 3 km.
    private static let gustavsberg = CLLocationCoordinate2D(latitude: 59.3262, longitude: 18.3856)
    private static let overviewMeters: Double = 3000
    private static let closeMeters: Double = 400
    private static let nudgeMeters: Double = 20
    private static let locateTimeout: Duration = .seconds(15)

    init(spec: AdapterSpec) {
        self.spec = spec
        let region = spec.municipality.region
        let start = region.contains(Coordinate(Self.gustavsberg)) ? Self.gustavsberg : region.center.clLocation
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: start, latitudinalMeters: Self.overviewMeters, longitudinalMeters: Self.overviewMeters
        )))
        _centre = State(initialValue: start)
        _cameraDistance = State(initialValue: Self.overviewMeters * 2)
        _pendingCentre = State(initialValue: start)
        _search = State(initialValue: AddressSearch(region: region.mapRegion))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // One tree for the controls so the search field keeps focus when suggestions appear.
                ZStack(alignment: .top) {
                    Group {
                        if showsSuggestions {
                            suggestionList
                                .padding(.top, controlsHeight)
                        } else {
                            map
                                .padding(.top, controlsFloat ? 0 : controlsHeight)
                        }
                    }
                    VStack(spacing: Fx.Space.s) {
                        searchField
                        locateRow
                    }
                    .padding(controlsFloat ? Fx.Space.m : Fx.Space.l)
                    .background(controlsFloat ? Color.clear : Fx.Color.paper)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
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
        .sensoryFeedback(.success, trigger: foundCount) { _, _ in haptics }
        .onAppear(perform: loadFromDraft)
        .task { await refreshAccess(autoLocate: true) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshAccess(autoLocate: false) }
        }
        .task(id: search.query) { await announceSearchResults() }
        .onDisappear {
            locateTask?.cancel()
            geocodeTask?.cancel()
        }
    }

    private var showsSuggestions: Bool { !search.suggestions.isEmpty && searchFocused }

    /// Controls float over the map; at accessibility sizes they stack above it so they never cover the pin.
    private var controlsFloat: Bool { !showsSuggestions && !dynamicTypeSize.isAccessibilitySize }

    // MARK: Parts

    private var searchField: some View {
        HStack(spacing: Fx.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Fx.Color.ink2)
                .accessibilityHidden(true)
            TextField(
                text: Binding(get: { search.query }, set: { search.query = $0 }),
                prompt: Text("Search for an address or place").foregroundStyle(Fx.Color.ink2)
            ) {
                Text("Search for an address or place")
            }
            .focused($searchFocused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityIdentifier("location.search")
            .onSubmit {
                if let first = search.suggestions.first { choose(first) }
            }
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
        .foregroundStyle(Fx.Color.ink)
        .padding(.horizontal, Fx.Space.m)
        .frame(minHeight: Fx.minTarget)
        .fxOutline(
            RoundedRectangle(cornerRadius: Fx.Radius.s, style: .continuous),
            fill: Fx.Color.card,
            outline: searchFocused ? Fx.Color.sea : Fx.Color.fieldBorder,
            width: searchFocused ? Fx.Border.emphasis : Fx.Border.hairline
        )
    }

    /// Full-width "Use my current location" row with its state; extra control under it when needed.
    private var locateRow: some View {
        let shape = RoundedRectangle(cornerRadius: Fx.Radius.m, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: useMyLocation) {
                HStack(alignment: .center, spacing: Fx.Space.m) {
                    locateIcon
                        .frame(minWidth: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(locate.title)
                            .font(Fx.Font.headline)
                            .foregroundStyle(locate.isWarning ? Fx.Color.ink : Fx.Color.sea)
                        if let subtitle = locate.subtitle(address: address) {
                            Text(subtitle)
                                .font(Fx.Font.footnote)
                                .foregroundStyle(Fx.Color.ink2)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Fx.Space.m)
                .padding(.vertical, Fx.Space.s)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(FxPressStyle())
            .disabled(locate == .finding)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityInputLabels([Text("Use my current location"), Text("My location")])

            if let extra = locate.extraAction {
                Button {
                    switch extra {
                    case .openSettings: openSettings()
                    case .tryAgain: useMyLocation()
                    }
                } label: {
                    Text(extra.title)
                        .font(Fx.Font.callout.weight(.semibold))
                        .underline()
                        .foregroundStyle(Fx.Color.sea)
                        .frame(maxWidth: .infinity, minHeight: Fx.minTarget, alignment: .leading)
                        .padding(.horizontal, Fx.Space.m)
                        .contentShape(.rect)
                }
                .buttonStyle(FxPressStyle())
            }
        }
        .fxOutline(shape, fill: Fx.Color.card, outline: locate.isWarning ? Fx.Color.fieldBorder : Fx.Color.sea, width: Fx.Border.emphasis)
    }

    @ViewBuilder private var locateIcon: some View {
        switch locate {
        case .finding:
            ProgressView().tint(Fx.Color.sea)
        case .found:
            Image(systemName: "checkmark.circle.fill")
                .font(Fx.Font.headline)
                .foregroundStyle(Fx.Color.success)
        case .idle:
            Image(systemName: "location.fill")
                .font(Fx.Font.headline)
                .foregroundStyle(Fx.Color.sea)
        default:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Fx.Font.headline)
                .foregroundStyle(Fx.Color.ink)
        }
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
                UserAnnotation()
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                cameraMoved(to: context.camera.centerCoordinate, distance: context.camera.distance)
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                place(coordinate, address: nil, moveCamera: true)
            }
            .overlay { centrePin }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Map. Move the map so the problem is under the centre mark."))
            .accessibilityValue(Text(pinSummary))
            .accessibilityAction(named: Text("Put the pin at the centre")) {
                place(centre, address: nil, moveCamera: false)
            }
            .accessibilityAction(named: Text("Move pin north 20 m")) { nudge(north: Self.nudgeMeters, east: 0) }
            .accessibilityAction(named: Text("Move pin south 20 m")) { nudge(north: -Self.nudgeMeters, east: 0) }
            .accessibilityAction(named: Text("Move pin east 20 m")) { nudge(north: 0, east: Self.nudgeMeters) }
            .accessibilityAction(named: Text("Move pin west 20 m")) { nudge(north: 0, east: -Self.nudgeMeters) }
        }
    }

    /// The fixed pin: its tip sits on the map centre. Faded until a place is chosen.
    private var centrePin: some View {
        Image(systemName: "mappin")
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(Fx.Color.sea)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .opacity(pin == nil ? 0.6 : 1)
            .alignmentGuide(VerticalAlignment.center) { $0[.bottom] }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Fx.Space.m) {
            if isOutside {
                if let otherKommun {
                    FxBanner(
                        kind: .warning,
                        title: String(localized: "This place is in \(otherKommun). Report it to that kommun.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                } else {
                    FxBanner(
                        kind: .warning,
                        title: String(localized: "The pin is outside \(spec.municipality.name)", bundle: L10n.bundle, locale: L10n.locale),
                        message: String(localized: "Fixa only sends reports to \(spec.municipality.name). Search for the address of the problem, or move the map.", bundle: L10n.bundle, locale: L10n.locale)
                    )
                }
            }
            Text("Move the map so the pin is on the problem.")
                .font(Fx.Font.footnote)
                .foregroundStyle(Fx.Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                // Visual drag hint; VoiceOver hears the map's own label and pin actions instead.
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: Fx.Space.s) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Fx.Color.sea)
                    .accessibilityHidden(true)
                Text(pinSummary)
                    .font(Fx.Font.callout)
                    .foregroundStyle(pin == nil ? Fx.Color.ink2 : Fx.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            FxPrimaryButton(title: confirmTitle, systemImage: isOutside ? nil : "checkmark") {
                confirm()
            }
            .disabled(pin == nil || isOutside)
            .accessibilityHint(Text(confirmHint))
            .accessibilityIdentifier("location.confirm")
        }
        .padding(Fx.Space.l)
        .background(Fx.Color.paper)
    }

    /// Outside the adapter's box at once; another kommun once reverse geocoding names one.
    private var isOutside: Bool {
        guard let pin else { return false }
        return otherKommun != nil || !spec.municipality.region.contains(Coordinate(pin))
    }

    private var confirmTitle: String {
        isOutside
            ? String(localized: "Place is outside \(spec.municipality.name)", bundle: L10n.bundle, locale: L10n.locale)
            : String(localized: "Use this place", bundle: L10n.bundle, locale: L10n.locale)
    }

    private var confirmHint: String {
        pin == nil ? String(localized: "Put the pin on the map first", bundle: L10n.bundle, locale: L10n.locale) : ""
    }

    private var pinSummary: String {
        guard pin != nil else { return String(localized: "No place chosen yet.", bundle: L10n.bundle, locale: L10n.locale) }
        return address.isEmpty ? String(localized: "Finding the address…", bundle: L10n.bundle, locale: L10n.locale) : address
    }

    // MARK: Actions

    private func loadFromDraft() {
        guard pin == nil, let coordinate = model.draft.coordinate else { return }
        pin = coordinate.clLocation
        otherKommun = model.outsideMunicipalityName
        address = model.draft.locationText
        moveCamera(to: coordinate.clLocation, meters: 600)
    }

    /// Reads authorization without prompting; on open, locates automatically when already allowed.
    private func refreshAccess(autoLocate: Bool) async {
        let access = await LocationProvider.access()
        switch access {
        case .allowed(let precise):
            if !precise, locate != .finding { locate = .approximate }
            if precise, locate.isPermissionState { locate = .idle }
            if autoLocate, !didAutoLocate, pin == nil, model.draft.coordinate == nil {
                didAutoLocate = true
                useMyLocation()
            }
        case .notDetermined:
            if locate.isPermissionState { locate = .idle }
        case .denied:
            locate = .notAllowed(canOpenSettings: true)
        case .restricted:
            locate = .notAllowed(canOpenSettings: false)
        case .servicesOff:
            locate = .servicesOff
        }
    }

    private func useMyLocation() {
        guard locate != .finding else { return }
        searchFocused = false
        locate = .finding
        locateTask?.cancel()
        locateTask = Task {
            do {
                let fix = try await LocationProvider.currentFix(timeout: Self.locateTimeout)
                guard !Task.isCancelled else { return }
                if fix.isApproximate {
                    locate = .approximate
                    moveCamera(to: fix.coordinate.clLocation, meters: Self.overviewMeters)
                } else {
                    locate = .found
                    foundCount += 1
                    place(fix.coordinate.clLocation, address: nil, moveCamera: false)
                    moveCamera(to: fix.coordinate.clLocation, meters: Self.closeMeters)
                }
            } catch LocationProvider.Failure.denied {
                locate = .notAllowed(canOpenSettings: true)
            } catch LocationProvider.Failure.restricted {
                locate = .notAllowed(canOpenSettings: false)
            } catch LocationProvider.Failure.servicesOff {
                locate = .servicesOff
            } catch {
                guard !Task.isCancelled else { return }
                locate = .failed
            }
            guard !Task.isCancelled else { return }
            // A found pin is announced with its address; every other outcome is said here.
            if locate.isWarning {
                let text = [locate.title, locate.subtitle(address: address)].compactMap { $0 }.joined(separator: ". ")
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }

    /// End of any camera move. A user's move places the pin at the new centre.
    private func cameraMoved(to coordinate: CLLocationCoordinate2D, distance: Double) {
        centre = coordinate
        cameraDistance = distance
        if let pending = pendingCentre {
            pendingCentre = nil
            if Self.meters(from: pending, to: coordinate) < 15 { return }
        }
        place(coordinate, address: nil, moveCamera: false)
    }

    /// Sets the pin, geocodes it when the address isn't known, announces the result to VoiceOver.
    private func place(_ coordinate: CLLocationCoordinate2D, address knownAddress: String?, moveCamera move: Bool) {
        if locate == .found, let current = pin, Self.meters(from: current, to: coordinate) > 1 {
            locate = .idle
        }
        pin = coordinate
        otherKommun = nil
        if move { moveCamera(to: coordinate, distance: cameraDistance) }
        geocodeTask?.cancel()
        if let knownAddress {
            address = knownAddress
        } else {
            address = ""
        }
        geocodeTask = Task {
            let place = await ReverseGeocoder.place(for: coordinate)
            guard !Task.isCancelled else { return }
            otherKommun = AppModel.otherMunicipality(place, spec: spec, coordinate: Coordinate(coordinate))
            if knownAddress == nil {
                address = place?.address ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
            }
            announcePlacement()
        }
    }

    private func announcePlacement() {
        var text = String(localized: "Pin placed: \(address)", bundle: L10n.bundle, locale: L10n.locale)
        if let otherKommun {
            text += " " + String(localized: "This place is in \(otherKommun). Report it to that kommun.", bundle: L10n.bundle, locale: L10n.locale)
        } else if isOutside {
            text += " " + String(localized: "The pin is outside \(spec.municipality.name)", bundle: L10n.bundle, locale: L10n.locale)
        }
        AccessibilityNotification.Announcement(text).post()
    }

    private func nudge(north: Double, east: Double) {
        let from = pin ?? centre
        let latitude = from.latitude + north / 111_320
        let longitude = from.longitude + east / (111_320 * cos(from.latitude * .pi / 180))
        place(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), address: nil, moveCamera: true)
    }

    /// Once typing pauses, tells VoiceOver how many places the search found (or none).
    private func announceSearchResults() async {
        guard !search.query.trimmingCharacters(in: .whitespaces).isEmpty, searchFocused else { return }
        guard (try? await Task.sleep(for: .seconds(1.5))) != nil, searchFocused else { return }
        let count = search.suggestions.count
        let text = count == 0
            ? String(localized: "No places found. Try another spelling, or move the map.", bundle: L10n.bundle, locale: L10n.locale)
            : String(localized: "Places found: \(count)", bundle: L10n.bundle, locale: L10n.locale)
        AccessibilityNotification.Announcement(text).post()
    }

    private func choose(_ suggestion: AddressSearch.Suggestion) {
        searchFocused = false
        Task {
            guard let (coordinate, text) = await search.resolve(suggestion) else {
                AccessibilityNotification.Announcement(
                    String(localized: "Couldn't look up that place. Try another search, or move the map.", bundle: L10n.bundle, locale: L10n.locale)
                ).post()
                return
            }
            place(coordinate, address: text, moveCamera: false)
            moveCamera(to: coordinate, meters: 600)
            search.query = ""
        }
    }

    private func moveCamera(to coordinate: CLLocationCoordinate2D, meters: Double) {
        moveCamera(to: coordinate, distance: meters * 2)
    }

    private func moveCamera(to coordinate: CLLocationCoordinate2D, distance: Double) {
        pendingCentre = coordinate
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            position = .camera(MapCamera(centerCoordinate: coordinate, distance: distance))
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func confirm() {
        guard let pin, !isOutside else { return }
        model.draft.coordinate = Coordinate(pin)
        // Chosen here, so no longer the automatic "your current location" pin, even if unchanged.
        model.pinIsAutomatic = false
        // The address comes from the geocoder; a place the resident typed stays as written.
        if !model.placeTextIsTyped {
            model.draft.locationText = address
        }
        dismiss()
    }

    private static func meters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

/// State of the "Use my current location" row.
private enum LocateState: Equatable {
    case idle
    case finding
    case found
    case notAllowed(canOpenSettings: Bool)
    case approximate
    case servicesOff
    case failed

    enum Extra {
        case openSettings, tryAgain

        var title: String {
            switch self {
            case .openSettings: String(localized: "Open Settings", bundle: L10n.bundle, locale: L10n.locale)
            case .tryAgain: String(localized: "Try again", bundle: L10n.bundle, locale: L10n.locale)
            }
        }
    }

    var title: String {
        switch self {
        case .idle: String(localized: "Use my current location", bundle: L10n.bundle, locale: L10n.locale)
        case .finding: String(localized: "Finding where you are…", bundle: L10n.bundle, locale: L10n.locale)
        case .found: String(localized: "Pin placed where you are", bundle: L10n.bundle, locale: L10n.locale)
        case .notAllowed: String(localized: "Fixa isn't allowed to use your location", bundle: L10n.bundle, locale: L10n.locale)
        case .approximate: String(localized: "Your iPhone shares only an approximate location", bundle: L10n.bundle, locale: L10n.locale)
        case .servicesOff: String(localized: "Location Services are off on this iPhone", bundle: L10n.bundle, locale: L10n.locale)
        case .failed: String(localized: "Couldn't find where you are", bundle: L10n.bundle, locale: L10n.locale)
        }
    }

    func subtitle(address: String) -> String? {
        switch self {
        case .idle: String(localized: "Puts the pin where you are standing", bundle: L10n.bundle, locale: L10n.locale)
        case .finding: String(localized: "This can take a few seconds outdoors", bundle: L10n.bundle, locale: L10n.locale)
        case .found: address.isEmpty ? String(localized: "Finding the address…", bundle: L10n.bundle, locale: L10n.locale) : address
        case .notAllowed: String(localized: "Search for the address above, or allow it in Settings.", bundle: L10n.bundle, locale: L10n.locale)
        case .approximate: String(localized: "Turn on Precise Location in Settings, or move the map yourself.", bundle: L10n.bundle, locale: L10n.locale)
        case .servicesOff: String(localized: "Settings › Privacy & Security › Location Services", bundle: L10n.bundle, locale: L10n.locale)
        case .failed: String(localized: "Search for the address above, or move the map.", bundle: L10n.bundle, locale: L10n.locale)
        }
    }

    var extraAction: Extra? {
        switch self {
        case .notAllowed(let canOpenSettings): canOpenSettings ? .openSettings : nil
        case .approximate: .openSettings
        case .failed: .tryAgain
        default: nil
        }
    }

    var isWarning: Bool {
        switch self {
        case .idle, .finding, .found: false
        default: true
        }
    }

    /// States that only reflect permission/settings and should follow a fresh authorization read.
    var isPermissionState: Bool {
        switch self {
        case .notAllowed, .approximate, .servicesOff: true
        default: false
        }
    }
}
