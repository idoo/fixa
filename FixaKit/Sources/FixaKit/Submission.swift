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

public enum SubmissionError: Error, Sendable, Equatable {
    case sessionLocked
    case serverValidation([String])
    case unexpectedPage(String)
    case uploadFailed(String)
    case http(Int)
    case transport(String)
    case invalidSpec(String)
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

    /// Ephemeral configuration (private cookie jar, no disk cache), 30 s timeout.
    public static func ephemeral() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
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
