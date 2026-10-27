import Foundation
import XCTest
@testable import FixaKit

// MARK: - Helpers

func fixture(_ name: String) throws -> String {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
    return String(decoding: try Data(contentsOf: url), as: UTF8.self)
}

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // FixaKitTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // FixaKit
    .deletingLastPathComponent() // fixa

func varmdoSpec() throws -> AdapterSpec {
    try AdapterCatalog.load(from: repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json"))
}

func validDraft() -> ReportDraft {
    ReportDraft(
        adapterID: "se.varmdo.ksb",
        tileID: "streetlight",
        description: "Lampan vid busshållplatsen är släckt sedan i måndags.",
        coordinate: Coordinate(latitude: 59.3262, longitude: 18.3856),
        locationText: "Gustavsbergs centrum",
        wantsFeedback: true,
        contact: Contact(firstName: "Anna", lastName: "Svensson", phone: "070-123 45 67", email: "anna@example.se")
    )
}

func formFields(_ body: Data?) -> [String: String] {
    var result: [String: String] = [:]
    for pair in String(decoding: body ?? Data(), as: UTF8.self).split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map {
            String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
        }
        result[parts[0]] = parts.count > 1 ? parts[1] : ""
    }
    return result
}

let base = "https://service.varmdo.se"
let faultURL = URL(string: "\(base)/EServices/Common/BlockPage.aspx?eServiceName=KSB&PageId=FaultReport")!

// MARK: - Parser

final class AbouPageParserTests: XCTestCase {
    let allFixtures = ["01-intro", "02-faultreport", "03-faultreport-validation", "04-contact", "05-summary", "06-session-lock", "07-after-cancel"]

    func testHiddenFieldsOnEveryFixture() throws {
        for name in allFixtures {
            let hidden = AbouPageParser.hiddenFields(try fixture(name))
            XCTAssertFalse(hidden["__VIEWSTATE", default: ""].isEmpty, name)
            XCTAssertNotNil(AbouPageParser.formAction(try fixture(name)), name)
        }
        XCTAssertNotNil(AbouPageParser.hiddenFields(try fixture("02-faultreport"))["__EVENTVALIDATION"])
    }

    func testFormActionIsUnescaped() throws {
        XCTAssertEqual(AbouPageParser.formAction(try fixture("02-faultreport")), "./BlockPage.aspx?eServiceName=KSB&PageId=FaultReport")
        XCTAssertEqual(AbouPageParser.formAction(try fixture("04-contact")), "./BlockPage.aspx?eServiceName=KSB&PageId=PersonalEmailInformation")
        XCTAssertEqual(AbouPageParser.formAction(try fixture("05-summary")), "./Summary.aspx?eServiceName=KSB&PageId=SummaryPage")
    }

    func testFieldNamesForEveryContractKey() throws {
        let spec = try varmdoSpec()
        let pages = ["FaultReport": try fixture("02-faultreport"), "PersonalEmailInformation": try fixture("04-contact")]
        let expected = ["KSB_14", "KSB_18", "KSB_20", "KSB_19", "U_29_1_1", "KSB_54", "U_29_3_2", "U_29_3_3", "KSB_17", "U_29_3_1"]
        var found: [String] = []
        for page in spec.channel.pages {
            for field in page.fields {
                let html = try XCTUnwrap(pages[page.id])
                let name = try XCTUnwrap(AbouPageParser.fieldName(html, key: field.key, control: field.control), field.key)
                XCTAssertTrue(name.hasPrefix("ctl00$ctl00$"), name)
                XCTAssertTrue(name.hasSuffix("$\(field.key)_field$\(field.control)"), name)
                found.append(field.key)
            }
        }
        XCTAssertEqual(Set(found), Set(expected))
        XCTAssertNil(AbouPageParser.fieldName(try fixture("02-faultreport"), key: "KSB_1", control: "textFieldControl"))
    }

    func testValidationErrors() throws {
        XCTAssertEqual(AbouPageParser.validationErrors(try fixture("03-faultreport-validation")), [
            "Välj ett värde för fältet 'Välj område'",
            "Fyll i fältet 'Beskriv felet här'",
            "Välj ett värde för fältet 'Jag vill ha återkoppling'",
        ])
        XCTAssertEqual(AbouPageParser.validationErrors(try fixture("02-faultreport")), [])
    }

