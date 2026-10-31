import Foundation

public enum EmergencyRouter {
    /// The first rule matching the local weekday and time (`from <= now < until`), else the default
    /// contact. On a day of the emergency's `holidays` calendar no rule matches.
    public static func contact(for date: Date, emergency: AdapterSpec.Emergency) -> AdapterSpec.EmergencyContact {
        let id = matchingRule(at: date, emergency: emergency)?.contactID ?? emergency.defaultContactID
        return emergency.contacts.first { $0.id == id }
            ?? emergency.contacts.first { $0.id == emergency.defaultContactID }
            ?? emergency.contacts[0]
    }

    /// True when a rule for `contactID` applies at `date` (e.g. the service centre is open now).
    public static func isOpen(contactID: String, at date: Date, emergency: AdapterSpec.Emergency) -> Bool {
        rules(at: date, emergency: emergency).contains { $0.contactID == contactID }
    }

    private static func matchingRule(at date: Date, emergency: AdapterSpec.Emergency) -> AdapterSpec.HoursRule? {
        rules(at: date, emergency: emergency).first
    }

    /// Every rule that applies at `date`, in adapter order.
    private static func rules(at date: Date, emergency: AdapterSpec.Emergency) -> [AdapterSpec.HoursRule] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: emergency.timeZone) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        if let code = emergency.holidays, let year = parts.year, let month = parts.month, let day = parts.day,
           PublicHolidays.isHoliday(year: year, month: month, day: day, calendar: code) {
            return []
        }
        let isoWeekday = ((parts.weekday ?? 1) + 5) % 7 + 1
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return emergency.rules.filter { rule in
            guard rule.isoWeekdays.contains(isoWeekday),
                  let from = minutesOfDay(rule.from ?? "00:00"),
                  let until = minutesOfDay(rule.until) else { return false }
            return from <= minutes && minutes < until
        }
    }

    static func minutesOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 2, let h = parts[0], let m = parts[1], (0...24).contains(h), (0..<60).contains(m),
              h * 60 + m <= 24 * 60 else { return nil }
        return h * 60 + m
    }
}

/// Public-holiday calendars for `AdapterSpec.Emergency.holidays`.
public enum PublicHolidays {
    public static let supported: Set<String> = ["SE"]

    /// True when the local date is a holiday in `calendar`. Unknown calendars have no holidays.
    public static func isHoliday(year: Int, month: Int, day: Int, calendar: String) -> Bool {
        guard calendar == "SE" else { return false }
        return swedish(year: year).contains(DayKey(month: month, day: day))
    }

    struct DayKey: Hashable {
        let month: Int
        let day: Int
    }

    /// Swedish röda dagar plus the afton days when offices close: nyårsdagen, trettondedag jul,
    /// långfredagen, påskafton, påskdagen, annandag påsk, första maj, Kristi himmelsfärdsdag,
    /// pingstdagen, nationaldagen, midsommarafton, midsommardagen, alla helgons dag, julafton,
    /// juldagen, annandag jul and nyårsafton.
    static func swedish(year: Int) -> Set<DayKey> {
        var days: Set<DayKey> = [
            DayKey(month: 1, day: 1), DayKey(month: 1, day: 6), DayKey(month: 5, day: 1), DayKey(month: 6, day: 6),
            DayKey(month: 12, day: 24), DayKey(month: 12, day: 25), DayKey(month: 12, day: 26), DayKey(month: 12, day: 31),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let easter = easterSunday(year: year)
        guard let easterDate = calendar.date(from: DateComponents(year: year, month: easter.month, day: easter.day)) else { return days }
        func add(_ date: Date?) {
            guard let date else { return }
            let c = calendar.dateComponents([.month, .day], from: date)
            days.insert(DayKey(month: c.month!, day: c.day!))
        }
        for offset in [-2, -1, 0, 1, 39, 49] {
            add(calendar.date(byAdding: .day, value: offset, to: easterDate))
        }
        // Midsommarafton: the Friday between 19 and 25 June; midsommardagen the next day.
        // Alla helgons dag: the Saturday between 31 October and 6 November.
        for day in 19...25 {
            guard let date = calendar.date(from: DateComponents(year: year, month: 6, day: day)),
                  calendar.component(.weekday, from: date) == 6 else { continue }
            add(date)
            add(calendar.date(byAdding: .day, value: 1, to: date))
        }
        for offset in 0...6 {
            guard let date = calendar.date(from: DateComponents(year: year, month: 10, day: 31 + offset)),
                  calendar.component(.weekday, from: date) == 7 else { continue }
            add(date)
        }
        return days
    }

    /// Gregorian Easter Sunday (anonymous Gregorian algorithm).
    static func easterSunday(year: Int) -> (month: Int, day: Int) {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return (month, day)
    }
}

/// Swedish text that goes into the municipality's form or onto its website. It reads like a report
/// typed on the e-service's own website: no app name, no footer.
public enum ReportComposer {
    /// A report started more than this long before sending gets an `Anmälan skriven:` line.
    static let writtenLineAfter: TimeInterval = 60 * 60

