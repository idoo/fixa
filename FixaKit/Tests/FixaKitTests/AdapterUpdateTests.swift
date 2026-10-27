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
        let file = try AdapterStatus.decodeMap(Data(contentsOf: repoRoot.appendingPathComponent("adapters/status.json")))
        XCTAssertEqual(file["se.varmdo.ksb"], .ok)

        let degraded = Data(#"""
        {"se.varmdo.ksb": {"state": "degraded", "updated": "2026-10-27T06:20:00Z",
          "message": {"en": "The e-service changed.", "sv": "E-tjänsten har ändrats."}}}
        """#.utf8)
        let status = try XCTUnwrap(AdapterStatus.decodeMap(degraded)["se.varmdo.ksb"])
        XCTAssertEqual(status.state, .degraded)
        XCTAssertEqual(status.message?.resolve(Locale(identifier: "sv_SE")), "E-tjänsten har ändrats.")
        XCTAssertEqual(status.updated, Date(timeIntervalSince1970: 1_793_082_000))

        XCTAssertThrowsError(try AdapterStatus.decodeMap(Data(#"{"x": {"state": "broken"}}"#.utf8)))
    }

    func testAcceptPolicy() throws {
        let bundled = try varmdoSpec()
        var json = try varmdoJSON()
        json["minAppBuild"] = 5

        XCTAssertNotNil(AdapterUpdatePolicy.accept(remote: try data(json), bundled: bundled, appBuild: 5))
        XCTAssertNil(AdapterUpdatePolicy.accept(remote: try data(json), bundled: bundled, appBuild: 4), "build too old")

        json.removeValue(forKey: "minAppBuild")
        XCTAssertNotNil(AdapterUpdatePolicy.accept(remote: try data(json), bundled: bundled, appBuild: 1), "no minAppBuild")

        var newer = json
        newer["specVersion"] = AdapterUpdatePolicy.supportedSpecVersion + 1
        XCTAssertNil(AdapterUpdatePolicy.accept(remote: try data(newer), bundled: bundled, appBuild: 99), "newer spec")

        var other = json
        other["id"] = "se.other.ksb"
        XCTAssertNil(AdapterUpdatePolicy.accept(remote: try data(other), bundled: bundled, appBuild: 99), "other id")

        var invalid = json
        invalid["categories"] = [Any]()
        XCTAssertNil(AdapterUpdatePolicy.accept(remote: try data(invalid), bundled: bundled, appBuild: 99), "fails checks")

        XCTAssertNil(AdapterUpdatePolicy.accept(remote: Data("<html>404</html>".utf8), bundled: bundled, appBuild: 99), "garbage")
    }
}