    func testSessionLock() throws {
        XCTAssertTrue(AbouPageParser.isSessionLocked(try fixture("06-session-lock")))
        XCTAssertFalse(AbouPageParser.isSessionLocked(try fixture("02-faultreport")))
    }

    func testPageID() {
        XCTAssertEqual(AbouPageParser.pageID(from: faultURL), "FaultReport")
        XCTAssertEqual(AbouPageParser.pageID(from: URL(string: "\(base)/EServices/Common/Summary.aspx?eServiceName=KSB&PageId=SummaryPage")!), "SummaryPage")
        XCTAssertNil(AbouPageParser.pageID(from: URL(string: "\(base)/KSB")!))
    }

    func testParseReceiptTolerant() throws {
        let html = """
        <html><head><title>Tack för din felanmälan</title><script>var x = "ärendenummer 999";</script></head>
        <body><form method="post" action="./Receipt.aspx?eServiceName=KSB" id="MainForm"><input type="hidden" name="__VIEWSTATE" value="abc" />
        <main><h1>Tack!</h1><p>Ditt ärendenummer är KSB-2026-01234. Du får en bekräftelse via e-post.</p></main></form></body></html>
        """
        let url = URL(string: "\(base)/EServices/Common/Receipt.aspx?eServiceName=KSB")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let receipt = try XCTUnwrap(AbouPageParser.parseReceipt(html: html, url: url, now: now))
        XCTAssertEqual(receipt.caseNumber, "KSB-2026-01234")
        XCTAssertEqual(receipt.title, "Tack för din felanmälan")
        XCTAssertEqual(receipt.finalURL, url)
        XCTAssertEqual(receipt.submittedAt, now)
        XCTAssertTrue(receipt.message.contains("bekräftelse"))

        let noNumber = "<html><head><title>Klart</title></head><body><p>Tack, vi har tagit emot ditt ärende.</p></body></html>"
        let plain = try XCTUnwrap(AbouPageParser.parseReceipt(html: noNumber, url: url, now: now))
        XCTAssertNil(plain.caseNumber)
        XCTAssertEqual(plain.title, "Klart")

        XCTAssertEqual(AbouPageParser.parseReceipt(html: "<p>Referens: 4711</p>", url: url, now: now)?.caseNumber, "4711")
    }

    func testParseReceiptNilForFormAndErrorPages() throws {
        for name in ["02-faultreport", "03-faultreport-validation", "04-contact", "05-summary", "06-session-lock", "07-after-cancel"] {
            XCTAssertNil(AbouPageParser.parseReceipt(html: try fixture(name), url: faultURL, now: Date()), name)
        }
    }

    func testThankYouFixtures() throws {
        let marker = try XCTUnwrap(try varmdoSpec().channel.completionPostBackMarker)
        XCTAssertTrue(try fixture("08-thankyou-processing").contains(marker))
        XCTAssertFalse(try fixture("09-thankyou-receipt").contains(marker))
        let url = URL(string: "\(base)/EServices/Common/ThankYou.aspx?eServiceName=KSB&PageId=ThankYou")!
        let receipt = try XCTUnwrap(AbouPageParser.parseReceipt(html: try fixture("09-thankyou-receipt"), url: url, now: Date()))
        XCTAssertEqual(receipt.caseNumber, "261026-KSB-KS43")
        XCTAssertEqual(AbouPageParser.caseNumber(in: "Här är ditt ärendenummer 261026-KSB-KS43"), "261026-KSB-KS43")
    }
}

// MARK: - Spec, catalog, schema

