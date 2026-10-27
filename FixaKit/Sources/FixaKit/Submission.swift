import Foundation

public struct SubmissionReceipt: Codable, Sendable, Equatable {
    public let caseNumber: String?
    public let finalURL: URL
    public let title: String
    public let message: String
    public let submittedAt: Date

    public init(caseNumber: String?, finalURL: URL, title: String, message: String, submittedAt: Date) {
        self.caseNumber = caseNumber
        self.finalURL = finalURL
        self.title = title
        self.message = message
        self.submittedAt = submittedAt
    }
}

/// The live e-service no longer looks like the adapter describes: a page, field or option moved,
/// was renamed beyond what the adapter's fallbacks recognise, or a new required field appeared.
public struct FormDrift: Error, Sendable, Equatable {
    /// `PageId` of the page where the mismatch was found, if the page had one.
    public var pageID: String?
    /// Human-readable labels (or keys) of fields and options Fixa could not fill.
    public var missing: [String]
    /// One sentence for logs and `fixa-cli dry-run`.
    public var detail: String

    public init(pageID: String?, missing: [String], detail: String) {
        self.pageID = pageID
        self.missing = missing
        self.detail = detail
    }

    /// One paragraph for logs and `fixa-cli dry-run`.
    public var report: String {
        var text = "The e-service form no longer matches the adapter"
        text += pageID.map { " on page \($0)" } ?? ""
        text += ". \(detail)"
        if !missing.isEmpty { text += " Missing: \(missing.joined(separator: "; "))." }
        return text
    }
}

public enum SubmissionError: Error, Sendable, Equatable {
    case sessionLocked
    case serverValidation([String])
    /// The page doesn't look like the adapter says (unknown page, missing field or option, new required field).
    case formChanged(FormDrift)
    case uploadFailed(String)
    case http(Int)
    case transport(String)
    /// The adapter itself is unusable (bad channel kind, URL or page list), independent of the live page.
    case invalidSpec(String)
    /// The final confirmation was sent but no receipt was read (timeout, dropped connection, unknown page).
    /// The case may or may not exist; never retry automatically, it could file a duplicate.
    case uncertain(String)

    /// True only when nothing reached the municipality as a case: a network or HTTP failure before the
    /// final confirmation was sent. Everything else needs a person (or a new adapter) first.
    public var isRetrySafe: Bool {
        switch self {
        case .transport, .http: true
        case .sessionLocked, .serverValidation, .formChanged, .uploadFailed, .invalidSpec, .uncertain: false
        }
    }
}

/// Per-request timeouts, kept in one place. Mobile networks stall; a page should never hang a send
/// for minutes, but a photo upload over a weak connection legitimately takes longer.
public enum SubmissionTimeouts {
    /// GET and form POST of one e-service page.
    public static let page: TimeInterval = 30
    /// Multipart photo upload.
    public static let upload: TimeInterval = 120
}

public enum SubmissionStage: Sendable, Equatable {
    case starting, uploadingPhoto, sendingReport, sendingContact, confirming, done
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-backed transport. Follows redirects; keeps cookies only in its own session.
public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    /// Ephemeral configuration (private cookie jar, no disk cache). Each request carries its own
    /// timeout from `SubmissionTimeouts`; the session only bounds a whole resource.
    public static func ephemeral() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = SubmissionTimeouts.upload
        configuration.timeoutIntervalForResource = SubmissionTimeouts.upload * 2
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    /// Drops every cookie so the next request starts a fresh server session.
    public func clearCookies() {
        guard let storage = session.configuration.httpCookieStorage else { return }
        for cookie in storage.cookies ?? [] {
            storage.deleteCookie(cookie)
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SubmissionError.transport("Not an HTTP response")
        }
        return (data, http)
    }
}