    /// Tile summary, the resident's text, the Swedish translation (if any), the translated place (if
    /// any), a line about an earlier report of the same problem (if any) and `Anmälan skriven:` when
    /// the report was started over an hour before `now`, separated by blank lines. Longer than the
    /// adapter's `descriptionMax`, the resident's text (then the translation) is cut; the other lines
    /// are never cut.
    public static func description(for d: ReportDraft, spec: AdapterSpec, now: Date = Date()) -> String {
        var parts = parts(for: d, spec: spec, now: now)
        var overflow = parts.joined.count - spec.validation.descriptionMax
        if overflow > 0 { parts.text = cut(parts.text, by: &overflow) }
        if overflow > 0 { parts.translation = cut(parts.translation, by: &overflow) }
        return parts.joined
    }

    /// Length of the description without the translations and without cutting: what the resident wrote must fit.
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
        var translatedPlace: String?
        var previous: String?
        var written: String?

        var joined: String {
            var blocks: [String] = []
            if let summary, !summary.isEmpty { blocks.append(summary) }
            if !text.isEmpty { blocks.append(text) }
            if !translationHeader.isEmpty, !translation.isEmpty { blocks.append(translationHeader + "\n" + translation) }
            if let translatedPlace { blocks.append(translatedPlace) }
            if let previous { blocks.append(previous) }
            if let written { blocks.append(written) }
            return blocks.joined(separator: "\n\n")
        }
    }

    private static func parts(for d: ReportDraft, spec: AdapterSpec, now: Date) -> Parts {
        let translated = d.translation?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var written: String?
        if let createdAt = d.createdAt, now.timeIntervalSince(createdAt) > writtenLineAfter {
            written = "Anmälan skriven: " + stockholmTimestamp(createdAt)
        }
        return Parts(
            summary: spec.tile(id: d.tileID)?.swedishSummary,
            text: d.description.trimmingCharacters(in: .whitespacesAndNewlines),
            translationHeader: d.translation.map { "Översatt från \(swedishLanguageName($0.sourceLanguage)):" } ?? "",
            translation: translated,
            translatedPlace: translatedPlaceLine(for: d),
            previous: previousReportLine(for: d),
            written: written
        )
    }

    /// `Plats (översatt från ukrainska): …`, when the place text was machine-translated.
    static func translatedPlaceLine(for d: ReportDraft) -> String? {
        guard let translation = d.translation,
              let place = translation.locationText?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty
        else { return nil }
        return "Plats (översatt från \(swedishLanguageName(translation.sourceLanguage))): \(place)"
    }

    /// `Jag anmälde detta tidigare den 2026-10-20 (ärende 123).`, when the resident sends again anyway.
    static func previousReportLine(for d: ReportDraft) -> String? {
        guard let previous = d.previousReport else { return nil }
        let date = String(stockholmTimestamp(previous.date).prefix(10))
        if let number = previous.caseNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !number.isEmpty {
            return "Jag anmälde detta tidigare den \(date) (ärende \(number))."
        }
        return "Jag anmälde detta tidigare den \(date)."
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

    /// What the municipality's form receives as text, in Swedish: `Område`, `Plats` and the
    /// description exactly as `description(for:spec:now:)` sends it. Never the contact details.
    /// Kept in Sent reports so the resident can see what was filed.
    public static func filedText(for d: ReportDraft, spec: AdapterSpec, now: Date = Date()) -> String {
        let place = placeText(for: d)
        return [
            "Område: \(spec.category(for: d)?.value ?? "-")",
            "Plats: \(place.isEmpty ? "-" : place)",
            "",
            "Beskrivning:",
            description(for: d, spec: spec, now: now),
        ].joined(separator: "\n")
    }

    /// `locationText (lat, lng)`, the coordinates rounded to 5 decimals (about a metre).
    public static func placeText(for d: ReportDraft) -> String {
        let text = d.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = d.coordinate else { return text }
        let coordinate = "\(rounded(c.latitude)), \(rounded(c.longitude))"
        return text.isEmpty ? coordinate : "\(text) (\(coordinate))"
    }

    static func rounded(_ value: Double) -> Double {
        (value * 100_000).rounded() / 100_000
    }
}

/// Plain Swedish report text the resident pastes into the municipality's own web form when Fixa cannot
/// send (`AdapterSpec.webFormURL`). The resident attaches the photo there themselves.
public enum WebFallback {
    public static func text(_ d: ReportDraft, spec: AdapterSpec, now: Date = Date()) -> String {
        var lines = [ReportComposer.filedText(for: d, spec: spec, now: now)]

        guard d.wantsFeedback else { return lines.joined(separator: "\n") }
        lines += ["", "Jag vill ha återkoppling."]
        let contact = d.contact
        let name = [contact.firstName, contact.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let phone = contact.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = contact.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { lines.append("Namn: \(name)") }
        if !phone.isEmpty { lines.append("Telefon: \(phone)") }
        if !email.isEmpty { lines.append("E-post: \(email)") }
        return lines.joined(separator: "\n")
    }
}