final class AdapterSpecTests: XCTestCase {
    func testVarmdoSpecContent() throws {
        let spec = try varmdoSpec()
        XCTAssertEqual(spec.id, "se.varmdo.ksb")
        XCTAssertEqual(spec.specVersion, 1)
        XCTAssertEqual(spec.tiles.map(\.id), ["streetlight", "pothole", "winter", "sign", "graffiti", "park", "water", "other"])
        XCTAssertEqual(spec.categories.map(\.value), ["Belysning", "Gator och cykelvägar", "Klotter och skadegörelse", "Parker och grönytor", "Vatten och avlopp", "Övrigt"])
        XCTAssertEqual(spec.fallbackEmail, "varmdo.kommun@varmdo.se")
        let languages: Set<String> = ["en", "sv", "cs", "da", "de", "et", "es", "fr", "it", "lv", "lt", "hu", "nl", "nb", "pl", "pt", "ro", "fi", "el", "ru", "uk", "ar"]
        var texts = [spec.disclaimer] + spec.categories.map(\.title) + spec.tiles.map(\.title)
        if let emergency = spec.emergency { texts += [emergency.note] + emergency.contacts.map(\.title) }
        for text in texts {
            XCTAssertEqual(Set(text.values.keys), languages)
            XCTAssertFalse(text.values.values.contains { $0.isEmpty })
        }
        for tile in spec.tiles {
            XCTAssertNotNil(spec.category(id: tile.categoryID), tile.id)
        }
        XCTAssertTrue(spec.municipality.region.contains(spec.municipality.region.center))
    }

    func testLocalizedTextResolve() throws {
        let text = LocalizedText(["sv": "Hej", "en": "Hello", "fi": "Hei"])
        XCTAssertEqual(text.resolve(Locale(identifier: "fi_FI")), "Hei")
        XCTAssertEqual(text.resolve(Locale(identifier: "de_DE")), "Hello")
        XCTAssertEqual(LocalizedText(["sv": "Hej"]).resolve(Locale(identifier: "de")), "Hej")
        let encoded = try JSONEncoder().encode(LocalizedText(["sv": "Hej"]))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"{"sv":"Hej"}"#)
    }

    func testBundledCopyIsByteIdentical() throws {
        let root = try Data(contentsOf: repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json"))
        let bundledURL = try XCTUnwrap(AdapterCatalog.bundledURLs().first { $0.lastPathComponent == "se-varmdo-ksb.json" })
        XCTAssertEqual(try Data(contentsOf: bundledURL), root, "Copy adapters/se-varmdo-ksb.json into FixaKit/Sources/FixaKit/Resources/adapters/")
        XCTAssertEqual(AdapterCatalog.bundled().map(\.id), ["se.varmdo.ksb"])
    }

    func testVarmdoMatchesSchema() throws {
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appendingPathComponent("schema/adapter.schema.json")))
        let instance = try JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json")))
        let validator = MiniSchemaValidator(root: try XCTUnwrap(schema as? [String: Any]))
        XCTAssertEqual(validator.validate(instance), [])

        var broken = try XCTUnwrap(instance as? [String: Any])
        broken["tiles"] = "nope"
        broken.removeValue(forKey: "disclaimer")
        let errors = validator.validate(broken)
        XCTAssertTrue(errors.contains("$: missing disclaimer"), "\(errors)")
        XCTAssertTrue(errors.contains("$.tiles: expected array"), "\(errors)")
    }
}

/// Minimal JSON Schema subset: type, required, properties, additionalProperties, items, enum, $ref (#/$defs/…).
struct MiniSchemaValidator {
    let root: [String: Any]

    func validate(_ value: Any) -> [String] { validate(value, root, "$") }

    private func validate(_ value: Any, _ schema: [String: Any], _ path: String) -> [String] {
        if let ref = schema["$ref"] as? String {
            let name = ref.replacingOccurrences(of: "#/$defs/", with: "")
            guard let target = (root["$defs"] as? [String: Any])?[name] as? [String: Any] else { return ["\(path): bad $ref \(ref)"] }
            return validate(value, target, path)
        }
        var errors: [String] = []
        if let type = schema["type"] as? String, !matches(value, type) {
            return ["\(path): expected \(type)"]
        }
        if let options = schema["enum"] as? [Any], !options.contains(where: { ($0 as? NSObject)?.isEqual(value) == true }) {
            errors.append("\(path): not in enum")
        }
        if let object = value as? [String: Any] {
            for key in schema["required"] as? [String] ?? [] where object[key] == nil {
                errors.append("\(path): missing \(key)")
            }
            let properties = schema["properties"] as? [String: Any] ?? [:]
            for (key, child) in object.sorted(by: { $0.key < $1.key }) {
                if let sub = properties[key] as? [String: Any] {
                    errors += validate(child, sub, "\(path).\(key)")
                } else if let additional = schema["additionalProperties"] as? [String: Any] {
                    errors += validate(child, additional, "\(path).\(key)")
                } else if schema["additionalProperties"] as? Bool == false {
                    errors.append("\(path): unexpected \(key)")
                }
            }
        }
        if let array = value as? [Any], let items = schema["items"] as? [String: Any] {
            for (i, element) in array.enumerated() {
                errors += validate(element, items, "\(path)[\(i)]")
            }
        }
        return errors
    }

