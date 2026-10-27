import XCTest
@testable import FixaKit

final class AdapterUpdateTests: XCTestCase {
    private func varmdoJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func testDecodesWithAndWithoutMinAppBuild() throws {
        var json = try varmdoJSON()
        json["minAppBuild"] = 7
        let with = try AdapterCatalog.decode(data(json))
        XCTAssertEqual(with.specVersion, 1)
        XCTAssertEqual(with.minAppBuild, 7)

        json.removeValue(forKey: "minAppBuild")
        XCTAssertNil(try AdapterCatalog.decode(data(json)).minAppBuild)

        json.removeValue(forKey: "specVersion")
        XCTAssertThrowsError(try AdapterCatalog.decode(data(json)))
    }

    func testBundledAdapterHasNoProblems() throws {
        XCTAssertEqual(try varmdoSpec().problems, [])
    }

    func testProblemsRejectBrokenAdapter() throws {
        var json = try varmdoJSON()
        var tiles = try XCTUnwrap(json["tiles"] as? [[String: Any]])
        tiles[0]["categoryID"] = "nope"
        json["tiles"] = tiles
        XCTAssertThrowsError(try AdapterCatalog.decode(data(json))) { error in
            guard case AdapterSpecError.invalid(let problems) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(problems.contains { $0.contains("unknown category nope") }, "\(problems)")
        }
    }

    func testStatusDecoding() throws {
        let url = repoRoot.appendingPathComponent("adapters/status.json")
        let file = try AdapterStatus.decodeMap(Data(contentsOf: url), signature: Data(contentsOf: url.appendingPathExtension("sig")))
        XCTAssertEqual(file["se.varmdo.ksb"], .ok)

        // Free text in the file is ignored: only the state reaches the app, which words it itself.
        let degraded = Data(#"""
        {"se.varmdo.ksb": {"state": "degraded", "updated": "2026-10-27T06:20:00Z",
          "message": {"en": "Call 0900-SCAM now.", "sv": "Ring 0900-SCAM nu."}}}
        """#.utf8)
        let status = try XCTUnwrap(AdapterStatus.decodeUnverifiedMap(degraded)["se.varmdo.ksb"])
        XCTAssertEqual(status, AdapterStatus(state: .degraded, updated: Date(timeIntervalSince1970: 1_793_082_000)))

        XCTAssertThrowsError(try AdapterStatus.decodeUnverifiedMap(Data(#"{"x": {"state": "broken"}}"#.utf8)))
    }

    func testAcceptPolicy() throws {
        let bundled = try varmdoSpec()
        var json = try varmdoJSON()
        json["minAppBuild"] = 5

        XCTAssertNotNil(try? AdapterUpdatePolicy.validate(remote: try data(json), bundled: bundled, appBuild: 5))
        XCTAssertNil(try? AdapterUpdatePolicy.validate(remote: try data(json), bundled: bundled, appBuild: 4), "build too old")

        json.removeValue(forKey: "minAppBuild")
        XCTAssertNotNil(try? AdapterUpdatePolicy.validate(remote: try data(json), bundled: bundled, appBuild: 1), "no minAppBuild")

        var newer = json
        newer["specVersion"] = AdapterUpdatePolicy.supportedSpecVersion + 1
        XCTAssertNil(try? AdapterUpdatePolicy.validate(remote: try data(newer), bundled: bundled, appBuild: 99), "newer spec")

        var other = json
        other["id"] = "se.other.ksb"
        XCTAssertNil(try? AdapterUpdatePolicy.validate(remote: try data(other), bundled: bundled, appBuild: 99), "other id")

        var invalid = json
        invalid["categories"] = [Any]()
        XCTAssertNil(try? AdapterUpdatePolicy.validate(remote: try data(invalid), bundled: bundled, appBuild: 99), "fails checks")

        XCTAssertNil(try? AdapterUpdatePolicy.validate(remote: Data("<html>404</html>".utf8), bundled: bundled, appBuild: 99), "garbage")
    }
}
