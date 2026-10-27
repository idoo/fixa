import CryptoKit
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

    /// A throwaway signing key, so content rules are tested on correctly signed data.
    private let testKey = Curve25519.Signing.PrivateKey()
    private var testPublicKey: String { testKey.publicKey.rawRepresentation.base64EncodedString() }

    private func signature(_ data: Data, key: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
        Data(try (key ?? testKey).signature(for: data).base64EncodedString().utf8)
    }

    private func check(_ data: Data, appBuild: Int = 99) throws -> AdapterSpec {
        try AdapterUpdatePolicy.check(remote: data, signature: try signature(data), bundled: try varmdoSpec(),
                                      appBuild: appBuild, publicKey: testPublicKey)
    }

    private func assertRejected(_ data: Data, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let bundled = try varmdoSpec()
        XCTAssertThrowsError(try check(data), message, file: file, line: line) { error in
            XCTAssertNotNil(error as? AdapterSpecError, "\(message): \(error)", file: file, line: line)
        }
        XCTAssertNil(AdapterUpdatePolicy.accept(remote: data, signature: try signature(data), bundled: bundled,
                                                appBuild: 99, publicKey: testPublicKey), message, file: file, line: line)
    }

    private func assertSignatureRejected(_ data: Data, signature: Data?, publicKey: String,
                                         _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try AdapterUpdatePolicy.check(remote: data, signature: signature, bundled: try varmdoSpec(),
                                                           appBuild: 99, publicKey: publicKey), message, file: file, line: line) { error in
            XCTAssertEqual(error as? AdapterSpecError, .rejected(["adapter signature does not verify"]), message, file: file, line: line)
        }
    }

    func testBundledAdapterPassesPinning() throws {
        let bundled = try varmdoSpec()
        XCTAssertEqual(AdapterSpecValidator.pinningProblems(remote: bundled, bundled: bundled), [])
        XCTAssertNotNil(try? check(try changed { _ in }))
    }

    // MARK: - Signatures

    func testPublishedFilesVerifyAgainstEmbeddedKey() throws {
        for name in ["se-varmdo-ksb.json", "status.json"] {
            let url = repoRoot.appendingPathComponent("adapters/\(name)")
            let data = try Data(contentsOf: url)
            let sig = try Data(contentsOf: url.appendingPathExtension("sig"))
            XCTAssertTrue(AdapterSignature.verify(data, signature: sig), "\(name).sig does not match the embedded public key; run fixa-cli sign")
        }
        let url = repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json")
        let accepted = try AdapterUpdatePolicy.check(remote: Data(contentsOf: url), signature: Data(contentsOf: url.appendingPathExtension("sig")),
                                                     bundled: try varmdoSpec(), appBuild: 99)
        XCTAssertEqual(accepted.id, "se.varmdo.ksb")
    }

    func testValidSignatureIsAccepted() throws {
        let data = try changed { _ in }
        let withNewline = try signature(data) + Data("\n".utf8)
        XCTAssertNotNil(AdapterUpdatePolicy.accept(remote: data, signature: withNewline, bundled: try varmdoSpec(),
                                                   appBuild: 99, publicKey: testPublicKey))
    }

    func testUnsignedAdapterIsRejected() throws {
        let data = try changed { _ in }
        try assertSignatureRejected(data, signature: nil, publicKey: testPublicKey, "no .sig")
        try assertSignatureRejected(data, signature: Data(), publicKey: testPublicKey, "empty .sig")
        try assertSignatureRejected(data, signature: Data("not base64!".utf8), publicKey: testPublicKey, "garbage .sig")
        try assertSignatureRejected(data, signature: Data(repeating: 0x41, count: 4096), publicKey: testPublicKey, "oversized .sig")
        // The real app key: a downloaded file with no signature never replaces the bundled adapter.
        XCTAssertNil(AdapterUpdatePolicy.accept(remote: data, signature: nil, bundled: try varmdoSpec(), appBuild: 99))
    }

    func testTamperedAdapterIsRejected() throws {
        let original = try changed { _ in }
        let sig = try signature(original)
        // minAppBuild changed after signing: harmless content, still refused.
        let tampered = try changed { json in json["minAppBuild"] = 1 }
        try assertSignatureRejected(tampered, signature: sig, publicKey: testPublicKey, "edited after signing")
        // Even a single appended byte (whitespace) breaks the signature of the exact bytes.
        try assertSignatureRejected(original + Data(" ".utf8), signature: sig, publicKey: testPublicKey, "trailing byte")
        // Signed by somebody else's key.
        let other = try signature(original, key: Curve25519.Signing.PrivateKey())
        try assertSignatureRejected(original, signature: other, publicKey: testPublicKey, "foreign key")
        // The published signature does not cover a modified copy of the published file.
        let url = repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json")
        var published = try Data(contentsOf: url)
        published.append(contentsOf: Array(" ".utf8))
        try assertSignatureRejected(published, signature: try Data(contentsOf: url.appendingPathExtension("sig")),
                                    publicKey: AdapterSignature.publicKeyBase64, "modified published adapter")
    }

    func testStatusSignatureIsRequired() throws {
        let data = Data(#"{"se.varmdo.ksb": {"state": "down"}}"#.utf8)
        XCTAssertEqual(try AdapterStatus.decodeMap(data, signature: try signature(data), publicKey: testPublicKey)["se.varmdo.ksb"]?.state, .down)
        XCTAssertThrowsError(try AdapterStatus.decodeMap(data, signature: nil, publicKey: testPublicKey))
        let tampered = Data(#"{"se.varmdo.ksb": {"state": "ok"}}"#.utf8)
        XCTAssertThrowsError(try AdapterStatus.decodeMap(tampered, signature: try signature(data), publicKey: testPublicKey))
    }

    func testRoadTilesExplainResponsibilityInEveryLanguage() throws {
        let spec = try varmdoSpec()
        let languages: Set<String> = ["en", "sv", "cs", "da", "de", "et", "es", "fr", "it", "lv", "lt", "hu", "nl", "nb", "pl", "pt", "ro", "fi", "el", "ru", "uk", "ar"]
        for id in ["pothole", "winter", "sign", "streetlight"] {
            let note = try XCTUnwrap(spec.tile(id: id)?.responsibility, id)
            XCTAssertEqual(Set(note.values.keys), languages, id)
            XCTAssertTrue(note.values.values.allSatisfy { $0.contains("0771-921 921") }, id)
        }
        XCTAssertNil(spec.tile(id: "graffiti")?.responsibility)
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
        let spec = try check(data, appBuild: 4)
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
        try assertRejected(try changed { $0["webFormURL"] = "https://service.varmdo.se/OTHER" }, "changed web form")
        try assertRejected(try changed { $0["webFormURL"] = "https://evil.example.com/KSB" }, "web form off host")
        try assertRejected(try changed { $0["id"] = "se.evil.ksb" }, "unknown id")
    }

    func testWebFormAndTileLinksStayOnTheMunicipality() throws {
        let bundled = try varmdoSpec()
        XCTAssertEqual(AdapterSpecValidator.linkProblems(bundled), [])
        func withOtherLink(_ url: String) throws -> Data {
            try changed { json in
                var tiles = try XCTUnwrap(json["tiles"] as? [[String: Any]])
                let index = try XCTUnwrap(tiles.firstIndex { $0["id"] as? String == "other" })
                var links = try XCTUnwrap(tiles[index]["links"] as? [[String: Any]])
                links[0]["url"] = url
                tiles[index]["links"] = links
                json["tiles"] = tiles
            }
        }
        for url in ["https://evil.example.com/FELATER", "http://service.varmdo.se/FELATER", "https://varmdo.se.evil.com/x",
                    "https://user@service.varmdo.se/x", "javascript:alert(1)"] {
            try assertRejected(try withOtherLink(url), url)
        }
        XCTAssertNotNil(try? check(try withOtherLink("https://www.varmdo.se/kontakt.html")))
        // The bundled adapter itself is checked the same way.
        XCTAssertThrowsError(try AdapterCatalog.decode(try withOtherLink("https://evil.example.com/x")))
        XCTAssertThrowsError(try AdapterCatalog.decode(try changed { $0["webFormURL"] = "http://service.varmdo.se/KSB" }))
    }

    func testEmergencyHoursAreChecked() throws {
        func withRule(_ edit: @escaping (inout [String: Any]) -> Void) throws -> Data {
            try changed { json in
                var emergency = try XCTUnwrap(json["emergency"] as? [String: Any])
                var rules = try XCTUnwrap(emergency["rules"] as? [[String: Any]])
                edit(&rules[0])
                emergency["rules"] = rules
                json["emergency"] = emergency
            }
        }
        XCTAssertThrowsError(try AdapterCatalog.decode(try withRule { $0["from"] = "18:00" }), "from after until")
        XCTAssertThrowsError(try AdapterCatalog.decode(try withRule { $0["from"] = "8" }), "unreadable from")
        XCTAssertThrowsError(try AdapterCatalog.decode(try withRule { $0["isoWeekdays"] = [0] }), "weekday 0")
        XCTAssertNoThrow(try AdapterCatalog.decode(try withRule { $0.removeValue(forKey: "from") }), "from is optional")
        XCTAssertThrowsError(try AdapterCatalog.decode(try changed { json in
            var emergency = try XCTUnwrap(json["emergency"] as? [String: Any])
            emergency["holidays"] = "XX"
            json["emergency"] = emergency
        }), "unknown holiday calendar")
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
