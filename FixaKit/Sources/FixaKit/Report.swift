import Foundation

public struct Coordinate: Codable, Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// `"lat,lng"` in WGS84 decimal degrees, e.g. `59.3262,18.3856`.
    var formValue: String { "\(latitude),\(longitude)" }
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
    /// Swedish machine translation of `ReportDraft.description`.
    public var text: String
    /// Swedish machine translation of `ReportDraft.locationText`, if the place was written in another language.
    public var locationText: String?

    public init(sourceLanguage: String, text: String, locationText: String? = nil) {
        self.sourceLanguage = sourceLanguage
        self.text = text
        self.locationText = locationText
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
        previousReport: PreviousReport? = nil
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
    }
}

/// One report that reached the municipality, kept for `SendGuard`.
public struct SentRecord: Codable, Sendable, Equatable {
    public var date: Date
    public var tileID: String?
    public var coordinate: Coordinate?
    public var locationText: String
    /// The municipality's case number from the receipt, if one was read.
    public var caseNumber: String?

    public init(date: Date, tileID: String?, coordinate: Coordinate?, locationText: String, caseNumber: String? = nil) {
        self.date = date
        self.tileID = tileID
        self.coordinate = coordinate
        self.locationText = locationText
        self.caseNumber = caseNumber
    }

    public init(_ draft: ReportDraft, date: Date, caseNumber: String? = nil) {
        self.init(date: date, tileID: draft.tileID, coordinate: draft.coordinate, locationText: draft.locationText, caseNumber: caseNumber)
    }
}

public struct ValidationIssue: Sendable, Equatable, Hashable {
    public enum Field: String, Sendable {
        case category, description, location, email, phone
    }

    public enum Code: String, Sendable {
        case missing, tooShort, tooLong, invalidFormat, outsideRegion
    }

    public let field: Field
    public let code: Code

    public init(field: Field, code: Code) {
        self.field = field
        self.code = code
    }
}

public enum ReportValidator {
    /// A description needs at least this many letters, so a quick chip like "Blinkar" or "Djupt hål"
    /// is enough when the tile summary already says what is wrong.
    public static let minimumLetters = 3

    public static func validate(_ d: ReportDraft, spec: AdapterSpec) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let rules = spec.validation

        if spec.category(for: d) == nil {
            issues.append(.init(field: .category, code: .missing))
        }

        let text = d.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            issues.append(.init(field: .description, code: .missing))
        } else if text.filter(\.isLetter).count < minimumLetters || composedLength(of: d, spec: spec) < rules.descriptionMin {
            issues.append(.init(field: .description, code: .tooShort))
        } else if ReportComposer.untruncatedLength(of: d, spec: spec) > rules.descriptionMax {
            issues.append(.init(field: .description, code: .tooLong))
        }

        let place = d.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let coordinate = d.coordinate {
            if !spec.municipality.region.contains(coordinate) {
                issues.append(.init(field: .location, code: .outsideRegion))
            }
        } else if rules.requireLocation && place.isEmpty {
            issues.append(.init(field: .location, code: .missing))
        }

        let email = d.contact.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty {
            if d.wantsFeedback && rules.emailRequiredWhenFeedback {
                issues.append(.init(field: .email, code: .missing))
            }
        } else if !isEmail(email) {
            issues.append(.init(field: .email, code: .invalidFormat))
        }

        let phone = d.contact.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty && !isPhone(phone) {
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