    private func matches(_ value: Any, _ type: String) -> Bool {
        let isBool = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "boolean": return isBool
        case "number": return value is NSNumber && !isBool
        case "integer":
            guard let n = value as? NSNumber, !isBool else { return false }
            return n.doubleValue.rounded() == n.doubleValue
        default: return true
        }
    }
}

// MARK: - Validator

final class ReportValidatorTests: XCTestCase {
    func testValidDraftHasNoIssues() throws {
        XCTAssertEqual(ReportValidator.validate(validDraft(), spec: try varmdoSpec()), [])
    }

    func testMissingCategory() throws {
        var d = validDraft()
        d.tileID = nil
        XCTAssertTrue(ReportValidator.validate(d, spec: try varmdoSpec()).contains(.init(field: .category, code: .missing)))
        d.categoryID = "water"
        XCTAssertFalse(ReportValidator.validate(d, spec: try varmdoSpec()).contains { $0.field == .category })
    }

    func testDescriptionLength() throws {
        var d = validDraft()
        for short in ["  ok  ", "12345 !!", "a1"] {
            d.description = short
            XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [.init(field: .description, code: .tooShort)], short)
        }
        d.description = String(repeating: "a", count: 4001)
        XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [.init(field: .description, code: .tooLong)])
        for blank in ["", "   ", "\n\t "] {
            d.description = blank
            XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [.init(field: .description, code: .missing)], blank)
        }
    }

    func testChipPhrasesPass() throws {
        var d = validDraft()
        for chip in ["Blinkar", "Djupt hål", "Släckt", "Hål"] {
            d.description = chip
            XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [], chip)
        }
    }

    func testTranslationDoesNotMakeTextTooLong() throws {
        var d = validDraft()
        d.description = String(repeating: "а", count: 3000)
        d.translation = MachineTranslation(sourceLanguage: "uk", text: String(repeating: "b", count: 3000))
        XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [])
    }

    func testEmailRules() throws {
        var d = validDraft()
        d.contact.email = ""
        XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [.init(field: .email, code: .missing)])
        d.wantsFeedback = false
        XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [])
        d.contact.email = "anna@"
        XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [.init(field: .email, code: .invalidFormat)])
    }

    func testPhoneFormat() throws {
        var d = validDraft()
        d.contact.phone = "ring mig"
        XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [.init(field: .phone, code: .invalidFormat)])
    }

    func testLocation() throws {
        var d = validDraft()
        d.coordinate = Coordinate(latitude: 59.3293, longitude: 18.0686) // Stockholm city
        XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [.init(field: .location, code: .outsideRegion)])
        d.coordinate = nil
        d.locationText = ""
        XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [.init(field: .location, code: .missing)])
        d.locationText = "Ingarö, Brunn"
        XCTAssertEqual(ReportValidator.validate(d, spec: try varmdoSpec()), [])
    }
}

// MARK: - Emergency

final class EmergencyRouterTests: XCTestCase {
    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Stockholm")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    func testRouting() throws {
        let emergency = try XCTUnwrap(try varmdoSpec().emergency)
        // 2026-10-29 is a Thursday.
        XCTAssertEqual(EmergencyRouter.contact(for: date("2026-10-29 16:59"), emergency: emergency).id, "servicecenter")
        XCTAssertEqual(EmergencyRouter.contact(for: date("2026-10-29 17:00"), emergency: emergency).id, "sos")
        XCTAssertEqual(EmergencyRouter.contact(for: date("2026-10-30 12:59"), emergency: emergency).id, "servicecenter")
        XCTAssertEqual(EmergencyRouter.contact(for: date("2026-10-30 13:00"), emergency: emergency).id, "sos")
        XCTAssertEqual(EmergencyRouter.contact(for: date("2026-10-31 10:00"), emergency: emergency).id, "sos")
        XCTAssertEqual(EmergencyRouter.contact(for: date("2026-11-01 10:00"), emergency: emergency).id, "sos")
        XCTAssertEqual(EmergencyRouter.contact(for: date("2026-10-26 09:00"), emergency: emergency).phone, "08-570 470 00")
        XCTAssertEqual(EmergencyRouter.contact(for: date("2026-10-31 10:00"), emergency: emergency).phone, "08-454 25 71")
    }
}

