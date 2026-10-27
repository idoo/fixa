import Foundation

/// Sends a report through an Abou e-service with plain HTTP, page by page, as described by the spec's channel.
public struct AbouSubmitter: Sendable {
    public let spec: AdapterSpec
    let transport: HTTPTransport
    /// Pause before every request after the first, so a send never hammers the e-service.
    let pageDelay: Duration

    public init(spec: AdapterSpec, transport: HTTPTransport = URLSessionTransport.ephemeral(), pageDelay: Duration = .milliseconds(400)) {
        self.spec = spec
        self.transport = transport
        self.pageDelay = pageDelay
    }

    /// Requests look like Safari on an iPhone filling in the form on the website, so the municipality
    /// sees the same report it would get from its own web page. (Safari 26 freezes the OS token at 18_6.)
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
    static let acceptHTML = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    static let acceptLanguage = "sv-SE,sv;q=0.9"

    /// Camera-roll style name for the uploaded photo, e.g. `IMG_4821.jpg`.
    static func photoFileName() -> String {
        String(format: "IMG_%04d.jpg", Int.random(in: 1...9999))
    }

    /// dryRun=true stops at the Summary page and returns nil receipt (no case created).
    ///
    /// A locked or expired session before the final confirmation starts over once from `introPath`
    /// with fresh cookies. Once the final confirmation has been sent nothing is retried or restarted:
    /// any failure to read the receipt is `.uncertain`.
    public func submit(
        _ draft: ReportDraft,
        dryRun: Bool = false,
        progress: @Sendable (SubmissionStage) -> Void = { _ in }
    ) async throws -> SubmissionReceipt? {
        let channel = spec.channel
        guard channel.kind == "abou" else { throw SubmissionError.invalidSpec("Unsupported channel kind \(channel.kind)") }
        guard let base = URL(string: channel.baseURL), !channel.pages.isEmpty else {
            throw SubmissionError.invalidSpec("Bad baseURL or no pages")
        }

        progress(.starting)
        do {
            return try await walk(draft, base: base, dryRun: dryRun, restart: false, progress: progress)
        } catch is SessionLost {
            do {
                return try await walk(draft, base: base, dryRun: dryRun, restart: true, progress: progress)
            } catch let lost as SessionLost {
                throw lost.error
            }
        }
    }

    /// The session ended under us before the final send; `submit` may start over once.
    struct SessionLost: Error {
        let error: SubmissionError
    }

    /// One pass from a fresh session to the receipt. Throws `SessionLost` only before the final send.
    private func walk(
        _ draft: ReportDraft,
        base: URL,
        dryRun: Bool,
        restart: Bool,
        progress: @Sendable (SubmissionStage) -> Void
    ) async throws -> SubmissionReceipt? {
        let channel = spec.channel
        (transport as? URLSessionTransport)?.clearCookies()
        _ = try await get(try url(channel.introPath, base: base), pausing: restart)
        var page = try await get(try url(channel.startPath, base: base))
        try checkSession(page)

        // The platform may skip pages (Värmdö skips contact details when no reply is wanted),
        // so each response may land on the expected page or any later one.
        var index = 0
        while index < channel.pages.count {
            index = try position(of: page, from: index)
            let pageSpec = channel.pages[index]

            if index == channel.pages.count - 1 {
                if dryRun {
                    progress(.done)
                    return nil
                }
                progress(.confirming)
                let receipt = try await confirm(page)
                progress(.done)
                return receipt
            }

            if let upload = channel.upload, upload.pageID == pageSpec.id, let photo = draft.photoJPEG {
                progress(.uploadingPhoto)
                try await uploadPhoto(photo, upload: upload, base: base)
            }

            progress(stage(pageSpec.stage))
            page = try await post(page, values: try values(for: pageSpec, draft: draft, html: page.html))
            index += 1
        }
        throw SubmissionError.invalidSpec("No summary page")
    }

    /// Sends Slutför on the summary page and reads the receipt.
    private func confirm(_ summary: Page) async throws -> SubmissionReceipt {
        let request = try postRequest(summary, values: [])
        try await pause()
        // ---- FINAL SEND: from the next line on the case may exist. ----
        // This request is sent exactly once. No retry and no session restart past this point; anything
        // but a receipt or the server's own validation messages is `.uncertain`, including 429/5xx,
        // timeouts, redirects off the host, maintenance and login pages.
        var page: Page
        do {
            page = try await self.page(request, pausing: false)
            page = try await finishProcessing(page, finalURL: request.url)
        } catch let error as SubmissionError {
            throw SubmissionError.uncertain("No answer after the final confirmation was sent: \(error)")
        } catch {
            throw SubmissionError.uncertain("No answer after the final confirmation was sent: \(error.localizedDescription)")
        }
        if isLocked(page.html) {
            throw SubmissionError.uncertain("After the final confirmation the e-service said a case is already open (\(page.url.absoluteString)).")
        }
        let errors = AbouPageParser.validationErrors(page.html)
        if !errors.isEmpty { throw SubmissionError.serverValidation(errors) }
        guard let receipt = AbouPageParser.parseReceipt(html: page.html, url: page.url, now: Date()) else {
            throw SubmissionError.uncertain("After the final confirmation the e-service showed a page without a receipt (\(page.url.absoluteString)).")
        }
        return receipt
    }

