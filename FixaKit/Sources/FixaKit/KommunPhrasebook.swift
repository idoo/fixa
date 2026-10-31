import Foundation

/// One sentence the kommun's e-service is known to say, with the values it carried.
public struct KommunPhrase: Sendable, Equatable {
    public enum ID: String, Sendable, CaseIterable {
        /// "Tack för att du använder vår e-tjänst!"
        case thanksForUsingService
        /// "Här är ditt ärendenummer <n>" (also "Ditt ärendenummer är <n>"); value `caseNumber`.
        case caseNumber
        /// "Tack för din felanmälan!"
        case thanksForReport
        /// "Med vänlig hälsning"
        case regards
        /// "Värmdö kommun" as the signature line; value `name` (a proper name, never translated).
        case signature
        /// "Om du har valt återkoppling kommer du att få svar inom 5 arbetsdagar."; value `days`.
        case replyWithinWorkingDays
        /// "Om din fråga kräver längre handläggningstid bekräftar vi inom samma tid …"
        case longerHandlingTime
        /// "Dina uppgifter bearbetas, vänligen vänta…"
        case processing
        /// "Välj ett värde för fältet '<label>'"; values `label` and, when it is an adapter field, `role`.
        case chooseValue
        /// "Fyll i fältet '<label>'"; values `label` and, when it is an adapter field, `role`.
        case fillIn
    }

    public enum Key: String, Sendable {
        case caseNumber, name, days, label, role
    }

    public let id: ID
    public let values: [Key: String]
    /// The kommun's sentence exactly as it appeared.
    public let original: String

    public init(id: ID, values: [Key: String] = [:], original: String) {
        self.id = id
        self.values = values
        self.original = original
    }

    public subscript(key: Key) -> String? { values[key] }
}

/// A kommun text split into known sentences and the rest, line by line, in the original order.
public struct KommunReading: Sendable, Equatable {
    public enum Part: Sendable, Equatable {
        case phrase(KommunPhrase)
        /// A sentence the phrasebook doesn't know, exactly as the kommun wrote it.
        case unknown(String)
    }

    /// One entry per non-empty line of the text.
    public let lines: [[Part]]

    public var phrases: [KommunPhrase] {
        lines.flatMap { $0 }.compactMap { if case .phrase(let p) = $0 { p } else { nil } }
    }

    /// The unknown remainder, one entry per unknown sentence (adjacent ones on a line joined).
    public var unknown: [String] {
        lines.flatMap { $0 }.compactMap { if case .unknown(let s) = $0 { s } else { nil } }
    }

    /// The case number exactly as the kommun wrote it, if a case-number sentence was found.
    public var caseNumber: String? {
        phrases.first { $0.id == .caseNumber }?[.caseNumber]
    }
}

