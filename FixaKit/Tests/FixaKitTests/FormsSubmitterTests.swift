import Foundation
import XCTest
@testable import FixaKit

// MARK: - Helpers

private let common = "\(base)/EServices/Common/"

private func formFixture(_ service: String, _ name: String) throws -> String {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/forms/\(service)"), "\(service)/\(name)")
    return String(decoding: try Data(contentsOf: url), as: UTF8.self)
}

/// An adapter from inline JSON: municipality, channel markers, contact and disclaimer as in KSB, the
/// rest (`id`, channel paths, pages, uploads, categories, tiles, questions, validation) from `json`.
private func formSpec(_ json: String) throws -> AdapterSpec {
    let ksb = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json"))) as? [String: Any])
    let own = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    var merged = ksb
    merged["emergency"] = nil
    for (key, value) in own where key != "channel" { merged[key] = value }
    var channel = try XCTUnwrap(ksb["channel"] as? [String: Any])
    channel["upload"] = nil
    for (key, value) in try XCTUnwrap(own["channel"] as? [String: Any]) { channel[key] = value }
    merged["channel"] = channel
    return try JSONDecoder().decode(AdapterSpec.self, from: JSONSerialization.data(withJSONObject: merged))
}

private func field(_ role: String, _ key: String, _ control: String, _ type: String, _ sv: String, question: String? = nil) -> String {
    let q = question.map { #", "question": "\#($0)""# } ?? ""
    return #"{"role": "\#(role)", "key": "\#(key)", "control": "\#(control)", "type": "\#(type)", "labels": {"sv": ["\#(sv)"], "en": ["\#(sv)"]}\#(q)}"#
}

private func title(_ sv: String, _ en: String) -> String { #"{"sv": "\#(sv)", "en": "\#(en)"}"# }

private func validation(min: Int = 0, location: Bool = false) -> String {
    #"{"descriptionMin": \#(min), "descriptionMax": 4000, "emailRequiredWhenFeedback": false, "requireLocation": \#(location)}"#
}

/// Replays one e-service's captured pages: intro, the first page from `Setup.aspx`, each page POST to
/// `next[pageID]`, the summary POST to KSB's processing ThankYou page and its post-back to the receipt.
private actor FormsAbou: HTTPTransport {
    let service: String
    let intro: String
    let first: (fixture: String, url: String)
    let next: [String: (fixture: String, url: String)]
    private(set) var requests: [URLRequest] = []

    init(service: String, intro: String, first: (String, String), next: [String: (String, String)]) {
        self.service = service
        self.intro = intro
        self.first = (first.0, first.1)
        self.next = next.mapValues { ($0.0, $0.1) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        func ok(_ data: Data, _ at: String) -> (Data, HTTPURLResponse) {
            (data, HTTPURLResponse(url: URL(string: at)!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        if method == "GET", url.path == intro { return ok(Data(try formFixture(service, "00-intro").utf8), url.absoluteString) }
        if method == "GET", url.path.contains("Setup.aspx") { return ok(Data(try formFixture(service, first.fixture).utf8), first.url) }
        if method == "POST", url.path.contains("/Citizen/Field/UploadFile/") {
            return ok(Data(#"{"success":true,"message":"Fil uppladdad"}"#.utf8), url.absoluteString)
        }
        if method == "POST", url.path.hasSuffix("/Citizen/Field/Action") {
            return ok(Data(#"{"success":true,"files":[{"FileName":"IMG_0001.jpg","Id":218081}]}"#.utf8), url.absoluteString)
        }
        if method == "POST", url.path.contains("ThankYou.aspx") { return ok(Data(try fixture("09-thankyou-receipt").utf8), url.absoluteString) }
        if method == "POST", AbouPageParser.pageID(from: url) == "SummaryPage" {
            return ok(Data(try fixture("08-thankyou-processing").utf8), "\(common)ThankYou.aspx?eServiceName=\(service)&PageId=ThankYou")
        }
        if method == "POST", let id = AbouPageParser.pageID(from: url), let page = next[id] {
            return ok(Data(try formFixture(service, page.fixture).utf8), page.url)
        }
        return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
    }
}

private struct Part {
    let name: String
    let filename: String?
    let contentType: String?
    let body: Data
}

/// Parts of a `multipart/form-data` request, in order.
private func multipartParts(_ request: URLRequest) throws -> [Part] {
    let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
    let boundary = try XCTUnwrap(contentType.components(separatedBy: "boundary=").last)
    let body = try XCTUnwrap(request.httpBody)
    let delimiter = Data("--\(boundary)".utf8)
    var parts: [Part] = []
    var rest = body[...]
    while let start = rest.range(of: delimiter) {
        rest = rest[start.upperBound...]
        if rest.starts(with: Data("--".utf8)) { break }
        rest = rest.dropFirst(2) // CRLF
        guard let headEnd = rest.range(of: Data("\r\n\r\n".utf8)), let next = rest.range(of: delimiter) else { break }
        let head = String(decoding: rest[rest.startIndex..<headEnd.lowerBound], as: UTF8.self)
        let content = rest[headEnd.upperBound..<(next.lowerBound - 2)] // CRLF before the delimiter
        func attribute(_ name: String) -> String? {
            head.range(of: #"\#(name)="([^"]*)""#, options: .regularExpression).map {
                String(head[$0].dropFirst(name.count + 2).dropLast())
            }
        }
        let type = head.components(separatedBy: "\r\n").first { $0.hasPrefix("Content-Type: ") }.map { String($0.dropFirst(14)) }
        parts.append(Part(name: attribute(" name") ?? attribute("name") ?? "", filename: attribute("filename"), contentType: type, body: Data(content)))
        rest = rest[next.lowerBound...]
    }
    return parts
}

private func text(_ parts: [Part], _ suffix: String) -> String? {
    parts.first { $0.name.hasSuffix(suffix) }.map { String(decoding: $0.body, as: UTF8.self) }
}

private let photo = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x41, 0x42, 0xFF, 0xD9])
private let anna = Contact(firstName: "Anna", lastName: "Svensson", phone: "070-123 45 67", email: "anna@example.se")

// MARK: - Specs

private func felaterSpec() throws -> AdapterSpec {
    try formSpec(#"""
    {"id": "se.varmdo.felater", "webFormURL": "https://service.varmdo.se/FELATER",
     "service": {"title": \#(title("Återvinningsstation", "Recycling station")), "symbol": "arrow.3.trianglepath", "order": 1},
     "channel": {"service": "FELATER", "introPath": "/FELATER", "startPath": "/Setup.aspx?Service=FELATER&skipintro=true",
       "pages": [
         {"id": "page", "stage": "sendingReport", "fields": [
           \#(field("answer", "FELATER_1", "dropDownSelect2FieldControl", "select", "Välj återvinningsstation", question: "station")),
           \#(field("answer", "FELATER_2", "checkBoxListFieldControl", "checkbox", "Vad bör göras?", question: "action")),
           \#(field("answer", "FELATER_3", "checkBoxListFieldControl", "checkbox", "Vad behöver städas?", question: "cleanWhat")),
           \#(field("answer", "FELATER_5", "textFieldControl", "text", "När besökte du återvinningsstationen?", question: "visited")),
           \#(field("answer", "FELATER_4", "checkBoxListFieldControl", "checkbox", "Vad behöver tömmas?", question: "emptyWhat")),
           \#(field("answer", "FELATER_6", "textFieldControl", "text", "När besökte du återvinningsstationen?", question: "visited")),
           \#(field("fullName", "FELATER_15", "textFieldControl", "text", "Namn"))]},
         {"id": "SummaryPage", "stage": "confirming", "fields": []}],
       "uploads": [
         {"pageID": "page", "fieldID": "FELATER.7", "path": "/Citizen/Field/UploadFile/FELATER.7", "filePartName": "files[]", "fileName": "foto.jpg", "actionPath": "/Citizen/Field/Action", "when": {"question": "action", "value": "Städning"}},
         {"pageID": "page", "fieldID": "FELATER.8", "path": "/Citizen/Field/UploadFile/FELATER.8", "filePartName": "files[]", "fileName": "foto.jpg", "actionPath": "/Citizen/Field/Action", "when": {"question": "action", "value": "Extra tömning"}}]},
     "categories": [{"id": "recycling", "value": "Återvinningsstation", "title": \#(title("Återvinningsstation", "Recycling station"))}],
     "tiles": [
       {"id": "recycling-clean", "symbol": "sparkles", "categoryID": "recycling", "title": \#(title("Behöver städas", "Needs cleaning up")), "answers": {"action": ["Städning"]}, "questionIDs": ["station", "cleanWhat", "visited"]},
       {"id": "recycling-empty", "symbol": "trash.fill", "categoryID": "recycling", "title": \#(title("Behöver tömmas", "Needs emptying")), "answers": {"action": ["Extra tömning"]}, "questionIDs": ["station", "emptyWhat", "visited"]}],
     "questions": [
       {"id": "station", "kind": "choice", "title": \#(title("Vilken station?", "Which station?")), "required": true,
        "options": [{"value": "780001, Djurö, utanför ÅVC|Djuröhällsvägen, Human Bridge", "title": \#(title("Djurö", "Djurö"))}]},
       {"id": "action", "kind": "multiChoice", "title": \#(title("Vad bör göras?", "What should be done?")), "required": true,
        "options": [{"value": "Städning", "title": \#(title("Städning", "Cleaning"))}, {"value": "Extra tömning", "title": \#(title("Extra tömning", "Extra emptying"))}]},
       {"id": "cleanWhat", "kind": "multiChoice", "title": \#(title("Vad behöver städas?", "What needs cleaning?")), "required": true,
        "options": [{"value": "Förpackningar", "title": \#(title("Förpackningar", "Packaging"))}, {"value": "Batterier", "title": \#(title("Batterier", "Batteries"))}]},
       {"id": "emptyWhat", "kind": "multiChoice", "title": \#(title("Vad behöver tömmas?", "What needs emptying?")), "required": true,
        "options": [{"value": "Tidningar", "title": \#(title("Tidningar", "Newspapers"))}]},
       {"id": "visited", "kind": "dateTime", "title": \#(title("När var du där?", "When were you there?")), "required": true}],
     "validation": \#(validation())}
    """#)
}

private func anmutbsopSpec() throws -> AdapterSpec {
    try formSpec(#"""
    {"id": "se.varmdo.anmutbsop", "webFormURL": "https://service.varmdo.se/anmutbsop",
     "service": {"title": \#(title("Utebliven sophämtning", "Missed bin collection")), "symbol": "trash", "order": 2},
     "channel": {"service": "anmutbsop", "introPath": "/anmutbsop", "startPath": "/Setup.aspx?Service=anmutbsop&skipintro=true",
       "pages": [
         {"id": "dinauppgifter", "stage": "sendingReport", "fields": [
           \#(field("firstName", "anmutbsop_1", "textFieldControl", "text", "Förnamn")),
           \#(field("lastName", "anmutbsop_2", "textFieldControl", "text", "Efternamn")),
           \#(field("answer", "anmutbsop_3", "textFieldControl", "text", "Hämtadress", question: "address")),
           \#(field("email", "anmutbsop_6", "AnswerTextBoxControl", "text", "E-post")),
           \#(field("phone", "anmutbsop_9", "textFieldControl", "text", "Mobilnummer")),
           \#(field("answer", "anmutbsop_7", "dropDownListFieldControl", "select", "Vad har inte hämtats", question: "missed"))]},
         {"id": "SummaryPage", "stage": "confirming", "fields": []}],
       "uploads": [
         {"pageID": "dinauppgifter", "fieldID": "anmutbsop.10", "path": "/Citizen/Field/UploadFile/anmutbsop.10", "filePartName": "files[]", "fileName": "foto.jpg", "actionPath": "/Citizen/Field/Action"}]},
     "categories": [{"id": "waste", "value": "Utebliven sophämtning", "title": \#(title("Utebliven sophämtning", "Missed bin collection"))}],
     "tiles": [{"id": "bins-missed", "symbol": "trash", "categoryID": "waste", "title": \#(title("Soporna hämtades inte", "Bin not emptied")), "questionIDs": ["address", "missed"]}],
     "questions": [
       {"id": "address", "kind": "text", "title": \#(title("Hämtadress", "Pickup address")), "required": true, "maxLength": 200},
       {"id": "missed", "kind": "choice", "title": \#(title("Vad har inte hämtats", "What wasn't collected")), "required": true,
        "options": [{"value": "Hushållsavfall", "title": \#(title("Hushållsavfall", "Household waste"))}, {"value": "Matavfall", "title": \#(title("Matavfall", "Food waste"))}, {"value": "Båda", "title": \#(title("Båda", "Both"))}]}],
     "validation": \#(validation())}
    """#)
}

private func invasivaarterSpec() throws -> AdapterSpec {
    try formSpec(#"""
    {"id": "se.varmdo.invasivaarter", "webFormURL": "https://service.varmdo.se/invasivaarter",
     "service": {"title": \#(title("Invasiva växter", "Invasive plants")), "symbol": "leaf", "order": 3},
     "channel": {"service": "invasivaarter", "introPath": "/invasivaarter", "startPath": "/Setup.aspx?Service=invasivaarter&skipintro=true",
       "pages": [
         {"id": "newpage", "stage": "sendingReport", "fields": [
           \#(field("answer", "invasivaarter_13", "textFieldControl", "text", "Ange vilken invasiv art det rör sig om", question: "species")),
           \#(field("description", "invasivaarter_6", "textFieldControl", "textarea", "Beskrivning")),
           \#(field("mapAnswer", "invasivaarter_11", "MapAnswer", "hidden", "Ange gärna platsen i kartan")),
           \#(field("answer", "invasivaarter_7", "radioButtonListFieldControl", "radio", "Är det enstaka växter eller ett större bestånd?", question: "amount"))]},
         {"id": "newpage1", "stage": "sendingContact", "fields": [
           \#(field("firstName", "invasivaarter_2", "textFieldControl", "text", "Förnamn")),
           \#(field("lastName", "invasivaarter_3", "textFieldControl", "text", "Efternamn")),
           \#(field("phone", "invasivaarter_4", "textFieldControl", "text", "Telefonnummer")),
           \#(field("email", "invasivaarter_5", "textFieldControl", "text", "E-postadress"))]},
         {"id": "SummaryPage", "stage": "confirming", "fields": []}],
       "uploads": [{"pageID": "newpage", "kind": "formFile", "key": "invasivaarter_8", "control": "fileUploadControl"}]},
     "categories": [{"id": "nature", "value": "Invasiva arter", "title": \#(title("Invasiva arter", "Invasive species"))}],
     "tiles": [{"id": "invasive-plants", "symbol": "leaf", "categoryID": "nature", "title": \#(title("Invasiv växt", "Invasive plant")), "questionIDs": ["species", "amount"]}],
     "questions": [
       {"id": "species", "kind": "text", "title": \#(title("Vilken växt?", "Which plant?")), "required": true},
       {"id": "amount", "kind": "choice", "title": \#(title("Hur mycket?", "How much?")), "required": true,
        "options": [{"value": "Större bestånd", "title": \#(title("Större bestånd", "A large patch"))}, {"value": "Enstaka växter (upp till fem stycken)", "title": \#(title("Enstaka växter", "A few plants"))}]}],
     "validation": \#(validation(min: 10, location: true))}
    """#)
}

private func vkskrotbilSpec() throws -> AdapterSpec {
    try formSpec(#"""
    {"id": "se.varmdo.vkskrotbil", "webFormURL": "https://service.varmdo.se/VKSKROTBIL",
     "service": {"title": \#(title("Övergivet fordon", "Abandoned vehicle")), "symbol": "car", "order": 4},
     "channel": {"service": "VKSKROTBIL", "introPath": "/VKSKROTBIL", "startPath": "/Setup.aspx?Service=VKSKROTBIL&skipintro=true",
       "pages": [
         {"id": "Uppgifterombilen", "stage": "sendingReport", "fields": [
           \#(field("answer", "VKSKROTBIL_1", "textFieldControl", "text", "Typ av fordon (ex personbil)", question: "vehicleType")),
           \#(field("answer", "VKSKROTBIL_2", "textFieldControl", "text", "Registreringsnummer", question: "registration")),
           \#(field("answer", "VKSKROTBIL_3", "textFieldControl", "text", "Fabrikat", question: "make")),
           \#(field("answer", "VKSKROTBIL_4", "textFieldControl", "text", "Färg", question: "colour")),
           \#(field("place", "VKSKROTBIL_5", "textFieldControl", "text", "Var står fordonet?")),
           \#(field("fullName", "VKSKROTBIL_6", "textFieldControl", "text", "Ditt namn (frivilligt)")),
           \#(field("email", "VKSKROTBIL_7", "textFieldControl", "text", "E-post (frivilligt)")),
           \#(field("phone", "VKSKROTBIL_8", "textFieldControl", "text", "Ditt telefonnummet (frivilligt)")),
           \#(field("description", "VKSKROTBIL_9", "textFieldControl", "text", "Övrig information"))]},
         {"id": "SummaryPage", "stage": "confirming", "fields": []}],
       "uploads": [{"pageID": "Uppgifterombilen", "kind": "formFile", "key": "VKSKROTBIL_10", "control": "fileUploadControl"}]},
     "categories": [{"id": "vehicles", "value": "Skrotbil", "title": \#(title("Skrotbil", "Abandoned vehicle"))}],
     "tiles": [{"id": "abandoned-car", "symbol": "car", "categoryID": "vehicles", "title": \#(title("Övergivet fordon", "Abandoned vehicle")), "questionIDs": ["vehicleType", "registration", "make", "colour"]}],
     "questions": [
       {"id": "vehicleType", "kind": "text", "title": \#(title("Typ av fordon", "Type of vehicle")), "required": true},
       {"id": "registration", "kind": "text", "title": \#(title("Registreringsnummer", "Number plate")), "required": true, "maxLength": 20},
       {"id": "make", "kind": "text", "title": \#(title("Märke", "Make")), "required": true},
       {"id": "colour", "kind": "text", "title": \#(title("Färg", "Colour")), "required": true}],
     "validation": \#(validation(location: true))}
    """#)
}

// MARK: - Tests

final class FormsSubmitterTests: XCTestCase {
    func testFelaterCleaningPostsChecklistsDateAndAjaxPhoto() async throws {
        try await checkFelater(try felaterSpec())
    }

    func testShippedFelater() async throws {
        try await checkFelater(try XCTUnwrap(AdapterCatalog.shipped(id: "se.varmdo.felater")))
    }

    func testShippedInvasivaarter() async throws {
        try await checkInvasivaarter(try XCTUnwrap(AdapterCatalog.shipped(id: "se.varmdo.invasivaarter")))
    }

    func testShippedVkskrotbil() async throws {
        try await checkVkskrotbil(try XCTUnwrap(AdapterCatalog.shipped(id: "se.varmdo.vkskrotbil")))
    }

    func testShippedAnmutbsop() async throws {
        try await checkAnmutbsop(try XCTUnwrap(AdapterCatalog.shipped(id: "se.varmdo.anmutbsop")))
    }

    /// An option value from the adapter's own question.
    private func option(_ spec: AdapterSpec, _ question: String, _ value: String) throws -> String {
        let options = try XCTUnwrap(spec.question(id: question)?.options, question)
        return try XCTUnwrap(options.first { $0.value == value }?.value, "\(question): \(value)")
    }

    private func checkFelater(_ spec: AdapterSpec) async throws {
        let station = "780001, Djurö, utanför ÅVC|Djuröhällsvägen, Human Bridge"
        let fake = FormsAbou(
            service: "felater", intro: "/FELATER",
            first: ("01-page", "\(common)BlockPage.aspx?eServiceName=FELATER&PageId=page"),
            next: ["page": ("04-summary", "\(common)Summary.aspx?eServiceName=FELATER&PageId=SummaryPage")]
        )
        let draft = ReportDraft(
            adapterID: "se.varmdo.felater", tileID: "recycling-clean", photoJPEG: photo, contact: anna,
            answers: [
                "station": [try option(spec, "station", station)],
                "cleanWhat": [try option(spec, "cleanWhat", "Förpackningar")],
                "visited": ["2026-11-19T10:00:00+01:00"],
                "emptyWhat": ["Tidningar"], // not visible for this tile: never posted
            ]
        )
        let receipt = try await AbouSubmitter(spec: spec, transport: fake, pageDelay: .zero).submit(draft)
        XCTAssertNotNil(receipt)

        let requests = await fake.requests
        let pagePost = try XCTUnwrap(requests.firstIndex { $0.httpMethod == "POST" && AbouPageParser.pageID(from: $0.url!) == "page" })
        let uploads = requests.indices.filter { requests[$0].url!.path.contains("/Citizen/Field/UploadFile/") }
        XCTAssertEqual(uploads.map { requests[$0].url!.path }, ["/Citizen/Field/UploadFile/FELATER.7"])
        XCTAssertTrue(uploads.allSatisfy { $0 < pagePost })
        XCTAssertTrue(requests.contains { AbouPageParser.pageID(from: $0.url!) == "SummaryPage" })

        let body = formFields(requests[pagePost].httpBody)
        XCTAssertEqual(requests[pagePost].value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        func value(_ suffix: String) -> String? { body.first { $0.key.hasSuffix(suffix) }?.value }
        XCTAssertEqual(value("$FELATER_1_field$dropDownSelect2FieldControl"), station)
        XCTAssertEqual(value("$FELATER_2_field$checkBoxListFieldControl$0"), "Städning")
        XCTAssertNil(value("$FELATER_2_field$checkBoxListFieldControl$1"))
        XCTAssertEqual(value("$FELATER_3_field$checkBoxListFieldControl$5"), "Förpackningar")
        XCTAssertEqual(body.keys.filter { $0.contains("$FELATER_3_field$") }.count, 1)
        XCTAssertEqual(value("$FELATER_5_field$textFieldControl"), "2026-11-19 10:00")
        XCTAssertEqual(value("$FELATER_15_field$textFieldControl"), "Anna Svensson")
        XCTAssertFalse(body.keys.contains { $0.contains("$FELATER_4_field$") || $0.contains("$FELATER_6_field$") }, "fields hidden by the activation rules are not posted")
    }

    func testInvasivaarterPostsMultipartWithPhotoInFileInput() async throws {
        try await checkInvasivaarter(try invasivaarterSpec())
    }

    private func checkInvasivaarter(_ spec: AdapterSpec) async throws {
        let fake = FormsAbou(
            service: "invasivaarter", intro: "/invasivaarter",
            first: ("01-newpage", "\(common)BlockPage.aspx?eServiceName=invasivaarter&PageId=newpage"),
            next: [
                "newpage": ("03-newpage1-contact", "\(common)BlockPage.aspx?eServiceName=invasivaarter&PageId=newpage1"),
                "newpage1": ("04-summary", "\(common)Summary.aspx?eServiceName=invasivaarter&PageId=SummaryPage"),
            ]
        )
        let draft = ReportDraft(
            adapterID: "se.varmdo.invasivaarter", tileID: "invasive-plants",
            description: "Bredvid röda huset vid badplatsen.",
            coordinate: Coordinate(latitude: 59.3262, longitude: 18.3856),
            photoJPEG: photo, contact: anna,
            answers: ["species": ["Blomsterlupin"], "amount": [try option(spec, "amount", "Större bestånd")]]
        )
        let receipt = try await AbouSubmitter(spec: spec, transport: fake, pageDelay: .zero).submit(draft)
        XCTAssertNotNil(receipt)

        let requests = await fake.requests
        XCTAssertFalse(requests.contains { $0.url!.path.contains("/Citizen/Field/") }, "formFile uploads never use the ajax endpoint")
        let page = try XCTUnwrap(requests.first { $0.httpMethod == "POST" && AbouPageParser.pageID(from: $0.url!) == "newpage" })
        XCTAssertTrue(page.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=----WebKitFormBoundary") == true)
        let parts = try multipartParts(page)
        let file = try XCTUnwrap(parts.first { $0.name.hasSuffix("$invasivaarter_8_field$fileUploadControl") })
        XCTAssertNotNil(file.filename?.range(of: #"^IMG_\d{4}\.jpg$"#, options: .regularExpression), file.filename ?? "-")
        XCTAssertEqual(file.contentType, "image/jpeg")
        XCTAssertEqual(file.body, photo)
        for key in ["invasivaarter_9", "invasivaarter_10"] {
            let empty = try XCTUnwrap(parts.first { $0.name.hasSuffix("$\(key)_field$fileUploadControl") }, key)
            XCTAssertEqual(empty.filename, "")
            XCTAssertEqual(empty.contentType, "application/octet-stream")
            XCTAssertTrue(empty.body.isEmpty)
        }
        XCTAssertEqual(text(parts, "$invasivaarter_7_field$radioButtonListFieldControl"), "Större bestånd")
        XCTAssertEqual(text(parts, "$invasivaarter_11_field$MapAnswer"), "59.3262,18.3856")
        XCTAssertEqual(text(parts, "$invasivaarter_13_field$textFieldControl"), "Blomsterlupin")
        XCTAssertEqual(text(parts, "__EVENTTARGET"), spec.channel.nextEventTarget)
        XCTAssertFalse(text(parts, "__VIEWSTATE", ).map(\.isEmpty) ?? true)

        let contact = try XCTUnwrap(requests.first { $0.httpMethod == "POST" && AbouPageParser.pageID(from: $0.url!) == "newpage1" })
        XCTAssertEqual(formFields(contact.httpBody).first { $0.key.hasSuffix("$invasivaarter_5_field$textFieldControl") }?.value, "anna@example.se")
    }

    func testVkskrotbilPostsMultipartWithPlaceNameAndPhoto() async throws {
        try await checkVkskrotbil(try vkskrotbilSpec())
    }

    private func checkVkskrotbil(_ spec: AdapterSpec) async throws {
        let fake = FormsAbou(
            service: "vkskrotbil", intro: "/VKSKROTBIL",
            first: ("01-uppgifterombilen", "\(common)FieldPage.aspx?eServiceName=VKSKROTBIL&PageId=Uppgifterombilen"),
            next: ["Uppgifterombilen": ("03-summary", "\(common)Summary.aspx?eServiceName=VKSKROTBIL&PageId=SummaryPage")]
        )
        let draft = ReportDraft(
            adapterID: "se.varmdo.vkskrotbil", tileID: "abandoned-car",
            coordinate: Coordinate(latitude: 59.3262, longitude: 18.3856), locationText: "Gustavsbergs centrum",
            photoJPEG: photo, contact: anna,
            answers: ["vehicleType": ["Personbil"], "registration": ["ABC 123"], "make": ["Volvo"], "colour": ["Röd"]]
        )
        let receipt = try await AbouSubmitter(spec: spec, transport: fake, pageDelay: .zero).submit(draft)
        XCTAssertNotNil(receipt)

        let requests = await fake.requests
        let page = try XCTUnwrap(requests.first { $0.httpMethod == "POST" && AbouPageParser.pageID(from: $0.url!) == "Uppgifterombilen" })
        XCTAssertTrue(page.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=----WebKitFormBoundary") == true)
        let parts = try multipartParts(page)
        let file = try XCTUnwrap(parts.first { $0.name.hasSuffix("$VKSKROTBIL_10_field$fileUploadControl") })
        XCTAssertEqual(file.body, photo)
        XCTAssertEqual(file.contentType, "image/jpeg")
        XCTAssertEqual(text(parts, "$VKSKROTBIL_5_field$textFieldControl"), "Gustavsbergs centrum (59.3262, 18.3856)")
        XCTAssertEqual(text(parts, "$VKSKROTBIL_6_field$textFieldControl"), "Anna Svensson")
        XCTAssertEqual(text(parts, "$VKSKROTBIL_2_field$textFieldControl"), "ABC 123")

        // The summary's own form is not multipart: Slutför stays urlencoded.
        let summary = try XCTUnwrap(requests.first { $0.httpMethod == "POST" && AbouPageParser.pageID(from: $0.url!) == "SummaryPage" })
        XCTAssertEqual(summary.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        XCTAssertEqual(requests.filter { AbouPageParser.pageID(from: $0.url!) == "SummaryPage" }.count, 1)
    }

    func testMissingFileInputIsDriftBeforeAnythingIsSent() async throws {
        let html = try formFixture("vkskrotbil", "01-uppgifterombilen")
            .replacingOccurrences(of: "VKSKROTBIL_10_field$fileUploadControl", with: "VKSKROTBIL_11_field$fileUploadControl")
        actor Renamed: HTTPTransport {
            let html: String
            private(set) var posts = 0
            init(html: String) { self.html = html }
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                if request.httpMethod == "POST" { posts += 1 }
                let at = request.url!.path.contains("Setup.aspx")
                    ? "\(common)FieldPage.aspx?eServiceName=VKSKROTBIL&PageId=Uppgifterombilen" : request.url!.absoluteString
                return (Data(html.utf8), HTTPURLResponse(url: URL(string: at)!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        let fake = Renamed(html: html)
        let draft = ReportDraft(
            adapterID: "se.varmdo.vkskrotbil", tileID: "abandoned-car", locationText: "Gustavsberg", photoJPEG: photo,
            answers: ["vehicleType": ["Personbil"], "registration": ["ABC 123"], "make": ["Volvo"], "colour": ["Röd"]]
        )
        do {
            _ = try await AbouSubmitter(spec: try vkskrotbilSpec(), transport: fake, pageDelay: .zero).submit(draft)
            XCTFail("expected drift")
        } catch SubmissionError.formChanged(let drift) {
            XCTAssertEqual(drift.pageID, "Uppgifterombilen")
        }
        let posts = await fake.posts
        XCTAssertEqual(posts, 0)
    }

    func testAnmutbsopUploadsPhotoBeforeThePage() async throws {
        try await checkAnmutbsop(try anmutbsopSpec())
    }

    private func checkAnmutbsop(_ spec: AdapterSpec) async throws {
        let fake = FormsAbou(
            service: "anmutbsop", intro: "/anmutbsop",
            first: ("01-dinauppgifter", "\(common)BlockPage.aspx?eServiceName=anmutbsop&PageId=dinauppgifter"),
            next: ["dinauppgifter": ("03-summary", "\(common)Summary.aspx?eServiceName=anmutbsop&PageId=SummaryPage")]
        )
        let draft = ReportDraft(
            adapterID: "se.varmdo.anmutbsop", tileID: "bins-missed", photoJPEG: photo, contact: anna,
            answers: ["address": ["Skogsbovägen 9"], "missed": [try option(spec, "missed", "Matavfall")]]
        )
        let receipt = try await AbouSubmitter(spec: spec, transport: fake, pageDelay: .zero).submit(draft)
        XCTAssertNotNil(receipt)

        let requests = await fake.requests
        let page = try XCTUnwrap(requests.firstIndex { $0.httpMethod == "POST" && AbouPageParser.pageID(from: $0.url!) == "dinauppgifter" })
        let upload = try XCTUnwrap(requests.firstIndex { $0.url!.path == "/Citizen/Field/UploadFile/anmutbsop.10" })
        XCTAssertLessThan(upload, page)
        let body = formFields(requests[page].httpBody)
        func value(_ suffix: String) -> String? { body.first { $0.key.hasSuffix(suffix) }?.value }
        XCTAssertEqual(value("$anmutbsop_3_field$textFieldControl"), "Skogsbovägen 9")
        XCTAssertEqual(value("$anmutbsop_6_field$AnswerTextBoxControl"), "anna@example.se")
        XCTAssertEqual(value("$anmutbsop_7_field$dropDownListFieldControl"), "Matavfall")
        XCTAssertEqual(value("$anmutbsop_1_field$textFieldControl"), "Anna")
    }

    func testParserMultipartHelpers() throws {
        XCTAssertTrue(AbouPageParser.isMultipartForm(try formFixture("invasivaarter", "01-newpage")))
        XCTAssertFalse(AbouPageParser.isMultipartForm(try formFixture("felater", "01-page")))
        XCTAssertFalse(AbouPageParser.isMultipartForm(try fixture("02-faultreport")))
        XCTAssertEqual(AbouPageParser.fileInputNames(try formFixture("invasivaarter", "01-newpage")).compactMap { FormStructure.split($0)?.key },
                       ["invasivaarter_8", "invasivaarter_9", "invasivaarter_10"])
        XCTAssertEqual(AbouPageParser.fileInputNames(try formFixture("felater", "01-page")), [], "ajax upload inputs have no name")
    }
}

final class KSBActivationRuleTests: XCTestCase {
    /// KSB.54 (feedback) is hidden by the page's rule when KSB.14 = "Vatten och avlopp", yet KSB keeps
    /// posting it: only `answer` fields are dropped for activation rules.
    func testWaterReportStillPostsFeedbackRadio() async throws {
        let fake = FakeAbou(mode: .skipContact)
        var draft = validDraft()
        draft.tileID = "water"
        draft.wantsFeedback = false
        _ = try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(draft, dryRun: true)
        let report = formFields(await fake.requests[2].httpBody)
        XCTAssertEqual(report.first { $0.key.hasSuffix("$KSB_14_field$dropDownListFieldControl") }?.value, "Vatten och avlopp")
        XCTAssertEqual(report.first { $0.key.contains("$KSB_54_field$") }?.value, "Nej")
    }
}