    // MARK: - Pages

    struct Page {
        let html: String
        let url: URL
    }

    private func isLocked(_ html: String) -> Bool {
        html.contains(spec.channel.sessionLockedMarker)
            || AbouPageParser.decodeEntities(html).contains(spec.channel.sessionLockedMarker)
    }

    /// Before the final send: a page saying another case is open, or the platform's generic error /
    /// intro page instead of a form page (the session expired), means start over.
    private func checkSession(_ page: Page) throws {
        if isLocked(page.html) { throw SessionLost(error: .sessionLocked) }
        let action = AbouPageParser.formAction(page.html) ?? ""
        let bouncedToIntro = page.url.path.caseInsensitiveCompare(spec.channel.introPath) == .orderedSame
        if page.url.path.localizedCaseInsensitiveContains("GenericError")
            || action.localizedCaseInsensitiveContains("GenericError")
            || bouncedToIntro {
            throw SessionLost(error: .transport("The e-service ended the session (\(page.url.absoluteString))."))
        }
    }

    private func currentPageID(_ page: Page) -> String? {
        if let action = AbouPageParser.formAction(page.html), let actionURL = URL(string: action, relativeTo: page.url),
           let id = AbouPageParser.pageID(from: actionURL) {
            return id
        }
        return AbouPageParser.pageID(from: page.url)
    }

    /// Index of the page we are on, searching `pages[from...]` by page id, then by finding the page's fields;
    /// otherwise the most specific error.
    private func position(of page: Page, from start: Int) throws -> Int {
        let pages = spec.channel.pages
        let current = currentPageID(page)
        if let index = pages[start...].firstIndex(where: { $0.id == current }) { return index }
        try checkSession(page)
        let errors = AbouPageParser.validationErrors(page.html)
        if !errors.isEmpty { throw SubmissionError.serverValidation(errors) }

        // The page id may have been renamed: accept a page whose adapter fields are all on it.
        let form = FormStructure(html: page.html)
        if let index = pages[start...].firstIndex(where: { candidate in
            !candidate.fields.isEmpty && resolve(candidate.fields, in: form) != nil
        }) {
            return index
        }
        let required = form.unfilledRequired(filled: [])
        let expected = pages[start...].map(\.id).joined(separator: " or ")
        throw SubmissionError.formChanged(FormDrift(
            pageID: current,
            missing: required,
            detail: "Fixa expected the page \(expected) but got \(current ?? page.url.absoluteString)"
                + (required.isEmpty ? "." : ", which asks for required fields Fixa doesn't fill.")
        ))
    }

    /// Controls for every field, each control used once; nil if any field is not on the page.
    private func resolve(_ fields: [AdapterSpec.FieldSpec], in form: FormStructure) -> [FormControl]? {
        var taken: Set<String> = []
        var result: [FormControl] = []
        for field in fields {
            guard let control = form.control(for: field, excluding: taken) else { return nil }
            taken.insert(control.name)
            result.append(control)
        }
        return result
    }

    private func stage(_ name: String) -> SubmissionStage {
        switch name {
        case "sendingContact": .sendingContact
        case "confirming": .confirming
        default: .sendingReport
        }
    }

    /// Name/value pairs for the page; `.formChanged` listing every field, option or new required
    /// question that doesn't match the adapter.
    private func values(for page: AdapterSpec.PageSpec, draft: ReportDraft, html: String) throws -> [(String, String)] {
        let form = FormStructure(html: html)
        var taken: Set<String> = []
        var pairs: [(String, String)] = []
        var missing: [String] = []
        for field in page.fields {
            let label = field.allLabels.first ?? "\(field.role.rawValue) (\(field.key))"
            guard let control = form.control(for: field, excluding: taken) else {
                missing.append(label)
                continue
            }
            taken.insert(control.name)
            var value = value(for: field, draft: draft)
            if !value.isEmpty, !control.options.isEmpty {
                let synonyms = field.role == .category
                    ? spec.category(for: draft)?.synonyms ?? []
                    : field.optionSynonyms?[value] ?? []
                guard let resolved = FormStructure.option(for: value, synonyms: synonyms, in: control.options) else {
                    missing.append("\(label): \(value)")
                    continue
                }
                value = resolved
            }
            pairs.append((control.name, value))
        }
        for question in form.unfilledRequired(filled: taken) where !missing.contains(question) {
            missing.append(question)
        }
        guard missing.isEmpty else {
            throw SubmissionError.formChanged(FormDrift(
                pageID: page.id,
                missing: missing,
                detail: "Some fields on this page are missing, renamed beyond recognition, or new and required."
            ))
        }
        return pairs
    }

