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
    /// Where residents ask the municipality about anything, including a report they sent: its own web
    /// page (Fixa never calls or e-mails it). Optional; an https page on the municipality's domain.
    public let contact: Contact?
    /// Hosts whose pages Fixa opens in an in-app Safari view (lowercase, each on the municipality's
    /// domain). Every other link opens in Safari. Absent means every link opens in Safari.
    public let allowedWebHosts: [String]?
    /// Present on every adapter listed under Home's "More forms": the e-service's own name and symbol.
    /// Absent on the municipality's main fault-report adapter, whose tiles make up Home's grid.
    public let service: Service?
    /// Questions the resident answers in Fixa's own controls, sent through `answer` fields.
    public let questions: [Question]?
    /// Heading and placeholder of the description box when the form's description means something
    /// narrower ("Where exactly did you see it?", "Anything else?"); absent: Fixa's own wording.
    public let descriptionTitle: LocalizedText?
    public let descriptionPrompt: LocalizedText?
    /// For forms without a place field: the question whose answer says where the report is for
    /// (a recycling station, a pick-up address). Used in Sent reports and by `SendGuard`.
    public let placeQuestion: String?

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
        /// The single photo upload of adapters written before `uploads` existed. Use `allUploads`.
        public let upload: UploadSpec?
        /// Photo uploads; each applies on its page when its `when` condition holds (none = always).
        public let uploads: [UploadSpec]?
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
            /// One name field: first and last name joined with a space.
            case fullName
            /// The draft's answer to `question` (tile answers win): text, a select or radio option, or
            /// every ticked option of a checkbox list.
            case answer
        }
        public let role: Role
        /// Field key, e.g. `KSB_14`; the input name ends in `$<key>_field$<control>`.
        public let key: String
        public let control: String
        /// Role `answer`: id of the question in `AdapterSpec.questions` this field sends.
        public let question: String?
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
        /// `ajax` (default): the platform's FileUploadField2, posted to `path` before the page and checked
        /// with `getFiles` at `actionPath`. `formFile`: an `<input type="file">` (`key`/`control`) sent in
        /// the page's own multipart POST.
        public enum Kind: String, Codable, Sendable {
            case ajax, formFile
        }
        /// Page whose POST the upload must precede (`ajax`) or travel with (`formFile`).
        public let pageID: String
        /// `ajax`: the field id with dots, e.g. `U.29.1.2`.
        public let fieldID: String?
        public let path: String?
        public let filePartName: String?
        public let fileName: String?
        public let actionPath: String?
        public let kind: Kind?
        /// `formFile`: key and control of the file input, e.g. `invasivaarter_8` / `fileUploadControl`.
        public let key: String?
        public let control: String?
        /// Upload only when the draft's answer to `question` (tile answers win) contains `value`.
        public let when: UploadCondition?

        public var resolvedKind: Kind { kind ?? .ajax }
    }

    public struct UploadCondition: Codable, Sendable, Hashable {
        public let question: String
        public let value: String
    }

    /// Home's "More forms" row for this e-service.
    public struct Service: Codable, Sendable, Hashable {
        public let title: LocalizedText
        /// One short line under the title: what the form is for.
        public let subtitle: LocalizedText?
        /// SF Symbol.
        public let symbol: String
        /// Ascending order on Home; absent sorts last, then by id.
        public let order: Int?
    }

    /// A question the resident answers in the app. Answers are stored as `[String]` per question id:
    /// the typed text (`text`, `longText`), the chosen option value (`choice`), every ticked value
    /// (`multiChoice`) or an ISO 8601 date-time with offset (`dateTime`, sent as Stockholm time).
    public struct Question: Codable, Sendable, Hashable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            case text, longText, choice, multiChoice, dateTime
        }
        public let id: String
        public let kind: Kind
        public let title: LocalizedText
        /// Help under the field (what to write, where to find it).
        public let hint: LocalizedText?
        public let required: Bool
        /// `choice` and `multiChoice`: what the form accepts.
        public let options: [QuestionOption]?
        /// `text`: tap-to-fill chips; the chip's `value` (Swedish) becomes the answer.
        public let suggestions: [QuestionOption]?
        /// `text`, `longText`: longest answer the form takes.
        public let maxLength: Int?
        /// `text`, `longText`: a typed answer in another language goes with a Swedish machine
        /// translation. Off unless set: codes and names (number plates, makes, addresses) stay as typed.
        public var translate: Bool? = nil
    }

    public struct QuestionOption: Codable, Sendable, Hashable, Identifiable {
        /// Exact option value (choices) or the Swedish text (suggestions) sent to the form.
        public let value: String
        public let title: LocalizedText
        /// `choice` options that are places (a recycling station): where it is, inside the
        /// municipality's `region.bbox`. The app offers the nearest one and sorts by distance.
        public var location: Coordinate?
        public var id: String { value }
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
        /// Unique across all adapters of the app.
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
        /// Answers this tile fixes, by question id (e.g. `{"action": ["Städning"]}`); not asked in the app.
        public let answers: [String: [String]]?
        /// Questions asked for this tile, in order. Absent: every adapter question not fixed by `answers`.
        public let questionIDs: [String]?
    }

    public struct TileLink: Codable, Sendable, Hashable {
        public let title: LocalizedText
        /// The e-service's web page; builds that know `adapterID` open that form in the app instead.
        public let url: URL
        /// A bundled adapter (e.g. `se.varmdo.felater`) whose form this link opens in Fixa.
        public let adapterID: String?
    }

    public struct ValidationRules: Codable, Sendable {
        public let descriptionMin: Int
        public let descriptionMax: Int
        public let emailRequiredWhenFeedback: Bool
        public let requireLocation: Bool
        /// The form refuses a report without a photo.
        public let photoRequired: Bool?
        /// The form needs an e-mail address whether or not a reply is wanted.
        public let emailRequired: Bool?
        /// False when the description field may stay empty (an "Övrig information" box); default true.
        public let descriptionRequired: Bool?
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
        /// The municipality's own page for everything that isn't an emergency ("Other questions?"),
        /// opened in the browser. An https page on the municipality's domain.
        public let infoURL: URL?
    }

    public struct EmergencyContact: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let title: LocalizedText
        public let phone: String
    }

    public struct Contact: Codable, Sendable {
        /// The municipality's contact page (e.g. its contact centre), opened in the in-app Safari view.
        public let pageURL: URL
        /// The page's name, e.g. "Kommunens kontaktcenter".
        public let title: LocalizedText
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

    /// Whether `url` is one of the municipality's own pages, opened in the in-app Safari view: https,
    /// no user or port, and a host listed in `allowedWebHosts` (exact match, case-insensitive).
    public func opensInApp(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "https", c.user == nil, c.password == nil, c.port == nil,
              let host = c.host?.lowercased(), !host.isEmpty else { return false }
        return (allowedWebHosts ?? []).contains { $0.lowercased() == host }
    }

    /// The main fault-report adapter (Home's grid) has no `service`.
    public var isPrimary: Bool { service == nil }

    /// `channel.uploads` followed by the legacy `channel.upload`.
    public var allUploads: [UploadSpec] {
        (channel.uploads ?? []) + (channel.upload.map { [$0] } ?? [])
    }

    public func question(id: String?) -> Question? {
        guard let id else { return nil }
        return questions?.first { $0.id == id }
    }

    /// Whether any page has a field with `role`.
    public func hasField(_ role: FieldSpec.Role) -> Bool {
        channel.pages.contains { $0.fields.contains { $0.role == role } }
    }

    /// Questions the resident answers for `tileID`, in order: the tile's `questionIDs`, else every
    /// adapter question; never one the tile already answers.
    public func visibleQuestions(tileID: String?) -> [Question] {
        let tile = tile(id: tileID)
        let fixed = Set(tile?.answers?.keys.map { $0 } ?? [])
        let all = tile?.questionIDs?.compactMap { question(id: $0) } ?? questions ?? []
        return all.filter { !fixed.contains($0.id) }
    }

    /// What the form receives per question: the draft's answers of visible questions with empty
    /// strings dropped, overlaid by the tile's fixed answers. A free-text answer of a `translate`
    /// question with a Swedish machine translation (`MachineTranslation.answers`) goes as
    /// `"<Swedish> (<original>)"`, or as typed when that would pass the question's `maxLength`.
    public func answers(for draft: ReportDraft) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for question in visibleQuestions(tileID: draft.tileID) {
            let values = (draft.answers[question.id] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !values.isEmpty else { continue }
            let original = values.joined(separator: ", ")
            if question.kind == .text || question.kind == .longText, question.translate == true,
               let swedish = draft.translation?.answers?[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !swedish.isEmpty, swedish != original {
                let combined = "\(swedish) (\(original))"
                result[question.id] = combined.count <= (question.maxLength ?? .max) ? [combined] : values
            } else {
                result[question.id] = values
            }
        }
        for (id, values) in tile(id: draft.tileID)?.answers ?? [:] {
            result[id] = values
        }
        return result
    }
}

extension AdapterSpec {
    /// Where the report is for, in Swedish: the draft's place text, else the answer to `placeQuestion`
    /// (a choice option's value, a text answer as typed), else "".
    public func placeText(for draft: ReportDraft) -> String {
        let typed = draft.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.isEmpty, let id = placeQuestion else { return typed }
        let values = (tile(id: draft.tileID)?.answers?[id] ?? draft.answers[id] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.joined(separator: ", ")
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
