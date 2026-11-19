import Foundation

public struct Coordinate: Codable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// `"lat,lng"` in WGS84 decimal degrees, e.g. `59.3262,18.3856`.
    var formValue: String { "\(latitude),\(longitude)" }
}

extension Coordinate {
    /// Great-circle distance in metres (haversine on a 6 371 km sphere; under 0.5 % off at these scales).
    public func distance(to other: Coordinate) -> Double {
        let radians = Double.pi / 180
        let dLat = (other.latitude - latitude) * radians
        let dLon = (other.longitude - longitude) * radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * radians) * cos(other.latitude * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6_371_000 * atan2(sqrt(a), sqrt(1 - a))
    }
}

extension AdapterSpec.Question {
    /// The options that carry a `location`, nearest to `point` first, with their distance in metres.
    /// Options without one are left out; ties keep the adapter's order.
    public func locatedOptions(nearestTo point: Coordinate) -> [(option: AdapterSpec.QuestionOption, meters: Double)] {
        (options ?? []).enumerated()
            .compactMap { index, option in option.location.map { (index, option, point.distance(to: $0)) } }
            .sorted { $0.2 != $1.2 ? $0.2 < $1.2 : $0.0 < $1.0 }
            .map { (option: $0.1, meters: $0.2) }
    }
}

public struct Contact: Codable, Sendable, Equatable {
    public var firstName: String
    public var lastName: String
    public var phone: String
    public var email: String

    public init(firstName: String = "", lastName: String = "", phone: String = "", email: String = "") {
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
    }
}

/// A Swedish machine translation of the resident's own text, sent alongside the original.
public struct MachineTranslation: Codable, Sendable, Equatable {
    /// BCP-47 code of the original text, e.g. `uk`, `ar`.
    public var sourceLanguage: String
    /// Swedish machine translation of `ReportDraft.description`; empty when only other text was translated.
    public var text: String
    /// Swedish machine translation of `ReportDraft.locationText`, if the place was written in another language.
    public var locationText: String?
    /// Swedish machine translations of free-text answers, by question id. Absent in older drafts.
    public var answers: [String: String]?

    public init(sourceLanguage: String, text: String, locationText: String? = nil, answers: [String: String]? = nil) {
        self.sourceLanguage = sourceLanguage
        self.text = text
        self.locationText = locationText
        self.answers = answers
    }
}

/// An earlier report of the same problem from this phone, mentioned when the resident sends again anyway.
public struct PreviousReport: Codable, Sendable, Equatable {
    public var caseNumber: String?
    public var date: Date

    public init(caseNumber: String?, date: Date) {
        self.caseNumber = caseNumber
        self.date = date
    }
}

public struct ReportDraft: Codable, Sendable, Equatable {
    public var adapterID: String
    public var tileID: String?
    public var categoryID: String?
    public var description: String
    public var coordinate: Coordinate?
    public var locationText: String
    /// One combined JPEG.
    public var photoJPEG: Data?
    public var wantsFeedback: Bool
    public var contact: Contact
    /// Swedish machine translation of `description`, if the resident wrote in another language.
    public var translation: MachineTranslation?
    /// When the resident started the report. Optional so drafts saved before it existed still decode.
    public var createdAt: Date?
    /// Set when the resident sends again although `SendGuard` found an earlier report of the same problem.
    public var previousReport: PreviousReport?
    /// Answers to the adapter's `questions`, by question id (see `AdapterSpec.Question`). Drafts saved
    /// before answers existed decode with none.
    public var answers: [String: [String]]

    public init(
        adapterID: String,
        tileID: String? = nil,
        categoryID: String? = nil,
        description: String = "",
        coordinate: Coordinate? = nil,
        locationText: String = "",
        photoJPEG: Data? = nil,
        wantsFeedback: Bool = false,
        contact: Contact = Contact(),
        translation: MachineTranslation? = nil,
        createdAt: Date? = nil,
        previousReport: PreviousReport? = nil,
        answers: [String: [String]] = [:]
    ) {
        self.adapterID = adapterID
        self.tileID = tileID
        self.categoryID = categoryID
        self.description = description
        self.coordinate = coordinate
        self.locationText = locationText
        self.photoJPEG = photoJPEG
        self.wantsFeedback = wantsFeedback
        self.contact = contact
        self.translation = translation
        self.createdAt = createdAt
        self.previousReport = previousReport
        self.answers = answers
    }
}