    private func value(for field: AdapterSpec.FieldSpec, draft: ReportDraft) -> String {
        let contact = draft.contact
        switch field.role {
        case .category: return spec.category(for: draft)?.value ?? ""
        case .place: return ReportComposer.placeText(for: draft)
        case .mapChoice: return (draft.coordinate != nil ? field.yesValue : field.noValue) ?? ""
        case .mapAnswer: return draft.coordinate?.formValue ?? ""
        case .description: return ReportComposer.description(for: draft, spec: spec)
        case .feedback: return (draft.wantsFeedback ? field.yesValue : field.noValue) ?? ""
        case .firstName: return contact.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .lastName: return contact.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .phone: return contact.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        case .email: return contact.email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Upload

    private func uploadPhoto(_ photo: Data, upload: AdapterSpec.UploadSpec, base: URL) async throws {
        let boundary = "----WebKitFormBoundary" + String((0..<16).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(upload.filePartName)\"; filename=\"\(Self.photoFileName())\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(photo)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = makeRequest(try url(upload.path, base: base), method: "POST", timeout: SubmissionTimeouts.upload)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        let uploaded = try json(try await send(request).0)
        guard uploaded["success"] as? Bool == true else {
            throw SubmissionError.uploadFailed(uploaded["message"] as? String ?? "Upload rejected")
        }

        var verify = makeRequest(try url(upload.actionPath, base: base), method: "POST")
        verify.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        verify.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        verify.setValue("application/json", forHTTPHeaderField: "Accept")
        verify.httpBody = try JSONSerialization.data(withJSONObject: [
            "FieldId": upload.fieldID,
            "Properties": ["action": "getFiles"],
        ])
        let files = try json(try await send(verify).0)
        guard files["success"] as? Bool == true, let list = files["files"] as? [Any], !list.isEmpty else {
            throw SubmissionError.uploadFailed("Photo not attached to \(upload.fieldID)")
        }
    }

    private func json(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubmissionError.uploadFailed(String(decoding: data.prefix(200), as: UTF8.self))
        }
        return object
    }

    // MARK: - HTTP

    private func url(_ path: String, base: URL) throws -> URL {
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw SubmissionError.invalidSpec("Bad path \(path)")
        }
        return url
    }

    private func makeRequest(_ url: URL, method: String, timeout: TimeInterval = SubmissionTimeouts.page) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        return request
    }

    private func get(_ url: URL, pausing: Bool = true) async throws -> Page {
        var request = makeRequest(url, method: "GET")
        request.setValue(Self.acceptHTML, forHTTPHeaderField: "Accept")
        return try await page(request, pausing: pausing)
    }

    /// The page after Slutför may only say "Dina uppgifter bearbetas…" and finish the case with a
    /// script-driven `__doPostBack('', '')` on load. Do what the browser does until the marker is gone,
    /// but never by posting to the final confirmation's URL again.
    private func finishProcessing(_ start: Page, finalURL: URL?) async throws -> Page {
        guard let marker = spec.channel.completionPostBackMarker, !marker.isEmpty else { return start }
        var page = start
        var remaining = spec.channel.maxCompletionPostBacks ?? 3
        while remaining > 0, page.html.contains(marker), AbouPageParser.formAction(page.html) != nil {
            let request = try postRequest(page, values: [], eventTarget: "")
            if request.url == finalURL {
                throw SubmissionError.uncertain("The page after the final confirmation posts back to it (\(page.url.absoluteString)); not sending it twice.")
            }
            page = try await self.page(request)
            remaining -= 1
        }
        return page
    }

    /// Posts the page's form with all hidden inputs, an event target (the Next button by default) and `values`.
    private func post(_ page: Page, values: [(String, String)], eventTarget: String? = nil) async throws -> Page {
        try await self.page(try postRequest(page, values: values, eventTarget: eventTarget))
    }

