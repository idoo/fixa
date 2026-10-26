import CoreLocation
import FixaKit
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

/// One-shot "Use my location". Authorization is requested only when the user taps the button.
@MainActor
enum LocationProvider {
    enum Failure: Error {
        case denied
        case unavailable
    }

    static func currentCoordinate() async throws -> CLLocationCoordinate2D {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw Failure.denied
            }
            if let location = update.location, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 200 {
                return location.coordinate
            }
        }
        throw Failure.unavailable
    }
}

/// Address text for a coordinate, via MapKit reverse geocoding.
@MainActor
enum ReverseGeocoder {
    static func address(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: "sv_SE")
        guard let item = try? await request.mapItems.first else { return nil }
        return item.address?.shortAddress ?? item.address?.fullAddress ?? item.name
    }
}