extension ReportDraft {
    enum CodingKeys: String, CodingKey {
        case adapterID, tileID, categoryID, description, coordinate, locationText, photoJPEG, wantsFeedback
        case contact, translation, createdAt, previousReport, answers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            adapterID: try c.decode(String.self, forKey: .adapterID),
            tileID: try c.decodeIfPresent(String.self, forKey: .tileID),
            categoryID: try c.decodeIfPresent(String.self, forKey: .categoryID),
            description: try c.decode(String.self, forKey: .description),
            coordinate: try c.decodeIfPresent(Coordinate.self, forKey: .coordinate),
            locationText: try c.decode(String.self, forKey: .locationText),
            photoJPEG: try c.decodeIfPresent(Data.self, forKey: .photoJPEG),
            wantsFeedback: try c.decode(Bool.self, forKey: .wantsFeedback),
            contact: try c.decode(Contact.self, forKey: .contact),
            translation: try c.decodeIfPresent(MachineTranslation.self, forKey: .translation),
            createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt),
            previousReport: try c.decodeIfPresent(PreviousReport.self, forKey: .previousReport),
            answers: try c.decodeIfPresent([String: [String]].self, forKey: .answers) ?? [:]
        )
    }
}

/// One report that reached the municipality, kept for `SendGuard`.
public struct SentRecord: Codable, Sendable, Equatable {
    public var date: Date
    public var tileID: String?
    public var coordinate: Coordinate?
    /// Where the report was for: the place text, or for forms without one the answer that names the
    /// place (`AdapterSpec.placeText(for:)`).
    public var locationText: String
    /// The municipality's case number from the receipt, if one was read.
    public var caseNumber: String?
    /// What the report was about beyond its tile: the draft's identifying answers (`SendGuard.subject`).
    /// Nil for drafts without answers and for records saved before it existed.
    public var subject: String?

    public init(date: Date, tileID: String?, coordinate: Coordinate?, locationText: String, caseNumber: String? = nil, subject: String? = nil) {
        self.date = date
        self.tileID = tileID
        self.coordinate = coordinate
        self.locationText = locationText
        self.caseNumber = caseNumber
        self.subject = subject
    }

    public init(_ draft: ReportDraft, spec: AdapterSpec?, date: Date, caseNumber: String? = nil) {
        self.init(date: date, tileID: draft.tileID, coordinate: draft.coordinate,
                  locationText: SendGuard.place(of: draft, spec: spec), caseNumber: caseNumber,
                  subject: SendGuard.subject(of: draft, spec: spec))
    }
}

public struct ValidationIssue: Sendable, Equatable, Hashable {
    public enum Field: String, Sendable {
        case category, description, location, email, phone
        /// The adapter requires a photo (`validation.photoRequired`).
        case photo
        /// An answer to the question `questionID`.
        case question
    }

    public enum Code: String, Sendable {
        case missing, tooShort, tooLong, invalidFormat, outsideRegion
    }

    public let field: Field
    public let code: Code
    /// Set for `.question`.
    public let questionID: String?

    public init(field: Field, code: Code, questionID: String? = nil) {
        self.field = field
        self.code = code
        self.questionID = questionID
    }
}

public enum ReportValidator {
    /// A description needs at least this many letters, so a quick chip like "Blinkar" or "Djupt hål"
    /// is enough when the tile summary already says what is wrong.
    public static let minimumLetters = 3

    /// Issues in screen order: category, questions (visible order), description, location, photo,
    /// e-mail, phone. A rule about a field applies only when the adapter's form has that field.
    public static func validate(_ d: ReportDraft, spec: AdapterSpec, now: Date = Date()) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let rules = spec.validation

        if spec.hasField(.category) && spec.category(for: d) == nil {
            issues.append(.init(field: .category, code: .missing))
        }