    /// The form POST for `page`, built without sending anything.
    private func postRequest(_ page: Page, values: [(String, String)], eventTarget: String? = nil) throws -> URLRequest {
        guard let action = AbouPageParser.formAction(page.html),
              let target = URL(string: action, relativeTo: page.url)?.absoluteURL else {
            throw SubmissionError.formChanged(FormDrift(
                pageID: currentPageID(page),
                missing: [],
                detail: "The page has no form to send (\(page.url.absoluteString))."
            ))
        }
        var fields = AbouPageParser.hiddenFields(page.html)
        fields["__EVENTTARGET"] = eventTarget ?? spec.channel.nextEventTarget
        fields["__EVENTARGUMENT"] = ""
        for (name, value) in values { fields[name] = value }

        var request = makeRequest(target, method: "POST")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.acceptHTML, forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncode(fields.sorted { $0.key < $1.key }).utf8)
        return request
    }

    /// Sends `request` and reads the HTML page. A maintenance or login page is never a form page or
    /// a receipt: before the final send it is `.unavailable` / `.formChanged`, after it `confirm`
    /// turns it into `.uncertain`.
    private func page(_ request: URLRequest, pausing: Bool = true) async throws -> Page {
        let (data, response) = try await send(request, pausing: pausing)
        let page = Page(html: String(decoding: data, as: UTF8.self), url: response.url ?? request.url!)
        if Self.isOutagePage(page.html) {
            throw SubmissionError.unavailable(status: nil, retryAfter: nil)
        }
        if Self.isLoginPage(page) {
            throw SubmissionError.formChanged(FormDrift(
                pageID: nil,
                missing: [],
                detail: "The e-service asked to log in (\(page.url.absoluteString))."
            ))
        }
        return page
    }

    /// Waits `pageDelay`, then sends. Requests go only to the adapter's own host, over HTTPS; a redirect
    /// that leaves it (refused by `RedirectGuard`, or followed by some other transport) is an error.
    /// 429 and 5xx are `.unavailable` with the server's `Retry-After`.
    private func send(_ request: URLRequest, pausing: Bool = true) async throws -> (Data, HTTPURLResponse) {
        guard isAllowed(request.url) else {
            throw SubmissionError.formChanged(FormDrift(
                pageID: nil,
                missing: [],
                detail: "The e-service form points outside \(allowedHost ?? "its host") (\(request.url?.absoluteString ?? "-"))."
            ))
        }
        if pausing { try await pause() }
        let result: (Data, HTTPURLResponse)
        do {
            result = try await transport.send(request)
        } catch let error as SubmissionError {
            throw error
        } catch {
            throw SubmissionError.transport(error.localizedDescription)
        }
        let response = result.1
        let status = response.statusCode
        switch status {
        case 200..<300:
            break
        case 300..<400:
            let location = response.value(forHTTPHeaderField: "Location") ?? "-"
            throw SubmissionError.transport("The e-service redirected to \(location); Fixa only follows redirects within \(allowedHost ?? "its host").")
        case 429, 500..<600:
            throw SubmissionError.unavailable(status: status, retryAfter: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
        default:
            throw SubmissionError.http(status)
        }
        if let url = response.url, !isAllowed(url) {
            throw SubmissionError.transport("The e-service answered from \(url.host ?? url.absoluteString), not \(allowedHost ?? "its host").")
        }
        return result
    }

    private var allowedHost: String? { URL(string: spec.channel.baseURL)?.host?.lowercased() }

    private func isAllowed(_ url: URL?) -> Bool {
        guard let url, let host = allowedHost else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == host
    }

    private func pause() async throws {
        guard pageDelay > .zero else { return }
        do {
            try await Task.sleep(for: pageDelay)
        } catch {
            throw SubmissionError.transport("Cancelled")
        }
    }

    /// `Retry-After` as seconds (`120`) or an HTTP date, clamped to 0…1 day; nil if absent or unreadable.
    static func retryAfter(_ header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        let seconds: TimeInterval
        if let value = TimeInterval(header) {
            seconds = value
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            guard let date = formatter.date(from: header) else { return nil }
            seconds = date.timeIntervalSince(now)
        }
        return min(max(seconds, 0), 24 * 60 * 60)
    }

    /// "Service Unavailable", maintenance and outage pages, which some servers send with HTTP 200.
    static func isOutagePage(_ html: String) -> Bool {
        let text = AbouPageParser.decodeEntities(html).lowercased()
        return outageMarkers.contains { text.contains($0) }
    }

    static let outageMarkers = [
        "service unavailable", "temporarily unavailable", "under maintenance", "maintenance mode",
        "planerat underhåll", "pågående underhåll", "underhållsarbete", "tillfälligt ur drift",
        "tillfälligt otillgänglig", "tillfälligt stängd",
    ]

    /// A sign-in page: a password field, or a login URL. (Every Abou page links to `/web/login.aspx`;
    /// only being *on* it counts.)
    static func isLoginPage(_ page: Page) -> Bool {
        let path = page.url.path.lowercased()
        if ["login", "logon", "signin", "/auth"].contains(where: path.contains) { return true }
        return page.html.range(of: #"type\s*=\s*["']?password"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func formEncode(_ pairs: [(key: String, value: String)]) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        allowed.insert(charactersIn: "-._* ")
        func encode(_ s: String) -> String {
            (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s).replacingOccurrences(of: " ", with: "+")
        }
        return pairs.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&")
    }
}
