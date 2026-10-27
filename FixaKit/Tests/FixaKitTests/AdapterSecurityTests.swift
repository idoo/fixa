import XCTest
@testable import FixaKit

/// A downloaded adapter may change how the form is filled, never where the user's data goes.
final class AdapterSecurityTests: XCTestCase {
    private func varmdoJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func changed(_ edit: (inout [String: Any]) throws -> Void) throws -> Data {
        var json = try varmdoJSON()
        try edit(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func changedChannel(_ key: String, _ value: Any) throws -> Data {
        try changed { json in
            var channel = try XCTUnwrap(json["channel"] as? [String: Any])
            channel[key] = value
            json["channel"] = channel
        }
    }

    private func changedUpload(_ key: String, _ value: Any) throws -> Data {
        try changed { json in
            var channel = try XCTUnwrap(json["channel"] as? [String: Any])
            var upload = try XCTUnwrap(channel["upload"] as? [String: Any])
            upload[key] = value
            channel["upload"] = upload
            json["channel"] = channel
        }
    }

    private func assertRejected(_ data: Data, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let bundled = try varmdoSpec()
        XCTAssertThrowsError(try AdapterUpdatePolicy.check(remote: data, bundled: bundled, appBuild: 99), message, file: file, line: line) { error in
            XCTAssertNotNil(error as? AdapterSpecError, "\(message): \(error)", file: file, line: line)
        }
        XCTAssertNil(AdapterUpdatePolicy.accept(remote: data, bundled: bundled, appBuild: 99), message, file: file, line: line)
    }

    func testBundledAdapterPassesPinning() throws {
        let bundled = try varmdoSpec()
        XCTAssertEqual(AdapterSpecValidator.pinningProblems(remote: bundled, bundled: bundled), [])
        XCTAssertNotNil(AdapterUpdatePolicy.accept(remote: try changed { _ in }, bundled: bundled, appBuild: 99))
    }

    func testBenignLabelChangeIsAccepted() throws {
        let data = try changed { json in
            var channel = try XCTUnwrap(json["channel"] as? [String: Any])
            var pages = try XCTUnwrap(channel["pages"] as? [[String: Any]])
            var fields = try XCTUnwrap(pages[0]["fields"] as? [[String: Any]])
            fields[0]["labels"] = ["sv": ["Välj kategori", "Kategori"], "en": ["Category"]]
            pages[0]["fields"] = fields
            channel["pages"] = pages
            json["channel"] = channel
            json["minAppBuild"] = 2
        }
        let spec = try AdapterUpdatePolicy.check(remote: data, bundled: try varmdoSpec(), appBuild: 4)
        XCTAssertEqual(spec.channel.pages[0].fields[0].labels?["en"], ["Category"])
    }

    func testDestinationChangesAreRejected() throws {
        try assertRejected(try changedChannel("baseURL", "https://evil.example.com"), "evil host")
        try assertRejected(try changedChannel("baseURL", "https://service.varmdo.se.evil.com"), "suffix host")
        try assertRejected(try changedChannel("baseURL", "http://service.varmdo.se"), "http")
        try assertRejected(try changedChannel("baseURL", "https://service.varmdo.se:8443"), "port")
        try assertRejected(try changedChannel("baseURL", "https://service.varmdo.se:443"), "explicit default port")
        try assertRejected(try changedChannel("baseURL", "https://user@service.varmdo.se"), "userinfo")
        try assertRejected(try changedChannel("baseURL", "https://service.varmdo.se/proxy"), "base path")
        try assertRejected(try changedChannel("service", "OTHER"), "changed service")
        try assertRejected(try changedChannel("kind", "email"), "changed kind")
        try assertRejected(try changed { $0["fallbackEmail"] = "harvest@evil.example.com" }, "changed fallback e-mail")
        try assertRejected(try changed { $0["id"] = "se.evil.ksb" }, "unknown id")
    }

    func testUnsafePathsAreRejected() throws {
        for path in ["https://evil.example.com/KSB", "//evil.example.com/KSB", "KSB", "/a//b", "/\\evil.example.com",
                     "/KSB?next=https://evil.example.com", "/K SB", "@evil.example.com/KSB"] {
            try assertRejected(try changedChannel("introPath", path), "introPath \(path)")
        }
        try assertRejected(try changedChannel("startPath", "javascript:alert(1)"), "startPath scheme")
        try assertRejected(try changedUpload("path", "https://evil.example.com/upload"), "upload path with scheme")
        try assertRejected(try changedUpload("actionPath", "//evil.example.com/Action"), "upload action protocol-relative")
        try assertRejected(try changedUpload("fileName", "foto.jpg\"\r\nX-Evil: 1"), "header injection in file name")
    }

    func testOversizedAdaptersAreRejected() throws {
        var padded = try changed { _ in }
        padded.append(Data(repeating: 0x20, count: AdapterSpecValidator.maxBytes))
        try assertRejected(padded, "over the byte limit")
        XCTAssertThrowsError(try AdapterSpecValidator.validateRemote(padded, bundled: [try varmdoSpec()])) { error in
            guard case AdapterSpecError.rejected(let problems) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(problems.contains { $0.contains("bytes") }, "\(problems)")
        }

        try assertRejected(try changed { json in
            var channel = try XCTUnwrap(json["channel"] as? [String: Any])
            let pages = try XCTUnwrap(channel["pages"] as? [[String: Any]])
            let summary = try XCTUnwrap(pages.last)
            channel["pages"] = Array(pages.dropLast()) + (0...AdapterSpecValidator.maxPages).map { i -> [String: Any] in
                var page = pages[0]
                page["id"] = "Page\(i)"
                return page
            } + [summary]
            json["channel"] = channel
        }, "too many pages")

        try assertRejected(try changedChannel("maxCompletionPostBacks", 10_000), "endless re-posts")
    }

    func testUnknownIDIsRejectedAgainstAllBundled() throws {
        let data = try changed { $0["id"] = "se.nowhere.ksb" }
        XCTAssertThrowsError(try AdapterSpecValidator.validateRemote(data, bundled: AdapterCatalog.bundled())) { error in
            XCTAssertEqual(error as? AdapterSpecError, .rejected(["unknown adapter id se.nowhere.ksb"]))
        }
    }
}
