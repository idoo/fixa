import XCTest
@testable import FixaKit

/// The kommun's contact page and the hosts Fixa opens in its in-app Safari view.
final class AdapterContactTests: XCTestCase {
    private func varmdoJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func changed(_ edit: (inout [String: Any]) throws -> Void) throws -> Data {
        var json = try varmdoJSON()
        try edit(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func spec() throws -> AdapterSpec {
        try AdapterCatalog.decode(try changed { _ in })
    }

    func testContactDecodes() throws {
        let spec = try spec()
        let contact = try XCTUnwrap(spec.contact)
        XCTAssertEqual(contact.pageURL.absoluteString, "https://www.varmdo.se/kommunochpolitik/kontaktcenter.4.1a4e4f4413f7b9c98702cd2.html")
        XCTAssertEqual(contact.title.resolve(Locale(identifier: "sv_SE")), "Värmdö kommuns kontaktcenter")
        XCTAssertEqual(contact.title.values.count, 22, "every app language")
        XCTAssertEqual(spec.allowedWebHosts, ["varmdo.se", "www.varmdo.se", "service.varmdo.se"])
    }

    func testShippedAdapterHasContact() {
        XCTAssertNotNil(AdapterCatalog.shipped(id: "se.varmdo.ksb")?.contact)
    }

    func testOldAdapterWithoutContactStillDecodes() throws {
        let spec = try AdapterCatalog.decode(try changed { json in
            json.removeValue(forKey: "contact")
            json.removeValue(forKey: "allowedWebHosts")
        })
        XCTAssertNil(spec.contact)
        XCTAssertNil(spec.allowedWebHosts)
        // Without an allowlist every link goes to Safari.
        XCTAssertFalse(spec.opensInApp(URL(string: "https://www.varmdo.se/")!))
    }

    func testHostAllowlist() throws {
        let spec = try spec()
        for url in ["https://www.varmdo.se/kommunochpolitik/kontaktcenter.4.1a4e4f4413f7b9c98702cd2.html",
                    "https://service.varmdo.se/KSB", "https://VARMDO.se/x", "https://varmdo.se"] {
            XCTAssertTrue(spec.opensInApp(URL(string: url)!), url)
        }
        for url in ["http://www.varmdo.se/", "https://evil.example.com/www.varmdo.se", "https://varmdo.se.evil.example.com/",
                    "https://notvarmdo.se/", "https://sub.www.varmdo.se/", "https://user@www.varmdo.se/",
                    "https://www.varmdo.se:8443/", "tel:0857047000", "mailto:x@varmdo.se", "https://github.com/idoo/fixa"] {
            XCTAssertFalse(spec.opensInApp(URL(string: url)!), url)
        }
    }

    func testContactAndHostsStayOnTheMunicipality() throws {
        func withContactURL(_ url: String) throws -> Data {
            try changed { json in
                var contact = try XCTUnwrap(json["contact"] as? [String: Any])
                contact["pageURL"] = url
                json["contact"] = contact
            }
        }
        XCTAssertThrowsError(try AdapterCatalog.decode(try withContactURL("https://evil.example.com/kontakt")), "other domain")
        XCTAssertThrowsError(try AdapterCatalog.decode(try withContactURL("http://www.varmdo.se/kontakt")), "plain http")
        XCTAssertThrowsError(try AdapterCatalog.decode(try withContactURL("https://notvarmdo.se/kontakt")), "lookalike")
        for host in ["evil.example.com", "notvarmdo.se", "varmdo.se.evil.com", "www.varmdo.se/x", ""] {
            XCTAssertThrowsError(try AdapterCatalog.decode(try changed { $0["allowedWebHosts"] = [host] }), host)
        }
        XCTAssertThrowsError(try AdapterCatalog.decode(try changed {
            $0["allowedWebHosts"] = (0...AdapterSpecValidator.maxListItems).map { "h\($0).varmdo.se" }
        }), "too many hosts")
    }
}