// MARK: - Composer & mail

final class ComposerTests: XCTestCase {
    func testDescriptionAndPlace() throws {
        let spec = try varmdoSpec()
        let d = validDraft()
        XCTAssertEqual(
            ReportComposer.description(for: d, spec: spec),
            "Gatubelysning ur funktion\n\nLampan vid busshållplatsen är släckt sedan i måndags."
        )
        XCTAssertEqual(ReportComposer.placeText(for: d), "Gustavsbergs centrum (59.3262, 18.3856)")
        var noCoordinate = d
        noCoordinate.coordinate = nil
        XCTAssertEqual(ReportComposer.placeText(for: noCoordinate), "Gustavsbergs centrum")
    }

    func testDescriptionWithTranslationAndDiscoveredTime() throws {
        let spec = try varmdoSpec()
        // 2026-10-27 08:15 UTC = 09:15 in Stockholm (CET, after the October change).
        let created = Date(timeIntervalSince1970: 1_793_088_900)
        var d = validDraft()
        d.description = "Ліхтар не світить"
        d.translation = MachineTranslation(sourceLanguage: "uk", text: "Lampan lyser inte")
        d.createdAt = created
        XCTAssertEqual(
            ReportComposer.description(for: d, spec: spec, now: created.addingTimeInterval(2 * 3600)),
            """
            Gatubelysning ur funktion

            Ліхтар не світить

            Översatt från ukrainska:
            Lampan lyser inte

            Upptäckt: 2026-10-27 09:15
            """
        )
        // Within the hour: no Upptäckt line.
        XCTAssertFalse(ReportComposer.description(for: d, spec: spec, now: created.addingTimeInterval(3600)).contains("Upptäckt"))
        d.createdAt = nil
        XCTAssertFalse(ReportComposer.description(for: d, spec: spec, now: created.addingTimeInterval(9 * 3600)).contains("Upptäckt"))
        XCTAssertEqual(ReportComposer.swedishLanguageName("ar"), "arabiska")
    }

    func testLongDescriptionIsCutSummaryAndTranslationKept() throws {
        let spec = try varmdoSpec()
        var d = validDraft()
        d.description = String(repeating: "x", count: 3900)
        d.translation = MachineTranslation(sourceLanguage: "uk", text: String(repeating: "y", count: 3800))
        let text = ReportComposer.description(for: d, spec: spec)
        XCTAssertLessThanOrEqual(text.count, spec.validation.descriptionMax)
        XCTAssertTrue(text.hasPrefix("Gatubelysning ur funktion\n\n"))
        XCTAssertTrue(text.hasSuffix(String(repeating: "y", count: 3800)))
        XCTAssertTrue(text.contains("Översatt från ukrainska:\n" + String(repeating: "y", count: 3800)), "the Swedish translation is kept whole when the original can give way")
        XCTAssertTrue(text.contains("x…"))
    }

    func testOldSavedDraftDecodes() throws {
        let old = #"{"adapterID":"se.varmdo.ksb","tileID":"streetlight","description":"Släckt","locationText":"Brunn","wantsFeedback":false,"contact":{"firstName":"","lastName":"","phone":"","email":""}}"#
        let d = try JSONDecoder().decode(ReportDraft.self, from: Data(old.utf8))
        XCTAssertNil(d.translation)
        XCTAssertNil(d.createdAt)
        var new = d
        new.translation = MachineTranslation(sourceLanguage: "ar", text: "Släckt")
        new.createdAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(try JSONDecoder().decode(ReportDraft.self, from: JSONEncoder().encode(new)), new)
    }

