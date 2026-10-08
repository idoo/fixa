import MapKit
import Observation

/// Address search limited to the municipality region.
@Observable
@MainActor
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Hashable {
        let id: Int
        let title: String
        let subtitle: String
    }

    var query = "" {
        didSet {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                completer.cancel()
                suggestions = []
            } else {
                completer.queryFragment = query
            }
        }
    }

    private(set) var suggestions: [Suggestion] = []
    @ObservationIgnored private var completions: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private let region: MKCoordinateRegion

    init(region: MKCoordinateRegion) {
        self.region = region
        super.init()
        completer.delegate = self
        completer.region = region
        completer.regionPriority = .required
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            completions = self.completer.results
            suggestions = completions.enumerated().map { index, completion in
                Suggestion(id: index, title: completion.title, subtitle: completion.subtitle)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            completions = []
            suggestions = []
        }
    }

    /// Resolves a suggestion to a coordinate and a display address.
    func resolve(_ suggestion: Suggestion) async -> (CLLocationCoordinate2D, String)? {
        guard completions.indices.contains(suggestion.id) else { return nil }
        let request = MKLocalSearch.Request(completion: completions[suggestion.id])
        request.region = region
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let text = item.address?.shortAddress ?? [suggestion.title, suggestion.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return (item.location.coordinate, text)
    }
}
