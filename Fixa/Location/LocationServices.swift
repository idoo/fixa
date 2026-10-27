import CoreLocation
import FixaKit
import ImageIO
import MapKit

extension Coordinate {
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }

    /// "59.3262,18.3856": stable key for view identity.
    var key: String { "\(latitude),\(longitude)" }
}

extension AdapterSpec.Region {
    var mapRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center.clLocation,
            span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
        )
    }
}

/// One-shot current location. Every lookup is bounded by a timeout, so nothing can spin forever.
/// Authorization is requested only by an explicit lookup when it hasn't been decided yet.
@MainActor
enum LocationProvider {
    enum Failure: Error, Sendable {
        case denied
        case restricted
        case servicesOff
        case unavailable
        case timedOut
    }

    /// What Fixa may do with location right now, read without prompting.
    enum Access: Equatable, Sendable {
        case notDetermined
        case allowed(precise: Bool)
        case denied
        case restricted
        case servicesOff
    }

    /// A found position; `isApproximate` when the user shares only an approximate location.
    struct Fix: Sendable {
        let coordinate: Coordinate
        let isApproximate: Bool
    }

    private static let manager = CLLocationManager()

    /// Current authorization. `locationServicesEnabled()` blocks, so it runs off the main actor.
    static func access() async -> Access {
        let servicesOn = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        guard servicesOn else { return .servicesOff }
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        default: return .allowed(precise: manager.accuracyAuthorization == .fullAccuracy)
        }
    }

    /// Quiet lookup: nil on any failure or after `timeout`.
    static func currentCoordinate(timeout: Duration) async -> Coordinate? {
        try? await currentFix(timeout: timeout).coordinate
    }

    /// Lookup that says why it failed. The clock starts once the permission prompt (if any) is answered,
    /// then gives up with `Failure.timedOut` after `timeout`.
    static func currentFix(timeout: Duration) async throws -> Fix {
        try await withThrowingTaskGroup(of: Fix.self) { group in
            group.addTask { try await liveFix() }
            group.addTask {
                while await isAskingPermission() {
                    try await Task.sleep(for: .milliseconds(500))
                }
                try await Task.sleep(for: timeout)
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw Failure.unavailable }
            return first
        }
    }

    private static func isAskingPermission() -> Bool {
        manager.authorizationStatus == .notDetermined
    }

    private static func liveFix() async throws -> Fix {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDeniedGlobally { throw Failure.servicesOff }
            if update.authorizationRestricted { throw Failure.restricted }
            if update.authorizationDenied { throw Failure.denied }
            guard let location = update.location, location.horizontalAccuracy >= 0 else { continue }
            if update.accuracyLimited || manager.accuracyAuthorization == .reducedAccuracy {
                return Fix(coordinate: Coordinate(location.coordinate), isApproximate: true)
            }
            if location.horizontalAccuracy < 200 {
                return Fix(coordinate: Coordinate(location.coordinate), isApproximate: false)
            }
        }
        throw Failure.unavailable
    }
}

/// Address text for a coordinate, via MapKit reverse geocoding.
@MainActor
enum ReverseGeocoder {
    /// Farther than this from the pin, the found address is only "near" it.
    static let exactRadiusMeters: CLLocationDistance = 100

    /// The address of the nearest result in Swedish (the text goes to the municipality as written).
    /// A result over `exactRadiusMeters` away is prefixed "nära " so it never claims the exact spot.
    static func address(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: "sv_SE")
        guard let items = try? await request.mapItems,
              let item = items.min(by: { $0.location.distance(from: location) < $1.location.distance(from: location) }),
              let text = item.address?.shortAddress ?? item.address?.fullAddress ?? item.name else { return nil }
        return item.location.distance(from: location) > exactRadiusMeters ? "nära \(text)" : text
    }
}

/// Where a photo was taken, read from its original file. Fixa re-encodes every photo before
/// sending, which drops this metadata, so the place only ever reaches the report as a pin.
enum PhotoLocation {
    static func coordinate(in data: Data) -> Coordinate? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue else { return nil }
        let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S"
        let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W"
        let coordinate = CLLocationCoordinate2D(latitude: south ? -latitude : latitude, longitude: west ? -longitude : longitude)
        guard CLLocationCoordinate2DIsValid(coordinate), latitude != 0 || longitude != 0 else { return nil }
        return Coordinate(coordinate)
    }
}