    func testMailFallback() throws {
        let spec = try varmdoSpec()
        let d = validDraft()
        XCTAssertEqual(MailFallback.subject(d, spec: spec), "Felanmälan: Belysning, Gustavsbergs centrum")
        let body = MailFallback.body(d, spec: spec)
        for expected in [
            "Område: Belysning",
            "Plats: Gustavsbergs centrum",
            "59.3262,18.3856",
            "https://maps.apple.com/?ll=59.3262,18.3856",
            "Gatubelysning ur funktion",
            "Lampan vid busshållplatsen",
            "Namn: Anna Svensson",
            "Telefon: 070-123 45 67",
            "E-post: anna@example.se",
            "Jag skickar felanmälan med e-post eftersom e-tjänsten inte gick att nå.",
        ] {
            XCTAssertTrue(body.contains(expected), expected)
        }
        XCTAssertFalse(body.localizedCaseInsensitiveContains("fixa"), "nothing in the e-mail names the app")
        XCTAssertFalse(body.localizedCaseInsensitiveContains("appen"))
        var old = d
        let created = Date(timeIntervalSince1970: 1_793_088_900)
        old.createdAt = created
        XCTAssertTrue(MailFallback.body(old, spec: spec, now: created.addingTimeInterval(7200)).contains("Upptäckt: 2026-10-27 09:15"))
    }
}

// MARK: - Submitter

