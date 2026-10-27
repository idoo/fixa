import Foundation

/// A municipality adapter, decoded from `adapters/*.json`.
public struct AdapterSpec: Codable, Sendable, Identifiable {
    /// Adapter format version; an app runs only adapters up to `AdapterUpdatePolicy.supportedSpecVersion`.
    public let specVersion: Int
    /// Lowest app build (CFBundleVersion) whose engine can run this adapter. Absent means any build.
    public let minAppBuild: Int?
    public let id: String
    public let municipality: Municipality
    public let channel: Channel
    public let categories: [Category]
    public let tiles: [Tile]
    public let validation: ValidationRules
    public let emergency: Emergency?
    /// The municipality's own web form for this e-service, opened in Safari when Fixa cannot send
    /// (the resident pastes `WebFallback.text` there). Same host as `channel.baseURL`.
    public let webFormURL: URL
    public let disclaimer: LocalizedText

    public struct Municipality: Codable, Sendable {
        public let name: String
        public let countryCode: String
        public let region: Region
        /// Names a reverse geocoder gives for this municipality (e.g. `["Värmdö", "Värmdö kommun"]`),
        /// used to tell a pin inside the region's box but in a neighbouring municipality.
        public let geocoderNames: [String]
    }

    public struct Region: Codable, Sendable {
        public let center: Coordinate
        public let bbox: BoundingBox

        public var latitudeSpan: Double { bbox.maxLatitude - bbox.minLatitude }
        public var longitudeSpan: Double { bbox.maxLongitude - bbox.minLongitude }

        public func contains(_ c: Coordinate) -> Bool {
            (bbox.minLatitude...bbox.maxLatitude).contains(c.latitude)
                && (bbox.minLongitude...bbox.maxLongitude).contains(c.longitude)
        }
    }

    public struct BoundingBox: Codable, Sendable {
        public let minLatitude: Double
        public let maxLatitude: Double
        public let minLongitude: Double
        public let maxLongitude: Double
    }

    /// How reports reach the municipality. Only `kind == "abou"` exists today.
    public struct Channel: Codable, Sendable {
        public let kind: String
        public let baseURL: String
        public let service: String
        /// Intro page that hands out the session cookie, e.g. `/KSB`.
        public let introPath: String
        /// Path that starts a fresh case, e.g. `/Setup.aspx?Service=KSB&skipintro=true`.
        public let startPath: String
        /// `__EVENTTARGET` of the Next/Slutför button.
        public let nextEventTarget: String
        /// Text the platform shows when the session already has an open case.
        public let sessionLockedMarker: String
        /// Text on the page after Slutför meaning the browser would auto-post the form to finish
        /// processing (Abou's ThankYou page calls `__doPostBack('', '')` on load). Optional.
        public let completionPostBackMarker: String?
        /// Upper bound for those re-posts; defaults to 3.
        public let maxCompletionPostBacks: Int?
        /// Pages in the order the platform shows them. The last page is the summary page whose Next submits the case.
        public let pages: [PageSpec]
        public let upload: UploadSpec?
    }

    public struct PageSpec: Codable, Sendable {
        /// The `PageId` query value of the page.
        public let id: String
        /// Progress stage reported while this page is posted: `sendingReport`, `sendingContact` or `confirming`.
        public let stage: String
        public let fields: [FieldSpec]
    }

    public struct FieldSpec: Codable, Sendable {
        public enum Role: String, Codable, Sendable {
            case category, place, mapChoice, mapAnswer, description, feedback
            case firstName, lastName, phone, email
        }
        public let role: Role
        /// Field key, e.g. `KSB_14`; the input name ends in `$<key>_field$<control>`.
        public let key: String
        public let control: String
        /// Radio value meaning yes (mapChoice, feedback).
        public let yesValue: String?
        /// Radio value meaning no (mapChoice, feedback).
        public let noValue: String?
        /// HTML control type (`select`, `radio`, `text`, `textarea`, `hidden`, `checkbox`). Lets the fallback
        /// accept a control whose `<control>` class was renamed but which is still the same kind of input.
        public let type: String?
        /// Question texts of the field per language, e.g. `{"sv": ["Beskriv felet här"]}`. Used when the key
        /// is not on the page: a control of the same kind under a matching label is used instead.
        public let labels: [String: [String]]?
        /// Other visible texts or values that mean the same radio option, keyed by `yesValue`/`noValue`.
        public let optionSynonyms: [String: [String]]?

