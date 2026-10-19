import Foundation

/// One Abou answer control, e.g. `…$KSB_14_field$dropDownListFieldControl`.
struct FormControl: Sendable, Equatable {
    /// Full input name, HTML-unescaped.
    let name: String
    /// Part before `_field$`, e.g. `KSB_14`.
    let key: String
    /// Part after `_field$`, e.g. `dropDownListFieldControl`.
    let control: String
    /// `select`, `textarea`, `radio`, `checkbox`, `hidden` or `text`.
    let type: String
    /// Select options or radio choices with their visible text.
    let options: [FormOption]
}

struct FormOption: Sendable, Equatable {
    let value: String
    let text: String
}

/// A question block: the visible label (or legend), whether it is marked required, and its controls.
struct FormQuestion: Sendable, Equatable {
    let label: String
    let required: Bool
    let controls: [FormControl]
}

/// The answerable structure of one Abou page.
struct FormStructure: Sendable {
    let controls: [FormControl]
    let questions: [FormQuestion]

    init(html: String) {
        let labelTexts = Dictionary(
            AbouPageParser.matches(#"<label\b([^>]*)>(.*?)</label>"#, in: html, options: [.caseInsensitive, .dotMatchesLineSeparators])
                .compactMap { m -> (String, String)? in
                    guard let id = AbouPageParser.attributes(of: "<label \(m[1])>")["for"] else { return nil }
                    return (id, AbouPageParser.visibleText(m[2]))
                },
            uniquingKeysWith: { first, _ in first }
        )

        // Controls in page order, radio buttons of one group merged into a single control.
        var located: [(location: Int, control: FormControl)] = []
        var indexByName: [String: Int] = [:]
        let pattern = #"<select\b([^>]*)>(.*?)</select>|<textarea\b([^>]*)>|<input\b([^>]*)>"#
        for (location, m) in Self.locatedMatches(pattern, in: html) {
            let isSelect = !m[1].isEmpty || m[0].lowercased().hasPrefix("<select")
            let isTextarea = m[0].lowercased().hasPrefix("<textarea")
            let attributes = AbouPageParser.attributes(of: "<x \(isSelect ? m[1] : isTextarea ? m[3] : m[4])>")
            guard let name = attributes["name"], let split = Self.split(name) else { continue }
            let type: String
            var options: [FormOption] = []
            if isSelect {
                type = "select"
                options = AbouPageParser.matches(#"<option\b([^>]*)>(.*?)</option>"#, in: m[2], options: [.caseInsensitive, .dotMatchesLineSeparators])
                    .map { o in
                        let text = AbouPageParser.visibleText(o[2])
                        return FormOption(value: AbouPageParser.attributes(of: "<x \(o[1])>")["value"] ?? text, text: text)
                    }
            } else if isTextarea {
                type = "textarea"
            } else {
                let raw = attributes["type"]?.lowercased() ?? "text"
                type = ["radio", "checkbox", "hidden"].contains(raw) ? raw : "text"
                if raw == "radio" || raw == "checkbox" {
                    let value = attributes["value"] ?? "on"
                    let text = attributes["id"].flatMap { labelTexts[$0] } ?? value
                    options = [FormOption(value: value, text: text)]
                }
            }
            if let existing = indexByName[name] {
                let old = located[existing].control
                located[existing].control = FormControl(name: old.name, key: old.key, control: old.control, type: old.type, options: old.options + options)
            } else {
                indexByName[name] = located.count
                located.append((location, FormControl(name: name, key: split.key, control: split.control, type: type, options: options)))
            }
        }
        controls = located.map(\.control)

        // Question blocks run from one `field-question-block` to the next.
        let starts = Self.locatedMatches(#"class="[^"]*\bfield-question-block\b[^"]*"[^>]*>"#, in: html)
            .map { $0.location + ($0.groups[0] as NSString).length }
        let ns = html as NSString
        var questions: [FormQuestion] = []
        for (i, start) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1] : ns.length
            let block = ns.substring(with: NSRange(location: start, length: end - start))
            let head = block.range(of: #"</label>|</legend>"#, options: [.regularExpression, .caseInsensitive])
                .map { String(block[..<$0.lowerBound]) } ?? ""
            let label = AbouPageParser.visibleText(head).replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let required = AbouPageParser.matches(#"<span\b[^>]*class="[^"]*required-label[^"]*"[^>]*>"#, in: head, options: [.caseInsensitive])
                .contains { !$0[0].replacingOccurrences(of: " ", with: "").lowercased().contains("display:none") }
            let inside = located.filter { $0.location >= start && $0.location < end }.map(\.control)
            questions.append(FormQuestion(label: label, required: required, controls: inside))
        }
        self.questions = questions
    }

    /// `…$KSB_14_field$dropDownListFieldControl` → (`KSB_14`, `dropDownListFieldControl`).
    static func split(_ name: String) -> (key: String, control: String)? {
        guard let marker = name.range(of: "_field$", options: .backwards) else { return nil }
        let control = String(name[marker.upperBound...])
        let key = String(name[..<marker.lowerBound].split(separator: "$", omittingEmptySubsequences: false).last ?? "")
        guard !key.isEmpty, !control.isEmpty, !control.contains("$") else { return nil }
        return (key, control)
    }

    static func locatedMatches(_ pattern: String, in text: String) -> [(location: Int, groups: [String])] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (m.range.location, (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            })
        }
    }

    /// Case- and diacritic-insensitive comparison key; ignores `*`, trailing `:` and extra whitespace.
    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "*", with: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":.").union(.whitespaces))
    }

    // MARK: - Resolution

    /// Exact key and control → same key, same kind of input → a same-kind control under a matching label.
    func control(for field: AdapterSpec.FieldSpec, excluding taken: Set<String> = []) -> FormControl? {
        let free = controls.filter { !taken.contains($0.name) }
        if let exact = free.first(where: { $0.key == field.key && $0.control == field.control }) { return exact }
        if let sameKey = free.first(where: { $0.key == field.key && compatible($0, field) }) { return sameKey }
        let wanted = Set(field.allLabels.map(Self.normalize).filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return nil }
        for question in questions where wanted.contains(Self.normalize(question.label)) {
            if let match = question.controls.first(where: { !taken.contains($0.name) && compatible($0, field) }) { return match }
        }
        return nil
    }

    private func compatible(_ candidate: FormControl, _ field: AdapterSpec.FieldSpec) -> Bool {
        candidate.control == field.control || field.type?.lowercased() == candidate.type
    }

    /// Exact value → visible text or value equal after normalising → a configured synonym.
    static func option(for wanted: String, synonyms: [String], in options: [FormOption]) -> String? {
        if options.contains(where: { $0.value == wanted }) { return wanted }
        for candidate in [wanted] + synonyms {
            let key = normalize(candidate)
            guard !key.isEmpty else { continue }
            if let match = options.first(where: { normalize($0.text) == key || normalize($0.value) == key }) { return match.value }
        }
        return nil
    }

    /// Labels of required questions none of whose controls are in `filled`.
    func unfilledRequired(filled: Set<String>) -> [String] {
        questions
            .filter { $0.required && !$0.controls.isEmpty && !$0.controls.contains { filled.contains($0.name) } }
            .map { $0.label.isEmpty ? $0.controls[0].key : $0.label }
    }
}
