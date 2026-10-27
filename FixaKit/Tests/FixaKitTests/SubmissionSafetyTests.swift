import Foundation
import XCTest
@testable import FixaKit

/// FakeAbou with injected faults: answers chosen requests with an error, a different page or garbage.
actor ScriptedAbou: HTTPTransport {
    enum Fault {
        case timeout
        case status(Int)
        case statusWithHeaders(Int, [String: String])
        case html(String, at: String)
    }

    struct Rule {
        let method: String
        let urlContains: String
        /// Which matching request (1-based) to fault; 0 faults every match.
        let occurrence: Int
        let fault: Fault
    }

    let inner: FakeAbou
    let rules: [Rule]
    private var seen: [Int: Int] = [:]
    private(set) var requests: [URLRequest] = []

    init(mode: FakeAbou.Mode = .normal, _ rules: [Rule]) {
        self.inner = FakeAbou(mode: mode)
        self.rules = rules
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!.absoluteString
        for (i, rule) in rules.enumerated() where rule.method == request.httpMethod && url.contains(rule.urlContains) {
            seen[i, default: 0] += 1
            guard rule.occurrence == 0 || rule.occurrence == seen[i] else { continue }
            switch rule.fault {
            case .timeout:
                throw URLError(.timedOut)
            case .status(let code):
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
            case .statusWithHeaders(let code, let headers):
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!)
            case .html(let html, let at):
                return (Data(html.utf8), HTTPURLResponse(url: URL(string: at)!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        return try await inner.send(request)
    }

    func count(_ method: String, _ marker: String) -> Int {
        requests.filter { $0.httpMethod == method && $0.url!.absoluteString.contains(marker) }.count
    }
}

private let common = "\(base)/EServices/Common/"

final class SubmissionSafetyTests: XCTestCase {
    func submit(_ fake: ScriptedAbou, dryRun: Bool = false) async throws -> SubmissionReceipt? {
        try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(validDraft(), dryRun: dryRun)
    }

    func expectError(_ fake: ScriptedAbou, dryRun: Bool = false, file: StaticString = #filePath, line: UInt = #line) async throws -> SubmissionError {
        do {
            _ = try await submit(fake, dryRun: dryRun)
        } catch let error as SubmissionError {
            return error
        }
        XCTFail("expected a SubmissionError", file: file, line: line)
        return .invalidSpec("")
    }

    // MARK: - Before / after the final send

    func testTimeoutBeforeFinalSendIsRetrySafe() async throws {
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=PersonalEmailInformation", occurrence: 1, fault: .timeout)])
        let error = try await expectError(fake)
        guard case .transport = error else { return XCTFail("expected .transport, got \(error)") }
        XCTAssertTrue(error.isRetrySafe)
        let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
        XCTAssertEqual(summaryPosts, 0)
    }

    func testHTTPErrorBeforeFinalSendIsRetrySafe() async throws {
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=FaultReport", occurrence: 1, fault: .status(503))])
        let error = try await expectError(fake)
        XCTAssertEqual(error, .unavailable(status: 503, retryAfter: nil))
        XCTAssertTrue(error.isRetrySafe)
    }

    func testTimeoutOnFinalSendIsUncertain() async throws {
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=SummaryPage", occurrence: 0, fault: .timeout)])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
        XCTAssertFalse(error.isRetrySafe)
        let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
        XCTAssertEqual(summaryPosts, 1, "the final confirmation must never be sent twice")
        let setups = await fake.count("GET", "Setup.aspx")
        XCTAssertEqual(setups, 1, "no session restart after the final send")
    }

    func testServerErrorOnFinalSendIsUncertain() async throws {
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=SummaryPage", occurrence: 0, fault: .status(500))])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
    }

    func testGarbageAfterFinalSendIsUncertain() async throws {
        let fake = ScriptedAbou([.init(
            method: "POST", urlContains: "PageId=SummaryPage", occurrence: 0,
            fault: .html("<html><body>Service Unavailable</body></html>", at: "\(common)Receipt.aspx?eServiceName=KSB")
        )])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
        XCTAssertFalse(error.isRetrySafe)
    }

    func testTimeoutDuringCompletionPostBackIsUncertain() async throws {
        let fake = ScriptedAbou(mode: .thankYou, [.init(method: "POST", urlContains: "ThankYou.aspx", occurrence: 0, fault: .timeout)])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
        let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
        XCTAssertEqual(summaryPosts, 1)
    }

    func testSessionLockAfterFinalSendIsUncertainWithoutRestart() async throws {
        let fake = ScriptedAbou([.init(
            method: "POST", urlContains: "PageId=SummaryPage", occurrence: 0,
            fault: .html(try fixture("06-session-lock"), at: "\(base)/Setup.aspx?Service=KSB&skipintro=true")
        )])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
        let setups = await fake.count("GET", "Setup.aspx")
        XCTAssertEqual(setups, 1)
        let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
        XCTAssertEqual(summaryPosts, 1)
    }

    // MARK: - Session restart before the final send

    func testSessionLockAtStartRestartsOnce() async throws {
        let fake = ScriptedAbou([.init(
            method: "GET", urlContains: "Setup.aspx", occurrence: 1,
            fault: .html(try fixture("06-session-lock"), at: "\(base)/Setup.aspx?Service=KSB&skipintro=true")
        )])
        let receipt = try await submit(fake)
        XCTAssertEqual(receipt?.caseNumber, "KSB-123456")
        let intros = await fake.count("GET", "/KSB")
        XCTAssertEqual(intros, 2, "restart begins again at introPath")
        let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
        XCTAssertEqual(summaryPosts, 1)
    }

    func testExpiredSessionMidFormRestartsOnce() async throws {
        let fake = ScriptedAbou([.init(
            method: "POST", urlContains: "PageId=FaultReport", occurrence: 1,
            fault: .html(try fixture("07-after-cancel"), at: "\(base)/Errors/GenericError.aspx?errorType=0")
        )])
        let log = StageLog()
        let receipt = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(validDraft()) { log.append($0) }
        XCTAssertEqual(receipt?.caseNumber, "KSB-123456")
        XCTAssertEqual(log.stages.last, .done)
        let setups = await fake.count("GET", "Setup.aspx")
        XCTAssertEqual(setups, 2)
        let faultPosts = await fake.count("POST", "PageId=FaultReport")
        XCTAssertEqual(faultPosts, 2)
    }

    func testDryRunAlsoRestartsOnLock() async throws {
        let fake = ScriptedAbou([.init(
            method: "POST", urlContains: "PageId=PersonalEmailInformation", occurrence: 1,
            fault: .html(try fixture("06-session-lock"), at: "\(base)/Setup.aspx?Service=KSB&skipintro=true")
        )])
        let receipt = try await submit(fake, dryRun: true)
        XCTAssertNil(receipt)
        let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
        XCTAssertEqual(summaryPosts, 0)
        let setups = await fake.count("GET", "Setup.aspx")
        XCTAssertEqual(setups, 2)
    }

    func testPersistentLockRestartsOnlyOnce() async throws {
        let fake = ScriptedAbou(mode: .locked, [])
        let error = try await expectError(fake, dryRun: true)
        XCTAssertEqual(error, .sessionLocked)
        XCTAssertFalse(error.isRetrySafe)
        let setups = await fake.count("GET", "Setup.aspx")
        XCTAssertEqual(setups, 2)
    }

    func testPersistentExpiryIsRetrySafeTransport() async throws {
        let fake = ScriptedAbou([.init(
            method: "POST", urlContains: "PageId=FaultReport", occurrence: 0,
            fault: .html(try fixture("07-after-cancel"), at: "\(base)/Errors/GenericError.aspx?errorType=0")
        )])
        let error = try await expectError(fake)
        guard case .transport = error else { return XCTFail("expected .transport, got \(error)") }
        XCTAssertTrue(error.isRetrySafe)
        let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
        XCTAssertEqual(summaryPosts, 0)
    }

    // MARK: - Contract

    func testIsRetrySafe() {
        XCTAssertTrue(SubmissionError.transport("x").isRetrySafe)
        XCTAssertTrue(SubmissionError.http(400).isRetrySafe)
        XCTAssertTrue(SubmissionError.unavailable(status: 429, retryAfter: 30).isRetrySafe)
        XCTAssertEqual(SubmissionError.unavailable(status: nil, retryAfter: 30).retryAfter, 30)
        XCTAssertNil(SubmissionError.http(500).retryAfter)
        XCTAssertFalse(SubmissionError.uncertain("x").isRetrySafe)
        XCTAssertFalse(SubmissionError.formChanged(FormDrift(pageID: nil, missing: [], detail: "")).isRetrySafe)
        XCTAssertFalse(SubmissionError.invalidSpec("x").isRetrySafe)
        XCTAssertFalse(SubmissionError.sessionLocked.isRetrySafe)
        XCTAssertFalse(SubmissionError.serverValidation([]).isRetrySafe)
        XCTAssertFalse(SubmissionError.uploadFailed("x").isRetrySafe)
        XCTAssertFalse(SubmissionError.blocked(status: 403).isRetrySafe)
        XCTAssertFalse(SubmissionError.loginRequired.isRetrySafe)
    }

    // MARK: - Blocked, sign-in, moved

    func testForbiddenAndUnauthorizedAreBlocked() async throws {
        for code in [401, 403] {
            for (method, marker) in [("GET", "Setup.aspx"), ("POST", "PageId=FaultReport"), ("POST", "PageId=PersonalEmailInformation")] {
                let fake = ScriptedAbou([.init(method: method, urlContains: marker, occurrence: 0, fault: .status(code))])
                let error = try await expectError(fake)
                XCTAssertEqual(error, .blocked(status: code), "\(code) \(marker)")
                XCTAssertFalse(error.isRetrySafe)
                let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
                XCTAssertEqual(summaryPosts, 0)
                let setups = await fake.count("GET", "Setup.aspx")
                XCTAssertEqual(setups, 1, "a block never restarts the session")
            }
        }
    }

    func testForbiddenAfterFinalSendIsUncertain() async throws {
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=SummaryPage", occurrence: 0, fault: .status(403))])
        let error = try await expectError(fake)
        guard case .uncertain = error else { return XCTFail("expected .uncertain, got \(error)") }
    }

    func testNotFoundOrGoneIsFormChanged() async throws {
        for code in [404, 410] {
            for (method, marker) in [("GET", "/KSB"), ("GET", "Setup.aspx"), ("POST", "PageId=FaultReport")] {
                let fake = ScriptedAbou([.init(method: method, urlContains: marker, occurrence: 0, fault: .status(code))])
                let error = try await expectError(fake)
                guard case .formChanged(let drift) = error else { XCTFail("expected .formChanged for \(code) \(marker), got \(error)"); continue }
                XCTAssertTrue(drift.detail.contains("\(code)"), drift.detail)
                XCTAssertFalse(error.isRetrySafe)
            }
        }
        // Any other client error stays a plain retry-safe HTTP error.
        let fake = ScriptedAbou([.init(method: "POST", urlContains: "PageId=FaultReport", occurrence: 0, fault: .status(400))])
        let error = try await expectError(fake)
        XCTAssertEqual(error, .http(400))
    }

    func testBankIDPageBeforeFinalSendIsLoginRequired() async throws {
        let html = """
        <html><head><title>Logga in med BankID</title></head><body><form method="post" action="./Identification.aspx" id="MainForm">
        <input type="hidden" name="__VIEWSTATE" value="x" /><h1>Legitimera dig med e-legitimation</h1></form></body></html>
        """
        for (method, marker) in [("GET", "Setup.aspx"), ("POST", "PageId=FaultReport")] {
            let fake = ScriptedAbou([.init(method: method, urlContains: marker, occurrence: 0,
                                           fault: .html(html, at: "\(base)/EServices/Common/Identification.aspx?eServiceName=KSB"))])
            let error = try await expectError(fake)
            XCTAssertEqual(error, .loginRequired, marker)
            XCTAssertFalse(error.isRetrySafe)
            let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
            XCTAssertEqual(summaryPosts, 0)
        }
    }

    // MARK: - Final-send hook

    func testBeforeFinalSendRunsOnceRightBeforeSlutfor() async throws {
        let fake = ScriptedAbou([])
        let marks = HookLog()
        let receipt = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero)
            .submit(validDraft(), beforeFinalSend: {
                let summaryPosts = await fake.count("POST", "PageId=SummaryPage")
                let total = await fake.requests.count
                marks.append(summaryPosts, total)
            })
        XCTAssertEqual(receipt?.caseNumber, "KSB-123456")
        let requests = await fake.requests
        XCTAssertEqual(marks.entries.count, 1)
        XCTAssertEqual(marks.entries.first?.summaryPosts, 0, "awaited before the final request is sent")
        let finalIndex = try XCTUnwrap(requests.firstIndex { $0.url!.absoluteString.contains("PageId=SummaryPage") })
        XCTAssertEqual(marks.entries.first?.requestsSoFar, finalIndex, "nothing is sent between the hook and Slutför")
    }

    func testBeforeFinalSendNotCalledOnDryRunOrEarlyFailure() async throws {
        let marks = HookLog()
        _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: ScriptedAbou([]), pageDelay: .zero)
            .submit(validDraft(), dryRun: true, beforeFinalSend: { marks.append(0, 0) })
        let failing = ScriptedAbou([.init(method: "POST", urlContains: "PageId=PersonalEmailInformation", occurrence: 0, fault: .status(503))])
        do {
            _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: failing, pageDelay: .zero)
                .submit(validDraft(), beforeFinalSend: { marks.append(0, 0) })
            XCTFail("expected an error")
        } catch {}
        XCTAssertTrue(marks.entries.isEmpty)
    }

    // MARK: - Orphan uploads

    func testChangedPageIsFoundBeforeThePhotoIsUploaded() async throws {
        let fake = MutatedAbou(fault: { $0.replacingOccurrences(of: descriptionAnchor, with: newRequiredBlock + descriptionAnchor) })
        var draft = validDraft()
        draft.photoJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])
        do {
            _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(draft)
            XCTFail("expected .formChanged")
        } catch SubmissionError.formChanged(let drift) {
            XCTAssertEqual(drift.missing, ["Fastighetsbeteckning"])
        }
        let requests = await fake.requests
        XCTAssertFalse(requests.contains { $0.url!.path.hasPrefix("/Citizen/Field/") }, "no photo uploaded for a page that doesn't match")
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 0)
    }

    func testMatchingPageUploadsThePhotoBeforePosting() async throws {
        let fake = ScriptedAbou([])
        var draft = validDraft()
        draft.photoJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])
        _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(draft, dryRun: true)
        let requests = await fake.requests
        let upload = try XCTUnwrap(requests.firstIndex { $0.url!.path.hasPrefix("/Citizen/Field/UploadFile") })
        let report = try XCTUnwrap(requests.firstIndex { $0.httpMethod == "POST" && $0.url!.absoluteString.contains("PageId=FaultReport") })
        XCTAssertLessThan(upload, report)
    }

    // MARK: - Headers like Safari's

    func testPostsCarryOriginAndReferer() async throws {
        let fake = ScriptedAbou([])
        var draft = validDraft()
        draft.photoJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])
        _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(draft)
        let requests = await fake.requests
        let posts = requests.filter { $0.httpMethod == "POST" }
        XCTAssertGreaterThanOrEqual(posts.count, 5)
        for post in posts {
            XCTAssertEqual(post.value(forHTTPHeaderField: "Origin"), base, post.url!.absoluteString)
            let referer = try XCTUnwrap(post.value(forHTTPHeaderField: "Referer"), post.url!.absoluteString)
            XCTAssertTrue(referer.hasPrefix(base + "/"), referer)
        }
        let report = try XCTUnwrap(posts.first { $0.url!.absoluteString.contains("PageId=FaultReport") })
        XCTAssertEqual(report.value(forHTTPHeaderField: "Referer"), faultURL.absoluteString, "the page the form came from")
        let upload = try XCTUnwrap(posts.first { $0.url!.path.hasPrefix("/Citizen/Field/UploadFile") })
        XCTAssertEqual(upload.value(forHTTPHeaderField: "Referer"), faultURL.absoluteString)
        let setup = try XCTUnwrap(requests.first { $0.httpMethod == "GET" && $0.url!.absoluteString.contains("Setup.aspx") })
        XCTAssertEqual(setup.value(forHTTPHeaderField: "Referer"), "\(base)/KSB")
    }

    func testRequestTimeouts() async throws {
        let fake = ScriptedAbou([])
        var draft = validDraft()
        draft.photoJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])
        _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(draft, dryRun: true)
        let requests = await fake.requests
        let upload = try XCTUnwrap(requests.first { $0.url!.path.hasPrefix("/Citizen/Field/UploadFile") })
        XCTAssertEqual(upload.timeoutInterval, SubmissionTimeouts.upload)
        for request in requests where request != upload {
            XCTAssertEqual(request.timeoutInterval, SubmissionTimeouts.page, request.url!.absoluteString)
        }
    }

    func testGarbageIsNotAReceipt() {
        let url = URL(string: "\(common)Receipt.aspx?eServiceName=KSB")!
        XCTAssertNil(AbouPageParser.parseReceipt(html: "<html><body>Service Unavailable</body></html>", url: url, now: Date()))
        XCTAssertNil(AbouPageParser.parseReceipt(html: "", url: url, now: Date()))
        XCTAssertNil(AbouPageParser.parseReceipt(html: "<html><title>Stack trace</title><body>Attack detected</body></html>", url: url, now: Date()))
        XCTAssertNotNil(AbouPageParser.parseReceipt(html: "<p>Vi har tagit emot ditt ärende.</p>", url: url, now: Date()))
    }
}

final class HookLog: @unchecked Sendable {
    struct Entry { let summaryPosts: Int; let requestsSoFar: Int }
    private let lock = NSLock()
    private var items: [Entry] = []
    func append(_ summaryPosts: Int, _ requestsSoFar: Int) { lock.withLock { items.append(Entry(summaryPosts: summaryPosts, requestsSoFar: requestsSoFar)) } }
    var entries: [Entry] { lock.withLock { items } }
}
