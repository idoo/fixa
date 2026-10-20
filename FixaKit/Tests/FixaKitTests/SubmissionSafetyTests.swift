import Foundation
import XCTest
@testable import FixaKit

/// FakeAbou with injected faults: answers chosen requests with an error, a different page or garbage.
actor ScriptedAbou: HTTPTransport {
    enum Fault {
        case timeout
        case status(Int)
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
        try await AbouSubmitter(spec: try varmdoSpec(), transport: fake).submit(validDraft(), dryRun: dryRun)
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
        XCTAssertEqual(error, .http(503))
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
        let receipt = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake).submit(validDraft()) { log.append($0) }
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
        XCTAssertTrue(SubmissionError.http(502).isRetrySafe)
        XCTAssertFalse(SubmissionError.uncertain("x").isRetrySafe)
        XCTAssertFalse(SubmissionError.formChanged(FormDrift(pageID: nil, missing: [], detail: "")).isRetrySafe)
        XCTAssertFalse(SubmissionError.invalidSpec("x").isRetrySafe)
        XCTAssertFalse(SubmissionError.sessionLocked.isRetrySafe)
        XCTAssertFalse(SubmissionError.serverValidation([]).isRetrySafe)
        XCTAssertFalse(SubmissionError.uploadFailed("x").isRetrySafe)
    }

    func testRequestTimeouts() async throws {
        let fake = ScriptedAbou([])
        var draft = validDraft()
        draft.photoJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])
        _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake).submit(draft, dryRun: true)
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