actor FakeAbou: HTTPTransport {
    enum Mode { case normal, locked, validation, skipContact, thankYou }
    let mode: Mode
    private(set) var requests: [URLRequest] = []

    init(mode: Mode = .normal) { self.mode = mode }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!.absoluteString
        let method = request.httpMethod ?? "GET"
        let common = "\(base)/EServices/Common/"
        func page(_ name: String, _ at: String) throws -> (Data, HTTPURLResponse) {
            (Data(try fixture(name).utf8), HTTPURLResponse(url: URL(string: at)!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        func json(_ s: String) -> (Data, HTTPURLResponse) {
            (Data(s.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        switch (method, url) {
        case ("GET", "\(base)/KSB"):
            return try page("01-intro", url)
        case ("GET", _) where url.contains("Setup.aspx"):
            return mode == .locked ? try page("06-session-lock", url) : try page("02-faultreport", faultURL.absoluteString)
        case ("POST", _) where url.contains("UploadFile"):
            return json(#"{"success":true,"message":"Fil uppladdad"}"#)
        case ("POST", _) where url.hasSuffix("/Citizen/Field/Action"):
            return json(#"{"success":true,"files":[{"FileName":"foto.jpg","Id":"1"}]}"#)
        case ("POST", _) where url.contains("PageId=FaultReport"):
            switch mode {
            case .validation: return try page("03-faultreport-validation", url)
            case .skipContact: return try page("05-summary", "\(common)Summary.aspx?eServiceName=KSB&PageId=SummaryPage")
            default: return try page("04-contact", "\(common)BlockPage.aspx?eServiceName=KSB&PageId=PersonalEmailInformation")
            }
        case ("POST", _) where url.contains("PageId=PersonalEmailInformation"):
            return try page("05-summary", "\(common)Summary.aspx?eServiceName=KSB&PageId=SummaryPage")
        case ("POST", _) where url.contains("ThankYou.aspx"):
            return try page("09-thankyou-receipt", url)
        case ("POST", _) where url.contains("PageId=SummaryPage"):
            if mode == .thankYou {
                return try page("08-thankyou-processing", "\(common)ThankYou.aspx?eServiceName=KSB&PageId=ThankYou")
            }
            let html = "<html><head><title>Kvittens</title></head><body><main><p>Ärendenummer: KSB-123456</p></main></body></html>"
            return (Data(html.utf8), HTTPURLResponse(url: URL(string: "\(common)Receipt.aspx?eServiceName=KSB")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        default:
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
    }
}

final class StageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SubmissionStage] = []
    func append(_ s: SubmissionStage) { lock.withLock { items.append(s) } }
    var stages: [SubmissionStage] { lock.withLock { items } }
}

final class AbouSubmitterTests: XCTestCase {
    func testDryRunStopsAtSummaryWithCorrectFields() async throws {
        let spec = try varmdoSpec()
        let fake = FakeAbou()
        let log = StageLog()
        let receipt = try await AbouSubmitter(spec: spec, transport: fake, pageDelay: .zero).submit(validDraft(), dryRun: true) { log.append($0) }
        XCTAssertNil(receipt)
        XCTAssertEqual(log.stages, [.starting, .sendingReport, .sendingContact, .done])

        let requests = await fake.requests
        XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["GET", "GET", "POST", "POST"])
        XCTAssertFalse(requests.contains { $0.url!.absoluteString.contains("SummaryPage") }, "dry run must not post the summary")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == AbouSubmitter.userAgent })
        XCTAssertFalse(AbouSubmitter.userAgent.localizedCaseInsensitiveContains("fixa"))

        let report = formFields(requests[2].httpBody)
        let hidden = AbouPageParser.hiddenFields(try fixture("02-faultreport"))
        XCTAssertEqual(report["__EVENTTARGET"], spec.channel.nextEventTarget)
        XCTAssertEqual(report["__VIEWSTATE"], hidden["__VIEWSTATE"])
        XCTAssertEqual(report["__EVENTVALIDATION"], hidden["__EVENTVALIDATION"])
        func value(_ key: String) -> String? { report.first { $0.key.contains("$\(key)_field$") }?.value }
        XCTAssertEqual(value("KSB_14"), "Belysning")
        XCTAssertEqual(value("KSB_18"), "Gustavsbergs centrum (59.3262, 18.3856)")
        XCTAssertEqual(value("KSB_20"), "Ja, visa karta och ange position")
        XCTAssertEqual(value("KSB_19"), "59.3262,18.3856")
        XCTAssertTrue(report.keys.contains { $0.hasSuffix("$KSB_19_field$MapAnswer") })
        XCTAssertEqual(value("U_29_1_1"), "Gatubelysning ur funktion\n\nLampan vid busshållplatsen är släckt sedan i måndags.")
        XCTAssertEqual(value("KSB_54"), "Ja")
        XCTAssertEqual(requests[2].url?.absoluteString, faultURL.absoluteString)

        let contact = formFields(requests[3].httpBody)
        XCTAssertEqual(contact["__EVENTTARGET"], spec.channel.nextEventTarget)
        XCTAssertEqual(contact.first { $0.key.hasSuffix("$U_29_3_1_field$AnswerTextBoxControl") }?.value, "anna@example.se")
        XCTAssertEqual(contact.first { $0.key.hasSuffix("$U_29_3_2_field$textFieldControl") }?.value, "Anna")
        XCTAssertEqual(contact.first { $0.key.hasSuffix("$KSB_17_field$textFieldControl") }?.value, "070-123 45 67")
    }

    func testNoCoordinateSendsNej() async throws {
        let fake = FakeAbou()
        var d = validDraft()
        d.coordinate = nil
        _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(d, dryRun: true)
        let report = formFields(await fake.requests[2].httpBody)
        XCTAssertEqual(report.first { $0.key.hasSuffix("$KSB_20_field$radioButtonListFieldControl") }?.value, "Nej")
        XCTAssertEqual(report.first { $0.key.hasSuffix("$KSB_19_field$MapAnswer") }?.value, "")
    }

    func testFullSubmitWithPhoto() async throws {
        let fake = FakeAbou()
        let log = StageLog()
        var d = validDraft()
        d.photoJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let receipt = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(d) { log.append($0) }
        XCTAssertEqual(receipt?.caseNumber, "KSB-123456")
        XCTAssertEqual(log.stages, [.starting, .uploadingPhoto, .sendingReport, .sendingContact, .confirming, .done])

        let requests = await fake.requests
        let upload = try XCTUnwrap(requests.first { $0.url!.path.hasPrefix("/Citizen/Field/UploadFile/U.29.1.2") })
        XCTAssertEqual(upload.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        let uploadBody = String(decoding: upload.httpBody!, as: UTF8.self)
        XCTAssertNotNil(uploadBody.range(of: #"name="files\[\]"; filename="IMG_[0-9]{4}\.jpg""#, options: .regularExpression), uploadBody.prefix(300).description)
        XCTAssertTrue(upload.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary=----WebKitFormBoundary"))
        let verify = try XCTUnwrap(requests.first { $0.url!.path == "/Citizen/Field/Action" })
        let verifyBody = try XCTUnwrap(JSONSerialization.jsonObject(with: verify.httpBody!) as? [String: Any])
        XCTAssertEqual(verifyBody["FieldId"] as? String, "U.29.1.2")
        XCTAssertEqual((verifyBody["Properties"] as? [String: String])?["action"], "getFiles")
        XCTAssertLessThan(requests.firstIndex(of: upload)!, requests.firstIndex { $0.url!.absoluteString.contains("PageId=FaultReport") }!)
        XCTAssertEqual(formFields(requests.last!.httpBody)["__EVENTTARGET"], try varmdoSpec().channel.nextEventTarget)
    }

    func testServerValidationSurfaced() async throws {
        do {
            _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: FakeAbou(mode: .validation), pageDelay: .zero).submit(validDraft(), dryRun: true)
            XCTFail("expected error")
        } catch let error as SubmissionError {
            XCTAssertEqual(error, .serverValidation([
                "Välj ett värde för fältet 'Välj område'",
                "Fyll i fältet 'Beskriv felet här'",
                "Välj ett värde för fältet 'Jag vill ha återkoppling'",
            ]))
        }
    }

    func testServerMaySkipContactPage() async throws {
        let fake = FakeAbou(mode: .skipContact)
        let log = StageLog()
        var d = validDraft()
        d.wantsFeedback = false
        let receipt = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(d) { log.append($0) }
        XCTAssertEqual(receipt?.caseNumber, "KSB-123456")
        XCTAssertEqual(log.stages, [.starting, .sendingReport, .confirming, .done])
        let requests = await fake.requests
        XCTAssertFalse(requests.contains { $0.url!.absoluteString.contains("PersonalEmailInformation") })
        let report = formFields(requests[2].httpBody)
        XCTAssertEqual(report.first { $0.key.contains("$KSB_54_field$") }?.value, "Nej")
    }

    func testCompletionPostBackFollowsThankYou() async throws {
        let spec = try varmdoSpec()
        let fake = FakeAbou(mode: .thankYou)
        let log = StageLog()
        let receipt = try await AbouSubmitter(spec: spec, transport: fake, pageDelay: .zero).submit(validDraft()) { log.append($0) }
        XCTAssertEqual(receipt?.caseNumber, "261026-KSB-KS43")
        XCTAssertEqual(log.stages.suffix(2), [.confirming, .done])

        let requests = await fake.requests
        let slutfor = requests[requests.count - 2]
        let postBack = requests[requests.count - 1]
        XCTAssertTrue(slutfor.url!.absoluteString.contains("PageId=SummaryPage"))
        XCTAssertEqual(formFields(slutfor.httpBody)["__EVENTTARGET"], spec.channel.nextEventTarget)
        XCTAssertEqual(postBack.httpMethod, "POST")
        XCTAssertTrue(postBack.url!.absoluteString.contains("ThankYou.aspx?eServiceName=KSB&PageId=ThankYou"))
        XCTAssertEqual(formFields(postBack.httpBody)["__EVENTTARGET"], "")
        XCTAssertEqual(requests.filter { $0.url!.absoluteString.contains("ThankYou.aspx") }.count, 1)
    }

    func testNoCompletionPostBackWithoutMarker() async throws {
        let fake = FakeAbou()
        let receipt = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(validDraft())
        XCTAssertEqual(receipt?.caseNumber, "KSB-123456")
        let requests = await fake.requests
        XCTAssertEqual(requests.map { $0.httpMethod ?? "" }, ["GET", "GET", "POST", "POST", "POST"])
        XCTAssertFalse(requests.contains { $0.url!.absoluteString.contains("ThankYou.aspx") })
    }

    func testSessionLockSurfaced() async throws {
        do {
            _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: FakeAbou(mode: .locked), pageDelay: .zero).submit(validDraft(), dryRun: true)
            XCTFail("expected error")
        } catch let error as SubmissionError {
            XCTAssertEqual(error, .sessionLocked)
        }
    }
}
