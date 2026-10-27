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

    /// Tolerant receipt reading: nil for form pages, error pages, session locks and any page that neither
    /// shows a case number nor says the report was received (a proxy error, an empty page).
    public static func parseReceipt(html: String, url: URL, now: Date) -> SubmissionReceipt? {
        if isSessionLocked(html) || !validationErrors(html).isEmpty { return nil }
        if html.contains("_field$") || decodeEntities(html).contains("Ärendet har inte skickats in") { return nil }
        if url.path.localizedCaseInsensitiveContains("GenericError") { return nil }
        if let action = formAction(html), action.localizedCaseInsensitiveContains("GenericError") { return nil }

        let title = matches(#"<title[^>]*>(.*?)</title>"#, in: html, options: [.caseInsensitive, .dotMatchesLineSeparators])
            .first.map { visibleText($0[1]) } ?? ""
        let message = String((receiptText(html) ?? mainText(html)).prefix(2000))
        let number = caseNumber(in: message) ?? caseNumber(in: title)
        guard number != nil || saysReceived(title + " " + message) else { return nil }
        return SubmissionReceipt(
            caseNumber: number,
            finalURL: url,
            title: title,
            message: message,
            submittedAt: now
        )
    }

    /// Swedish wording of a confirmation page ("Tack…", "vi har tagit emot ditt ärende", "kvittens").
    static func saysReceived(_ text: String) -> Bool {
        !matches(#"(?i)\b(tack|tagit emot|mottagits?|mottagen|registrerats?|inskickad|kvittens)\b"#, in: text).isEmpty
    }

    // MARK: - Internals

    static func caseNumber(in text: String) -> String? {
        let pattern = #"(?i)(?:ärendenummer|ärende-?nr|ärende-?id|diarienummer|referens(?:nummer)?)[^0-9A-Za-zÅÄÖåäö]{0,20}(?:(?:är|is)\s+)?([A-Z0-9][A-Z0-9-]{2,})"#
        return matches(pattern, in: text)
            .map { $0[1] }
            .first { $0.contains(where: \.isNumber) }
    }

    /// Removes elements whose content is never visible text (scripts span lines, hence `(?is)`).
    static func withoutInvisible(_ html: String, tags: [String] = ["script", "style", "head", "noscript", "header", "footer", "nav", "svg"]) -> String {
        var body = html
        for tag in tags {
            body = body.replacingOccurrences(of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>", with: " ", options: .regularExpression)
        }
        return body
    }

    static func mainText(_ html: String) -> String {
        var body = withoutInvisible(html)
        if let main = matches(#"<main\b[^>]*>(.*?)</main>"#, in: body, options: [.caseInsensitive, .dotMatchesLineSeparators]).first {
            body = main[1]
        }
        return visibleText(body)
    }

    /// The municipality's own words on Abou's thank-you page, one paragraph per line: the thank-you
    /// block (`pagecontent thankYou`), then the grey info box ("svar inom 5 arbetsdagar"). Nil when the
    /// page has no thank-you block.
    static func receiptText(_ html: String) -> String? {
        let body = withoutInvisible(html)
        guard let start = body.range(of: #"<div[^>]+class="[^"]*\bpagecontent\b[^"]*"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var block = String(body[start.lowerBound...])
        if let end = block.range(of: "</main>", options: .caseInsensitive) { block = String(block[..<end.lowerBound]) }
        var parts = [paragraphs(block)]
        if let grey = matches(#"<div[^>]+class="[^"]*\bgreyboxcontent\b[^"]*"[^>]*>(.*?)</div>"#, in: body, options: [.caseInsensitive, .dotMatchesLineSeparators]).first {
            parts.append(paragraphs(grey[1]))
        }
        let text = parts.filter { !$0.isEmpty }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// Visible text with block boundaries (`p`, `br`, headings, `div`, `li`) as line breaks; blank and
    /// repeated lines dropped.
    static func paragraphs(_ fragment: String) -> String {
        let marked = fragment.replacingOccurrences(of: #"(?i)<br\s*/?>|</?(p|div|h[1-6]|li|ul|ol|tr|section)\b[^>]*>"#, with: "\n", options: .regularExpression)
        var lines: [String] = []
        for raw in marked.components(separatedBy: "\n") {
            let line = visibleText(raw)
            if !line.isEmpty, line != lines.last { lines.append(line) }
        }
        return lines.joined(separator: "\n")
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
        let named = namedEntities
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

    /// HTML named character references: the full Latin-1 set (Swedish pages use `&aring;`, `&auml;`,
    /// `&ouml;`) plus common punctuation.
    static let namedEntities: [String: String] = {
        var table: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
            "sbquo": "\u{201A}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}", "bull": "\u{2022}",
            "euro": "\u{20AC}", "trade": "\u{2122}", "thinsp": "\u{2009}", "ensp": "\u{2002}", "emsp": "\u{2003}",
            "zwnj": "\u{200C}", "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}", "OElig": "Œ", "oelig": "œ",
            "Scaron": "Š", "scaron": "š", "Yuml": "Ÿ"]
        // U+00A0 … U+00FF in HTML 4 order.
        let latin1 = "nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn sup2 sup3 acute micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc Atilde Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig agrave aacute acirc atilde auml aring aelig ccedil egrave eacute ecirc euml igrave iacute icirc iuml eth ntilde ograve oacute ocirc otilde ouml divide oslash ugrave uacute ucirc uuml yacute thorn yuml"
        for (offset, name) in latin1.split(separator: " ").enumerated() {
            table[String(name)] = String(Character(Unicode.Scalar(0xA0 + offset)!))
        }
        table["nbsp"] = " "
        return table
    }()

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
