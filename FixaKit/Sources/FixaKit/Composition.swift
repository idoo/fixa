import Foundation

public enum EmergencyRouter {
    /// The first rule matching the local weekday and time (before `until`), else the default contact.
    public static func contact(for date: Date, emergency: AdapterSpec.Emergency) -> AdapterSpec.EmergencyContact {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: emergency.timeZone) ?? .current
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let isoWeekday = ((parts.weekday ?? 1) + 5) % 7 + 1
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        let rule = emergency.rules.first { rule in
            guard rule.isoWeekdays.contains(isoWeekday), let until = minutesOfDay(rule.until) else { return false }
            return minutes < until
        }
        let id = rule?.contactID ?? emergency.defaultContactID
        return emergency.contacts.first { $0.id == id }
            ?? emergency.contacts.first { $0.id == emergency.defaultContactID }
            ?? emergency.contacts[0]
    }

    static func minutesOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

/// Swedish text that goes into the municipality's form or e-mail. It reads like a report typed on the
/// e-service's own website: no app name, no footer.
public enum ReportComposer {
    /// A report started more than this long before sending gets an `Upptäckt:` line.
    static let discoveredLineAfter: TimeInterval = 60 * 60

    /// Tile summary, the resident's text, the Swedish translation (if any) and `Upptäckt:` when the
    /// report was started over an hour before `now`, separated by blank lines. Longer than the
    /// adapter's `descriptionMax`, the resident's text (then the translation) is cut; the summary
    /// and `Upptäckt:` line are never cut.
    public static func description(for d: ReportDraft, spec: AdapterSpec, now: Date = Date()) -> String {
        var parts = parts(for: d, spec: spec, now: now)
        var overflow = parts.joined.count - spec.validation.descriptionMax
        if overflow > 0 { parts.text = cut(parts.text, by: &overflow) }
        if overflow > 0 { parts.translation = cut(parts.translation, by: &overflow) }
        return parts.joined
    }

    /// Length of the description without the translation and without cutting: what the resident wrote must fit.
    static func untruncatedLength(of d: ReportDraft, spec: AdapterSpec, now: Date = Date()) -> Int {
        var plain = d
        plain.translation = nil
        return parts(for: plain, spec: spec, now: now).joined.count
    }

    private struct Parts {
        var summary: String?
        var text: String
        /// Header line, newline, translated text; empty when there is no translation.
        var translationHeader: String
        var translation: String
        var discovered: String?

        var joined: String {
            var blocks: [String] = []
            if let summary { blocks.append(summary) }
            if !text.isEmpty { blocks.append(text) }
            if !translationHeader.isEmpty, !translation.isEmpty { blocks.append(translationHeader + "\n" + translation) }
            if let discovered { blocks.append(discovered) }
            return blocks.joined(separator: "\n\n")
        }
    }

    private static func parts(for d: ReportDraft, spec: AdapterSpec, now: Date) -> Parts {
        let translated = d.translation?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var discovered: String?
        if let createdAt = d.createdAt, now.timeIntervalSince(createdAt) > discoveredLineAfter {
            discovered = "Upptäckt: " + stockholmTimestamp(createdAt)
        }
        return Parts(
            summary: spec.tile(id: d.tileID)?.swedishSummary,
            text: d.description.trimmingCharacters(in: .whitespacesAndNewlines),
            translationHeader: d.translation.map { "Översatt från \(swedishLanguageName($0.sourceLanguage)):" } ?? "",
            translation: translated,
            discovered: discovered
        )
    }

    /// Drops up to `overflow` characters (plus one for the ellipsis) from the end of `s`.
    private static func cut(_ s: String, by overflow: inout Int) -> String {
        guard !s.isEmpty else { return s }
        let keep = s.count - overflow - 1
        guard keep > 0 else {
            overflow -= s.count
            return ""
        }
        overflow = 0
        return s.prefix(keep).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// `uk` → `ukrainska`; the code itself if Swedish has no name for it.
    static func swedishLanguageName(_ code: String) -> String {
        Locale(identifier: "sv_SE").localizedString(forLanguageCode: code)?.lowercased(with: Locale(identifier: "sv_SE")) ?? code
    }

    /// `yyyy-MM-dd HH:mm` in Europe/Stockholm, whatever the phone's zone.
    static func stockholmTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// `locationText (lat, lng)`.
    public static func placeText(for d: ReportDraft) -> String {
        let text = d.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = d.coordinate else { return text }
        let coordinate = "\(c.latitude), \(c.longitude)"
        return text.isEmpty ? coordinate : "\(text) (\(coordinate))"
    }
}

/// Swedish plain-text e-mail for when the e-service cannot be reached.
public enum MailFallback {
    public static func subject(_ d: ReportDraft, spec: AdapterSpec) -> String {
        let category = spec.category(for: d)?.value ?? "Felanmälan"
        let place = d.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? "Felanmälan: \(category)" : "Felanmälan: \(category), \(place)"
    }

    public static func body(_ d: ReportDraft, spec: AdapterSpec, now: Date = Date()) -> String {
        var lines = [
            "Hej!",
            "",
            "Jag skickar felanmälan med e-post eftersom e-tjänsten inte gick att nå.",
            "",
            "Område: \(spec.category(for: d)?.value ?? "-")",
        ]
        let place = d.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Plats: \(place.isEmpty ? "-" : place)")
        if let c = d.coordinate {
            lines.append("Position: \(c.formValue)")
            lines.append("Karta: https://maps.apple.com/?ll=\(c.formValue)")
        }
        lines += ["", "Beskrivning:", ReportComposer.description(for: d, spec: spec, now: now), ""]
        lines.append("Jag vill ha återkoppling: \(d.wantsFeedback ? "Ja" : "Nej")")

        let contact = d.contact
        let name = [contact.firstName, contact.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let phone = contact.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = contact.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(name.isEmpty && phone.isEmpty && email.isEmpty) {
            lines += ["", "Kontaktuppgifter:"]
            if !name.isEmpty { lines.append("Namn: \(name)") }
            if !phone.isEmpty { lines.append("Telefon: \(phone)") }
            if !email.isEmpty { lines.append("E-post: \(email)") }
        }
        if d.photoJPEG != nil {
            lines += ["", "Foto bifogat."]
        }
        lines += ["", "Med vänliga hälsningar"]
        if !name.isEmpty { lines.append(name) }
        return lines.joined(separator: "\n")
    }
}
