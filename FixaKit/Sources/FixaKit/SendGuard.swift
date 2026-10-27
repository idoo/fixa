import Foundation

/// Keeps one phone from spamming the municipality: warns about a report that repeats a recent one
/// and caps how many reports go out per hour and per day. Pure; the app owns the history.
public enum SendGuard {
    public enum Decision: Equatable, Sendable {
        case ok
        /// The same problem at the same place was sent at `previous` (the latest such send), with the
        /// municipality's case number if one was read.
        case duplicate(previous: Date, caseNumber: String?)
        /// Too many sends; the next one is allowed at `retryAfter`.
        case tooMany(retryAfter: Date)
    }

    /// Two reports of the same tile this close are the same problem.
    public static let duplicateRadius: Double = 150
    public static let duplicateWindow: TimeInterval = 14 * 24 * 60 * 60
    /// At most `count` sends in any rolling `window`.
    public static let limits: [(count: Int, window: TimeInterval)] = [(5, 60 * 60), (15, 24 * 60 * 60)]

    public static func check(_ draft: ReportDraft, history: [SentRecord], now: Date) -> Decision {
        let duplicates = history.filter { record in
            now.timeIntervalSince(record.date) < duplicateWindow
                && record.tileID == draft.tileID
                && samePlace(draft.coordinate, draft.locationText, record.coordinate, record.locationText)
        }
        if let latest = duplicates.max(by: { $0.date < $1.date }) {
            return .duplicate(previous: latest.date, caseNumber: latest.caseNumber)
        }

        var retryAfter: Date?
        for limit in limits {
            let counted = history.map(\.date).filter { now.timeIntervalSince($0) < limit.window }.sorted()
            guard counted.count >= limit.count else { continue }
            // Once this send ages out, fewer than `count` remain in the window.
            let freed = counted[counted.count - limit.count].addingTimeInterval(limit.window)
            retryAfter = max(retryAfter ?? freed, freed)
        }
        return retryAfter.map { .tooMany(retryAfter: $0) } ?? .ok
    }

    /// Within `duplicateRadius` when both have a pin; otherwise the same place text.
    static func samePlace(_ a: Coordinate?, _ aText: String, _ b: Coordinate?, _ bText: String) -> Bool {
        if let a, let b {
            return distance(a, b) <= duplicateRadius
        }
        let left = normalized(aText)
        return !left.isEmpty && left == normalized(bText)
    }

    /// Case, accents, punctuation and spacing don't matter: "Storvägen 3" = "storvagen  3,".
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "sv_SE"))
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    /// Great-circle distance in metres.
    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }
}