        /// Every configured label, in a stable order (sv first), for matching and drift reports.
        public var allLabels: [String] {
            guard let labels else { return [] }
            return labels.keys.sorted { ($0 == "sv" ? "" : $0) < ($1 == "sv" ? "" : $1) }.flatMap { labels[$0] ?? [] }
        }
    }

    public struct UploadSpec: Codable, Sendable {
        /// Page whose POST the upload must precede.
        public let pageID: String
        public let fieldID: String
        public let path: String
        public let filePartName: String
        public let fileName: String
        public let actionPath: String
    }

    public struct Category: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        /// Exact value the form expects.
        public let value: String
        public let title: LocalizedText
        /// Other option values or visible texts the form may use for this category after a rename.
        public let synonyms: [String]?
    }

    public struct Tile: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let symbol: String
        public let categoryID: String
        public let title: LocalizedText
        /// First line of the description sent to the municipality. Absent when the category says it all
        /// ("Övrigt"); then the resident's own text comes first.
        public let swedishSummary: String?
        /// Who looks after this kind of problem, shown under the tile (e.g. municipal streets versus state
        /// or private roads). Absent when the municipality is always the right place.
        public let responsibility: LocalizedText?
        /// The municipality's other e-services for things that don't belong in this one (https only).
        public let links: [TileLink]?
    }

    public struct TileLink: Codable, Sendable, Hashable {
        public let title: LocalizedText
        public let url: URL
    }

    public struct ValidationRules: Codable, Sendable {
        public let descriptionMin: Int
        public let descriptionMax: Int
        public let emailRequiredWhenFeedback: Bool
        public let requireLocation: Bool
    }

    public struct Emergency: Codable, Sendable {
        public let contacts: [EmergencyContact]
        public let rules: [HoursRule]
        public let defaultContactID: String
        public let timeZone: String
        public let note: LocalizedText
        /// Public-holiday calendar on which no rule applies (so `defaultContactID` answers). `"SE"`:
        /// Swedish public holidays plus julafton, nyårsafton and midsommarafton.
        public let holidays: String?
    }

    public struct EmergencyContact: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let title: LocalizedText
        public let phone: String
    }

    /// Applies on the listed ISO weekdays (1 = Monday … 7 = Sunday) from `from` (default "00:00") until
    /// before `until` ("HH:mm", local time): `from <= now < until`.
    public struct HoursRule: Codable, Sendable, Hashable {
        public let isoWeekdays: [Int]
        public let from: String?
        public let until: String
        public let contactID: String
    }

    public func tile(id: String?) -> Tile? {
        guard let id else { return nil }
        return tiles.first { $0.id == id }
    }

    public func category(id: String?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    /// The draft's explicit category, else its tile's category.
    public func category(for draft: ReportDraft) -> Category? {
        category(id: draft.categoryID) ?? category(id: tile(id: draft.tileID)?.categoryID)
    }
}

/// Text in several languages. Encodes as a plain JSON object `{"sv": …, "en": …}`.
public struct LocalizedText: Codable, Sendable, Hashable {
    public let values: [String: String]

    public init(_ values: [String: String]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: String].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    /// The locale's language, else English, else Swedish.
    public func resolve(_ locale: Locale) -> String {
        if let code = locale.language.languageCode?.identifier, let text = values[code] {
            return text
        }
        return values["en"] ?? values["sv"] ?? values.values.sorted().first ?? ""
    }
}

public enum AdapterCatalog {
    public static func load(from url: URL) throws -> AdapterSpec {
        try decode(Data(contentsOf: url))
    }

    /// Decodes an adapter and rejects it when `AdapterSpec.problems` is not empty.
    public static func decode(_ data: Data) throws -> AdapterSpec {
        let spec = try JSONDecoder().decode(AdapterSpec.self, from: data)
        let problems = spec.problems
        guard problems.isEmpty else { throw AdapterSpecError.invalid(problems) }
        return spec
    }

    /// Adapters shipped inside FixaKit, sorted by id.
    public static func bundled() -> [AdapterSpec] {
        var seen = Set<String>()
        return bundledURLs()
            .compactMap { try? load(from: $0) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.id < $1.id }
    }

    /// The shipped adapter with this id, decoded once. Text that must not come from a download
    /// (the disclaimer) is read from here, never from the running, possibly downloaded, adapter.
    public static func shipped(id: String) -> AdapterSpec? {
        shippedAdapters.first { $0.id == id }
    }

    private static let shippedAdapters = bundled()

    static func bundledURLs() -> [URL] {
        let nested = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "adapters") ?? []
        let flat = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return nested + flat
    }
}