        for question in spec.visibleQuestions(tileID: d.tileID) {
            if let issue = questionIssue(question, values: d.answers[question.id] ?? [], now: now) {
                issues.append(issue)
            }
        }

        if spec.hasField(.description) {
            let text = d.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let required = rules.descriptionRequired ?? true
            if text.isEmpty && required {
                issues.append(.init(field: .description, code: .missing))
            } else if required && (text.filter(\.isLetter).count < minimumLetters || composedLength(of: d, spec: spec) < rules.descriptionMin) {
                issues.append(.init(field: .description, code: .tooShort))
            } else if ReportComposer.untruncatedLength(of: d, spec: spec) > rules.descriptionMax {
                issues.append(.init(field: .description, code: .tooLong))
            }
        }

        let place = d.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let coordinate = d.coordinate {
            if !spec.municipality.region.contains(coordinate) {
                issues.append(.init(field: .location, code: .outsideRegion))
            }
        } else if rules.requireLocation && place.isEmpty {
            issues.append(.init(field: .location, code: .missing))
        }

        if rules.photoRequired == true && d.photoJPEG == nil {
            issues.append(.init(field: .photo, code: .missing))
        }

        // Format checks only for what the form takes: a profile address the form never gets can't block it.
        let email = d.contact.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty {
            if (d.wantsFeedback && rules.emailRequiredWhenFeedback) || (rules.emailRequired == true && spec.hasField(.email)) {
                issues.append(.init(field: .email, code: .missing))
            }
        } else if spec.hasField(.email) && !isEmail(email) {
            issues.append(.init(field: .email, code: .invalidFormat))
        }

        let phone = d.contact.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if spec.hasField(.phone) && !phone.isEmpty && !isPhone(phone) {
            issues.append(.init(field: .phone, code: .invalidFormat))
        }

        return issues
    }

    /// Characters of what the municipality reads as the description: the tile summary (if the tile has
    /// one) plus the resident's text, chips included. Without a summary only the resident's text counts.
    static func composedLength(of d: ReportDraft, spec: AdapterSpec) -> Int {
        let text = d.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary = spec.tile(id: d.tileID)?.swedishSummary, !summary.isEmpty else { return text.count }
        return summary.count + 2 + text.count
    }

    /// Answers may lie at most this far in the future (clock drift between picker and send).
    static let futureTolerance: TimeInterval = 5 * 60

    /// The first problem with an answer: missing when required, too long, an option the form lacks,
    /// or a date-time that doesn't parse or lies in the future.
    static func questionIssue(_ q: AdapterSpec.Question, values raw: [String], now: Date) -> ValidationIssue? {
        let values = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        func issue(_ code: ValidationIssue.Code) -> ValidationIssue {
            .init(field: .question, code: code, questionID: q.id)
        }
        if values.isEmpty { return q.required ? issue(.missing) : nil }
        switch q.kind {
        case .text, .longText:
            if let max = q.maxLength, values.contains(where: { $0.count > max }) { return issue(.tooLong) }
        case .choice, .multiChoice:
            let allowed = Set((q.options ?? []).map(\.value))
            if values.contains(where: { !allowed.contains($0) }) { return issue(.invalidFormat) }
        case .dateTime:
            let parser = ISO8601DateFormatter()
            for value in values {
                guard let date = parser.date(from: value), date <= now.addingTimeInterval(futureTolerance) else {
                    return issue(.invalidFormat)
                }
            }
        }
        return nil
    }

    /// One `@`, a non-empty local part, a domain with a dot and a TLD of two or more letters, no spaces.
    static func isEmail(_ s: String) -> Bool {
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !s.contains(where: \.isWhitespace) else { return false }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }), let tld = labels.last else { return false }
        return tld.count >= 2 && tld.allSatisfy(\.isLetter)
    }

    static func isPhone(_ s: String) -> Bool {
        let digits = s.filter(\.isASCII).filter(\.isNumber).count
        return digits >= 6 && s.range(of: #"^\+?[0-9 ()\-]+$"#, options: .regularExpression) != nil
    }
}
