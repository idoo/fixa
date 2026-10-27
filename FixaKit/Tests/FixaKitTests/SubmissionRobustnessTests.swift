import Foundation
import XCTest
@testable import FixaKit

private let common = "\(base)/EServices/Common/"
private let summaryURL = "\(common)Summary.aspx?eServiceName=KSB&PageId=SummaryPage"
private let contactURL = "\(common)BlockPage.aspx?eServiceName=KSB&PageId=PersonalEmailInformation"

/// HTTP policy: what is retry-safe before the final send, what is `.uncertain` after it, and that the
/// final confirmation is never sent twice.
final class SubmissionRobustnessTests: XCTestCase {
    func submit(_ fake: ScriptedAbou, delay: Duration = .zero) async throws -> SubmissionReceipt? {
        try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: delay).submit(validDraft())
    }

    func expectError(_ fake: ScriptedAbou, file: StaticString = #filePath, line: UInt = #line) async throws -> SubmissionError {
        do {
            _ = try await submit(fake)
        } catch let error as SubmissionError {
            return error
        }
        XCTFail("expected a SubmissionError", file: file, line: line)
        return .invalidSpec("")
    }

    func finalPosts(_ fake: ScriptedAbou) async -> Int {
        await fake.count("POST", "PageId=SummaryPage")
    }

    // MARK: - Before the final send: retry-safe, with Retry-After

    func test429WithRetryAfterSecondsIsRetrySafe() async throws {
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=FaultReport", occurrence: 1,
                                       fault: .statusWithHeaders(429, ["Retry-After": "120"]))])
        let error = try await expectError(fake)
        XCTAssertEqual(error, .unavailable(status: 429, retryAfter: 120))
        XCTAssertTrue(error.isRetrySafe)
        XCTAssertEqual(error.retryAfter, 120)
        let posts = await finalPosts(fake)
        XCTAssertEqual(posts, 0)
    }

    func test503WithRetryAfterDateIsRetrySafe() async throws {
        let date = Date().addingTimeInterval(600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let fake = ScriptedAbou([.init(method: "GET", urlContains: "Setup.aspx", occurrence: 1,
                                       fault: .statusWithHeaders(503, ["Retry-After": formatter.string(from: date)]))])
        let error = try await expectError(fake)
        guard case .unavailable(503, let retryAfter?) = error else { return XCTFail("expected .unavailable(503, _), got \(error)") }
        XCTAssertEqual(retryAfter, 600, accuracy: 5)
        XCTAssertTrue(error.isRetrySafe)
    }

    func testAny5xxBeforeFinalSendIsRetrySafe() async throws {
        for code in [500, 502, 504] {
            let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=PersonalEmailInformation", occurrence: 1, fault: .status(code))])
            let error = try await expectError(fake)
            XCTAssertEqual(error, .unavailable(status: code, retryAfter: nil))
            XCTAssertTrue(error.isRetrySafe)
            let posts = await finalPosts(fake)
            XCTAssertEqual(posts, 0)
        }
    }

    func testRetryAfterParsing() {
        let now = Date(timeIntervalSince1970: 1_793_088_900) // Tue, 27 Oct 2026 08:15:00 GMT
        XCTAssertEqual(AbouSubmitter.retryAfter("120", now: now), 120)
        XCTAssertEqual(AbouSubmitter.retryAfter(" 30 ", now: now), 30)
        XCTAssertEqual(AbouSubmitter.retryAfter("Tue, 27 Oct 2026 08:17:00 GMT", now: now), 120)
        XCTAssertEqual(AbouSubmitter.retryAfter("Tue, 27 Oct 2026 08:00:00 GMT", now: now), 0)
        XCTAssertEqual(AbouSubmitter.retryAfter("-5", now: now), 0)
        XCTAssertEqual(AbouSubmitter.retryAfter("9999999", now: now), 24 * 60 * 60)
        XCTAssertNil(AbouSubmitter.retryAfter("soon", now: now))
        XCTAssertNil(AbouSubmitter.retryAfter(nil, now: now))
    }

    // MARK: - Pages served with 200 that are not what they seem

    func testMaintenancePageBeforeFinalSendIsRetrySafe() async throws {
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=FaultReport", occurrence: 1,
                                       fault: .html("<html><title>Service Unavailable</title><body>The server is temporarily unavailable.</body></html>", at: contactURL))])
        let error = try await expectError(fake)
        XCTAssertEqual(error, .unavailable(status: nil, retryAfter: nil))
        XCTAssertTrue(error.isRetrySafe)
        let posts = await finalPosts(fake)
        XCTAssertEqual(posts, 0)
    }

    func testMaintenancePageAfterFinalSendIsNeverAReceipt() async throws {
        // "Tack" would otherwise read as received-wording.
        let html = "<html><head><title>Tack för ditt tålamod</title></head><body><p>Planerat underhåll pågår. Tack!</p></body></html>"
        XCTAssertNotNil(AbouPageParser.parseReceipt(html: html, url: URL(string: "\(common)Receipt.aspx")!, now: Date()),
                        "precondition: the parser alone would take this for a receipt")
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=SummaryPage", occurrence: 0,
                                       fault: .html(html, at: "\(common)Receipt.aspx?eServiceName=KSB"))])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
        XCTAssertFalse(error.isRetrySafe)
        let posts = await finalPosts(fake)
        XCTAssertEqual(posts, 1)
    }

    func testLoginPageAfterFinalSendIsUncertain() async throws {
        let html = "<html><title>Logga in</title><body><p>Tack för att du använder e-tjänsterna.</p><form action=\"/web/login.aspx\"><input type=\"password\" name=\"pw\"></form></body></html>"
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=SummaryPage", occurrence: 0,
                                       fault: .html(html, at: "\(base)/web/login.aspx?RedirectPage=x"))])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
        let posts = await finalPosts(fake)
        XCTAssertEqual(posts, 1)
    }

    func testLoginPageBeforeFinalSendIsNotRetried() async throws {
        let html = "<html><body><form method=\"post\" action=\"./login.aspx\"><input type=\"hidden\" name=\"__VIEWSTATE\" value=\"x\" /><input type=\"password\" name=\"pw\"></form></body></html>"
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=FaultReport", occurrence: 1,
                                       fault: .html(html, at: "\(base)/web/login.aspx?RedirectPage=x"))])
        let error = try await expectError(fake)
        guard case .formChanged = error else { return XCTFail("expected .formChanged, got \(error)") }
        XCTAssertFalse(error.isRetrySafe)
        let posts = await finalPosts(fake)
        XCTAssertEqual(posts, 0)
    }

    func testRealFormPagesAreNotOutageOrLogin() throws {
        for name in ["01-intro", "02-faultreport", "03-faultreport-validation", "04-contact", "05-summary", "06-session-lock",
                     "07-after-cancel", "08-thankyou-processing", "09-thankyou-receipt"] {
            let html = try fixture(name)
            XCTAssertFalse(AbouSubmitter.isOutagePage(html), name)
            XCTAssertFalse(AbouSubmitter.isLoginPage(.init(html: html, url: faultURL)), name)
        }
    }

    // MARK: - Redirects and hosts

    func testRedirectOffHostBeforeFinalSendIsAnError() async throws {
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=FaultReport", occurrence: 1,
                                       fault: .statusWithHeaders(302, ["Location": "https://evil.example.com/KSB"]))])
        let error = try await expectError(fake)
        guard case .transport = error else { return XCTFail("expected .transport, got \(error)") }
        let requests = await fake.requests
        XCTAssertFalse(requests.contains { $0.url?.host != "service.varmdo.se" })
        let posts = await finalPosts(fake)
        XCTAssertEqual(posts, 0)
    }

    func testAnswerFromAnotherHostIsAnError() async throws {
        // A transport that followed a redirect: the page came from elsewhere.
        let fake = ScriptedAbou([.init(method: "GET", urlContains: "Setup.aspx", occurrence: 1,
                                       fault: .html(try fixture("02-faultreport"), at: "https://evil.example.com/EServices/Common/BlockPage.aspx?eServiceName=KSB&PageId=FaultReport"))])
        let error = try await expectError(fake)
        guard case .transport = error else { return XCTFail("expected .transport, got \(error)") }
        let requests = await fake.requests
        XCTAssertFalse(requests.contains { $0.url?.host != "service.varmdo.se" })
    }

    func testRedirectAfterFinalSendIsUncertain() async throws {
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=SummaryPage", occurrence: 0,
                                       fault: .statusWithHeaders(302, ["Location": "https://evil.example.com/"]))])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
        let posts = await finalPosts(fake)
        XCTAssertEqual(posts, 1)
    }

    func testFormPostingOffHostIsNeverSent() async throws {
        let hostile = try fixture("04-contact").replacingOccurrences(
            of: "action=\"./BlockPage.aspx?eServiceName=KSB&amp;PageId=PersonalEmailInformation\"",
            with: "action=\"https://evil.example.com/collect?PageId=PersonalEmailInformation\""
        )
        XCTAssertNotEqual(hostile, try fixture("04-contact"))
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=FaultReport", occurrence: 1, fault: .html(hostile, at: contactURL))])
        let error = try await expectError(fake)
        guard case .formChanged = error else { return XCTFail("expected .formChanged, got \(error)") }
        XCTAssertFalse(error.isRetrySafe)
        let requests = await fake.requests
        XCTAssertFalse(requests.contains { $0.url?.host != "service.varmdo.se" })
    }

    func testRedirectGuard() {
        let origin = URL(string: "https://service.varmdo.se/KSB")
        XCTAssertTrue(RedirectGuard.allows(from: origin, to: URL(string: "https://service.varmdo.se/Setup.aspx")))
        XCTAssertTrue(RedirectGuard.allows(from: origin, to: URL(string: "https://SERVICE.varmdo.se/x")))
        XCTAssertFalse(RedirectGuard.allows(from: origin, to: URL(string: "http://service.varmdo.se/x")))
        XCTAssertFalse(RedirectGuard.allows(from: origin, to: URL(string: "https://evil.example.com/x")))
        XCTAssertFalse(RedirectGuard.allows(from: origin, to: URL(string: "https://service.varmdo.se.evil.com/x")))
        XCTAssertFalse(RedirectGuard.allows(from: nil, to: URL(string: "https://service.varmdo.se/x")))
    }

    func testURLSessionTransportDoesNotFollowOffHostRedirect() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingProtocol.self]
        let transport = URLSessionTransport(session: URLSession(configuration: configuration))
        RedirectingProtocol.reset()
        let (_, response) = try await transport.send(URLRequest(url: URL(string: "https://service.varmdo.se/KSB")!))
        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(RedirectingProtocol.hosts(), ["service.varmdo.se"])
    }

    // MARK: - The final confirmation is sent once

    func testCompletionPostBackNeverTargetsTheFinalURL() async throws {
        let marker = try XCTUnwrap(try varmdoSpec().channel.completionPostBackMarker)
        let html = """
        <html><body><form method="post" action="./Summary.aspx?eServiceName=KSB&amp;PageId=SummaryPage" id="MainForm">
        <input type="hidden" name="__VIEWSTATE" value="x" /></form><p>\(marker)</p></body></html>
        """
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=SummaryPage", occurrence: 1,
                                       fault: .html(html, at: "\(common)ThankYou.aspx?eServiceName=KSB&PageId=ThankYou"))])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
        let posts = await finalPosts(fake)
        XCTAssertEqual(posts, 1, "the final confirmation must never be sent twice")
    }

    func testEveryFailureAfterTheFinalSendLeavesExactlyOneFinalPost() async throws {
        let faults: [ScriptedAbou.Fault] = [
            .timeout, .status(500), .status(429), .statusWithHeaders(503, ["Retry-After": "5"]),
            .statusWithHeaders(301, ["Location": "\(base)/KSB"]),
            .html(try fixture("05-summary"), at: summaryURL),
            .html(try fixture("07-after-cancel"), at: "\(base)/Errors/GenericError.aspx?errorType=0"),
        ]
        for fault in faults {
            let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=SummaryPage", occurrence: 0, fault: fault)])
            let error = try await expectError(fake)
            guard case .uncertain = error else { XCTFail("expected .uncertain for \(fault), got \(error)"); continue }
            let posts = await finalPosts(fake)
            XCTAssertEqual(posts, 1, "\(fault)")
            let setups = await fake.count("GET", "Setup.aspx")
            XCTAssertEqual(setups, 1, "no restart after the final send: \(fault)")
        }
    }

    // MARK: - Looks like the website

    func testRequestsLookLikeSafariAndNeverNameTheApp() async throws {
        let fake = ScriptedAbou([])
        var draft = validDraft()
        draft.photoJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])
        draft.translation = MachineTranslation(sourceLanguage: "uk", text: "Lampan lyser inte")
        draft.createdAt = Date().addingTimeInterval(-5 * 3600)
        let receipt = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(draft)
        XCTAssertNotNil(receipt)
        let requests = await fake.requests
        for request in requests {
            let name = request.url!.absoluteString
            XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")!.hasPrefix("Mozilla/5.0 (iPhone; CPU iPhone OS"), name)
            XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")!.contains("Safari/"), name)
            XCTAssertTrue(request.value(forHTTPHeaderField: "Accept-Language")!.hasPrefix("sv-SE"), name)
            for (field, value) in request.allHTTPHeaderFields ?? [:] {
                XCTAssertFalse(value.localizedCaseInsensitiveContains("fixa"), "\(name) \(field): \(value)")
            }
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let decoded = body.removingPercentEncoding ?? body
            XCTAssertFalse(decoded.localizedCaseInsensitiveContains("fixa"), name)
            XCTAssertFalse(decoded.localizedCaseInsensitiveContains("Skickad via"), name)
            XCTAssertFalse(decoded.localizedCaseInsensitiveContains("Maskinöversättning"), name)
        }
        let report = requests.first { $0.httpMethod == "POST" && $0.url!.absoluteString.contains("PageId=FaultReport") }!
        let posted = String(decoding: report.httpBody!, as: UTF8.self).replacingOccurrences(of: "+", with: " ").removingPercentEncoding!
        XCTAssertTrue(posted.contains("Översatt från ukrainska:\nLampan lyser inte\n\nUpptäckt: "), posted)
    }

    // MARK: - Politeness

    func testPausesBetweenRequests() async throws {
        let fake = ScriptedAbou([])
        let delay = Duration.milliseconds(60)
        let clock = ContinuousClock()
        let start = clock.now
        _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: delay).submit(validDraft(), dryRun: true)
        let elapsed = clock.now - start
        let requests = await fake.requests.count
        XCTAssertGreaterThan(requests, 2)
        XCTAssertGreaterThanOrEqual(elapsed, delay * (requests - 1))
    }
}

/// Answers service.varmdo.se with a 302 to another host and records every host it is asked for.
final class RedirectingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var seen: [String] = []
    private static let lock = NSLock()

    static func reset() { lock.withLock { seen = [] } }
    static func hosts() -> [String] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append(url.host ?? "") }
        if url.host == "service.varmdo.se" {
            let target = URL(string: "https://evil.example.com/steal")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("stolen".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
