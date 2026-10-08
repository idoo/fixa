import Foundation

/// Pure parsing of Abou (ASP.NET WebForms) pages.
public enum AbouPageParser {
    /// Every `<input type="hidden">` with a name, values HTML-unescaped.
    public static func hiddenFields(_ html: String) -> [String: String] {
        var result: [String: String] = [:]
        for tag in matches(#"<input\b[^>]*>"#, in: html, options: [.caseInsensitive]).map({ $0[0] }) {
            let attributes = attributes(of: tag)
            guard attributes["type"]?.lowercased() == "hidden", let name = attributes["name"] else { continue }
            result[name] = attributes["value"] ?? ""
        }
        return result
    }

    /// The `action` of the main form, HTML-unescaped and still relative (e.g. `./BlockPage.aspx?eServiceName=KSB&PageId=FaultReport`).
    public static func formAction(_ html: String) -> String? {
        let forms = matches(#"<form\b[^>]*>"#, in: html, options: [.caseInsensitive]).map { attributes(of: $0[0]) }
        let form = forms.first { $0["id"] == "MainForm" } ?? forms.first
        return form?["action"]
    }

    public static func fieldName(_ html: String, key: String, control: String) -> String? {
        let pattern = #"name="((?:[^"]*\$)?"# + NSRegularExpression.escapedPattern(for: "\(key)_field$\(control)") + #")""#
        return matches(pattern, in: html).first.map { decodeEntities($0[1]) }
    }

    /// Messages of `<label class="validation-error-label">`, in page order.
    public static func validationErrors(_ html: String) -> [String] {
        matches(#"<label\b[^>]*class="[^"]*validation-error-label[^"]*"[^>]*>(.*?)</label>"#, in: html, options: [.caseInsensitive, .dotMatchesLineSeparators])
            .map { visibleText($0[1]) }
            .filter { !$0.isEmpty }
    }

    public static func isSessionLocked(_ html: String) -> Bool {
        decodeEntities(html).contains("Du har ett ärende igång redan")
    }

    /// The `PageId` query value, e.g. `FaultReport`.
    public static func pageID(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: true)?
            .queryItems?
            .first { $0.name.caseInsensitiveCompare("PageId") == .orderedSame }?
            .value
    }

    /// Tolerant receipt reading: nil for form pages, error pages and session locks.
    public static func parseReceipt(html: String, url: URL, now: Date) -> SubmissionReceipt? {
        if isSessionLocked(html) || !validationErrors(html).isEmpty { return nil }
        if html.contains("_field$") || decodeEntities(html).contains("Ärendet har inte skickats in") { return nil }
        if url.path.localizedCaseInsensitiveContains("GenericError") { return nil }
        if let action = formAction(html), action.localizedCaseInsensitiveContains("GenericError") { return nil }

        let title = matches(#"<title[^>]*>(.*?)</title>"#, in: html, options: [.caseInsensitive, .dotMatchesLineSeparators])
            .first.map { visibleText($0[1]) } ?? ""
        let message = String(mainText(html).prefix(2000))
        return SubmissionReceipt(
            caseNumber: caseNumber(in: message) ?? caseNumber(in: title),
            finalURL: url,
            title: title,
            message: message,
            submittedAt: now
        )
    }

    // MARK: - Internals

    static func caseNumber(in text: String) -> String? {
        let pattern = #"(?i)(?:ärendenummer|ärende-?nr|ärende-?id|diarienummer|referens(?:nummer)?)[^0-9A-Za-zÅÄÖåäö]{0,20}(?:(?:är|is)\s+)?([A-Z0-9][A-Z0-9-]{2,})"#
        return matches(pattern, in: text)
            .map { $0[1] }
            .first { $0.contains(where: \.isNumber) }
    }

    static func mainText(_ html: String) -> String {
        var body = html
        for tag in ["script", "style", "head", "noscript", "header", "footer", "nav"] {
            body = body.replacingOccurrences(of: "<\(tag)\\b[^>]*>.*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        if let main = matches(#"<main\b[^>]*>(.*?)</main>"#, in: body, options: [.caseInsensitive, .dotMatchesLineSeparators]).first {
            body = main[1]
        }
        return visibleText(body)
    }

    static func visibleText(_ fragment: String) -> String {
        let stripped = fragment.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeEntities(stripped)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func attributes(of tag: String) -> [String: String] {
        var result: [String: String] = [:]
        for m in matches(#"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#, in: tag) {
            let value = m[2].isEmpty ? m[3] : m[2]
            result[m[1].lowercased()] = decodeEntities(value)
        }
        return result
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let entity = after[..<semi]
                var replacement: String?
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if entity.hasPrefix("#") {
                    replacement = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    replacement = named[String(entity)]
                }
                if let replacement {
                    out += replacement
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        out += rest
        return out
    }

    /// Capture groups per match; group 0 is the whole match, missing groups are "".
    static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
}
