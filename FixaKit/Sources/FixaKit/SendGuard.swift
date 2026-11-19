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

    /// A repeat has the same tile, the same place (pin, place text, or for forms without a place the
    /// answer naming it) and, when the earlier record has one, the same subject. `checksDuplicate: false`
    /// checks the rate limit only.
    public static func check(_ draft: ReportDraft, spec: AdapterSpec?, history: [SentRecord], now: Date,
                             checksDuplicate: Bool = true) -> Decision {
        if checksDuplicate {
            let place = place(of: draft, spec: spec)
            let subject = subject(of: draft, spec: spec)
            let duplicates = history.filter { record in
                now.timeIntervalSince(record.date) < duplicateWindow
                    && record.tileID == draft.tileID
                    && samePlace(draft.coordinate, place, record.coordinate, record.locationText)
                    && (record.subject == nil || record.subject == subject)
            }
            if let latest = duplicates.max(by: { $0.date < $1.date }) {
                return .duplicate(previous: latest.date, caseNumber: latest.caseNumber)
            }
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

    /// `AdapterSpec.placeText(for:)`, or the trimmed place text without a spec.
    static func place(of draft: ReportDraft, spec: AdapterSpec?) -> String {
        spec?.placeText(for: draft) ?? draft.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The draft's identifying answers as one normalized string: `choice`, `multiChoice` and `text`
    /// answers of the questions it shows, the place question left out, sorted by question id. Nil
    /// without a spec or without such answers, so reports without answers compare as before.
    static func subject(of draft: ReportDraft, spec: AdapterSpec?) -> String? {
        guard let spec else { return nil }
        let kinds: Set<AdapterSpec.Question.Kind> = [.choice, .multiChoice, .text]
        let parts = spec.visibleQuestions(tileID: draft.tileID)
            .filter { kinds.contains($0.kind) && $0.id != spec.placeQuestion }
            .sorted { $0.id < $1.id }
            .compactMap { question -> String? in
                let values = (draft.answers[question.id] ?? []).map(normalized).filter { !$0.isEmpty }.sorted()
                return values.isEmpty ? nil : question.id + "=" + values.joined(separator: "|")
            }
        return parts.isEmpty ? nil : parts.joined(separator: ";")
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
