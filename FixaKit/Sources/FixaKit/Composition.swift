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

public enum ReportComposer {
    /// Tile summary, blank line, then the user's text.
    public static func description(for d: ReportDraft, spec: AdapterSpec) -> String {
        let text = d.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary = spec.tile(id: d.tileID)?.swedishSummary else { return text }
        return text.isEmpty ? summary : summary + "\n\n" + text
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

    public static func body(_ d: ReportDraft, spec: AdapterSpec) -> String {
        var lines = [
            "Hej!",
            "",
            "Jag vill göra en felanmälan. Den skickas med e-post från appen Fixa eftersom e-tjänsten inte gick att nå.",
            "",
            "Område: \(spec.category(for: d)?.value ?? "-")",
        ]
        let place = d.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Plats: \(place.isEmpty ? "-" : place)")
        if let c = d.coordinate {
            lines.append("Position: \(c.formValue)")
            lines.append("Karta: https://maps.apple.com/?ll=\(c.formValue)")
        }
        lines += ["", "Beskrivning:", ReportComposer.description(for: d, spec: spec), ""]
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