/// Pure reading of the Swedish the kommun's e-service sends back (receipt page, validation messages),
/// so the app can show it in the resident's language. Only sentences seen on saved pages are known;
/// everything else comes back unchanged as `unknown`.
public enum KommunPhrasebook {
    /// `fields`: the adapter's fields, to tell which field a validation message is about.
    public static func read(_ text: String, fields: [AdapterSpec.FieldSpec] = []) -> KommunReading {
        var lines: [[KommunReading.Part]] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = collapse(raw)
            guard !line.isEmpty else { continue }
            // "Värmdö kommun" is a signature only right under "Med vänlig hälsning"; elsewhere a line
            // like "Kontakta Värmdö kommun" is ordinary text.
            let afterRegards: Bool
            if case .phrase(let previous)? = lines.last?.last { afterRegards = previous.id == .regards } else { afterRegards = false }
            if let phrase = phrase(line, fields: fields, afterRegards: afterRegards) {
                lines.append([.phrase(phrase)])
                continue
            }
            var parts: [KommunReading.Part] = []
            for sentence in sentences(line) {
                if let phrase = phrase(sentence, fields: fields, afterRegards: false) {
                    parts.append(.phrase(phrase))
                } else if case .unknown(let previous)? = parts.last {
                    parts[parts.count - 1] = .unknown(previous + " " + sentence)
                } else {
                    parts.append(.unknown(sentence))
                }
            }
            lines.append(parts)
        }
        return KommunReading(lines: lines)
    }

    // MARK: - Internals

    private struct Pattern {
        let id: KommunPhrase.ID
        let regex: String
        /// Capture group number per value.
        let captures: [KommunPhrase.Key: Int]
    }

    /// Sentence end: `.`, `!`, `?` or `…`, optionally repeated.
    private static let end = #"[.!?…]*"#

    /// Each regex carries its own flags: wording is case-insensitive (`(?i)`), but the case number and
    /// the signature are matched with their capitals, which are part of what they are.
    private static let patterns: [Pattern] = [
        Pattern(id: .thanksForUsingService, regex: #"(?i)tack för att du använder vår e-tjänst"# + end, captures: [:]),
        Pattern(id: .caseNumber, regex: #"(?i:här är ditt|ditt) (?i:ärendenummer)(?: (?i:är))?:? ([A-Z0-9][A-Z0-9-]{2,})"# + end, captures: [.caseNumber: 1]),
        Pattern(id: .thanksForReport, regex: #"(?i)tack för din felanmälan"# + end, captures: [:]),
        Pattern(id: .regards, regex: #"(?i)med vänliga? hälsninga?r?,?"#, captures: [:]),
        Pattern(id: .signature, regex: #"(\p{Lu}[\p{L}-]*(?: \p{Lu}[\p{L}-]*){0,2} kommun)"# + end, captures: [.name: 1]),
        Pattern(id: .replyWithinWorkingDays, regex: #"(?i)om du har valt återkoppling kommer du att få svar inom (\d{1,3}) arbetsdagar"# + end, captures: [.days: 1]),
        Pattern(id: .longerHandlingTime, regex: #"(?i)om din fråga kräver längre handläggningstid bekräftar vi inom samma tid att vi tagit emot ditt ärende och talar också om vem som handlägger ditt ärende"# + end, captures: [:]),
        Pattern(id: .processing, regex: #"(?i)dina uppgifter bearbetas,? vänligen vänta"# + end, captures: [:]),
        Pattern(id: .chooseValue, regex: #"(?i)välj ett värde för fältet '([^']+)'"# + end, captures: [.label: 1]),
        Pattern(id: .fillIn, regex: #"(?i)fyll i fältet '([^']+)'"# + end, captures: [.label: 1]),
    ]

    private static func phrase(_ sentence: String, fields: [AdapterSpec.FieldSpec], afterRegards: Bool) -> KommunPhrase? {
        let text = straightQuotes(sentence)
        for pattern in patterns where pattern.id != .signature || afterRegards {
            guard let match = AbouPageParser.matches("^(?:" + pattern.regex + ")$", in: text).first else { continue }
            var values: [KommunPhrase.Key: String] = [:]
            for (key, group) in pattern.captures where group < match.count {
                values[key] = match[group]
            }
            // A case number always has a digit (the parser's rule too); "ärendenummer ABC" isn't one.
            if pattern.id == .caseNumber, values[.caseNumber]?.contains(where: \.isNumber) != true { continue }
            if let label = values[.label], let role = role(ofLabel: label, in: fields) {
                values[.role] = role.rawValue
            }
            return KommunPhrase(id: pattern.id, values: values, original: sentence)
        }
        return nil
    }

    /// The adapter field whose Swedish (or any) label matches, compared like the form resolver does.
    static func role(ofLabel label: String, in fields: [AdapterSpec.FieldSpec]) -> AdapterSpec.FieldSpec.Role? {
        let key = trimmedLabel(label)
        return fields.first { field in field.allLabels.contains { trimmedLabel($0) == key } }?.role
    }

    private static func trimmedLabel(_ s: String) -> String {
        var key = FormStructure.normalize(s)
        while key.hasSuffix(":") || key.hasSuffix("?") { key.removeLast() }
        return key.trimmingCharacters(in: .whitespaces)
    }

    /// Whitespace runs (including no-break spaces) to one space.
    private static func collapse(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Curly and typographic quotes to `'`, so `‘Välj område’` and `"Välj område"` read alike.
    private static func straightQuotes(_ s: String) -> String {
        s.replacingOccurrences(of: #"[‘’‚‛“”„"´`]"#, with: "'", options: .regularExpression)
    }

    /// Splits after `.`, `!`, `?` or `…` followed by a space and a capital letter or digit.
    static func sentences(_ line: String) -> [String] {
        let marked = line.replacingOccurrences(of: #"([.!?…])\s+(?=[\p{Lu}0-9])"#, with: "$1\n", options: .regularExpression)
        return marked.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
