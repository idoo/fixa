import XCTest
@testable import FixaKit

/// Inline adapters shaped like the Värmdö e-services of the "More forms" section, built on the KSB
/// adapter's municipality and channel. Shared by the forms tests.
enum FormsFixtures {
    static func text(_ sv: String, _ en: String? = nil) -> [String: String] { ["sv": sv, "en": en ?? sv] }

    static func field(_ role: String, _ key: String, _ control: String = "textFieldControl", type: String = "text",
                      question: String? = nil) -> [String: Any] {
        var f: [String: Any] = ["role": role, "key": key, "control": control, "type": type]
        if let question { f["question"] = question }
        return f
    }

    static func option(_ value: String, _ en: String? = nil) -> [String: Any] {
        ["value": value, "title": text(value, en)]
    }

    static func question(_ id: String, _ kind: String, _ sv: String, required: Bool = true, options: [String]? = nil,
                         suggestions: [String]? = nil, maxLength: Int? = nil, translate: Bool = false) -> [String: Any] {
        var q: [String: Any] = ["id": id, "kind": kind, "title": text(sv, id), "required": required]
        if let options { q["options"] = options.map { option($0) } }
        if let suggestions { q["suggestions"] = suggestions.map { option($0) } }
        if let maxLength { q["maxLength"] = maxLength }
        if translate { q["translate"] = true }
        return q
    }

    static func ksbJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("adapters/se-varmdo-ksb.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func ksb() throws -> AdapterSpec {
        try AdapterCatalog.decode(try JSONSerialization.data(withJSONObject: ksbJSON()))
    }

    /// A non-primary adapter on the KSB base with these pages, uploads, questions and tiles.
    static func form(id: String, service: String, order: Int, category: String, pages: [[String: Any]],
                     uploads: [[String: Any]], questions: [[String: Any]], tiles: [[String: Any]],
                     validation: [String: Any], extra: [String: Any] = [:]) throws -> [String: Any] {
        var json = try ksbJSON()
        json["id"] = id
        json["emergency"] = nil
        json["service"] = ["title": text(service), "subtitle": text(service), "symbol": "leaf", "order": order]
        json["categories"] = [["id": category, "value": category, "title": text(category)]]
        json["questions"] = questions
        json["tiles"] = tiles.map { tile -> [String: Any] in
            var t = tile
            t["categoryID"] = category
            t["symbol"] = t["symbol"] ?? "leaf"
            t["title"] = t["title"] ?? text(t["id"] as? String ?? "")
            return t
        }
        json["validation"] = validation
        var channel = try XCTUnwrap(json["channel"] as? [String: Any])
        channel["upload"] = nil
        channel["uploads"] = uploads
        channel["pages"] = pages + [["id": "SummaryPage", "stage": "confirming", "fields": [] as [Any]]]
        json["channel"] = channel
        for (key, value) in extra { json[key] = value }
        return json
    }

    static func felaterJSON() throws -> [String: Any] {
        try form(
            id: "test.felater", service: "Återvinningsstation", order: 1, category: "recycling",
            pages: [["id": "page", "stage": "sendingReport", "fields": [
                field("answer", "FELATER_1", "dropDownSelect2FieldControl", type: "select", question: "station"),
                field("answer", "FELATER_2", "checkBoxListFieldControl", type: "checkbox", question: "action"),
                field("answer", "FELATER_3", "checkBoxListFieldControl", type: "checkbox", question: "cleanWhat"),
                field("answer", "FELATER_5", question: "visited"),
                field("answer", "FELATER_4", "checkBoxListFieldControl", type: "checkbox", question: "emptyWhat"),
                field("answer", "FELATER_6", question: "visited"),
                field("fullName", "FELATER_15"),
            ]]],
            uploads: [
                ["pageID": "page", "fieldID": "FELATER.7", "path": "/Citizen/Field/UploadFile/FELATER.7",
                 "filePartName": "files[]", "fileName": "foto.jpg", "actionPath": "/Citizen/Field/Action",
                 "when": ["question": "action", "value": "Städning"]],
                ["pageID": "page", "fieldID": "FELATER.8", "path": "/Citizen/Field/UploadFile/FELATER.8",
                 "filePartName": "files[]", "fileName": "foto.jpg", "actionPath": "/Citizen/Field/Action",
                 "when": ["question": "action", "value": "Extra tömning"]],
            ],
            questions: [
                question("station", "choice", "Vilken station?", options: ["780005, Gustavsberg centrum|Coop", "780006, Hemmesta"]),
                question("action", "multiChoice", "Vad bör göras?", required: false, options: ["Städning", "Extra tömning"]),
                question("cleanWhat", "multiChoice", "Vad behöver städas?", options: ["Batterier", "Tidningar"]),
                question("emptyWhat", "multiChoice", "Vad behöver tömmas?", options: ["Glasförpackningar", "Batterier"]),
                question("visited", "dateTime", "När var du där?"),
            ],
            tiles: [
                ["id": "t-clean", "answers": ["action": ["Städning"]], "questionIDs": ["station", "cleanWhat", "visited"]],
                ["id": "t-empty", "answers": ["action": ["Extra tömning"]], "questionIDs": ["station", "emptyWhat", "visited"]],
            ],
            validation: ["descriptionMin": 0, "descriptionMax": 4000, "descriptionRequired": false,
                         "emailRequiredWhenFeedback": false, "requireLocation": false, "photoRequired": true]
        )
    }

    static func anmutbsopJSON() throws -> [String: Any] {
        try form(
            id: "test.anmutbsop", service: "Utebliven sophämtning", order: 2, category: "waste",
            pages: [["id": "dinauppgifter", "stage": "sendingReport", "fields": [
                field("firstName", "anmutbsop_1"),
                field("lastName", "anmutbsop_2"),
                field("answer", "anmutbsop_3", question: "address"),
                field("email", "anmutbsop_6", "AnswerTextBoxControl"),
                field("phone", "anmutbsop_9"),
                field("answer", "anmutbsop_7", "dropDownListFieldControl", type: "select", question: "missed"),
            ]]],
            uploads: [["pageID": "dinauppgifter", "fieldID": "anmutbsop.10", "path": "/Citizen/Field/UploadFile/anmutbsop.10",
                       "filePartName": "files[]", "fileName": "foto.jpg", "actionPath": "/Citizen/Field/Action"]],
            questions: [
                question("address", "text", "Hämtadress", maxLength: 200),
                question("missed", "choice", "Vad har inte hämtats", options: ["Hushållsavfall", "Matavfall", "Båda"]),
            ],
            tiles: [["id": "t-bins", "questionIDs": ["address", "missed"]]],
            validation: ["descriptionMin": 0, "descriptionMax": 4000, "descriptionRequired": false,
                         "emailRequiredWhenFeedback": false, "emailRequired": true, "requireLocation": false,
                         "photoRequired": false]
        )
    }

    static func vkskrotbilJSON() throws -> [String: Any] {
        try form(
            id: "test.vkskrotbil", service: "Övergivet fordon", order: 4, category: "vehicles",
            pages: [["id": "Uppgifterombilen", "stage": "sendingReport", "fields": [
                field("answer", "VKSKROTBIL_1", question: "vehicleType"),
                field("answer", "VKSKROTBIL_2", question: "registration"),
                field("place", "VKSKROTBIL_5"),
                field("fullName", "VKSKROTBIL_6"),
                field("email", "VKSKROTBIL_7"),
                field("phone", "VKSKROTBIL_8"),
                field("description", "VKSKROTBIL_9"),
            ]]],
            uploads: [["pageID": "Uppgifterombilen", "kind": "formFile", "key": "VKSKROTBIL_10", "control": "fileUploadControl"]],
            questions: [
                question("vehicleType", "text", "Typ av fordon", suggestions: ["Personbil", "Husvagn"], maxLength: 30, translate: true),
                question("registration", "text", "Registreringsnummer", suggestions: ["Saknas"], maxLength: 20),
            ],
            tiles: [["id": "t-car", "questionIDs": ["vehicleType", "registration"]]],
            validation: ["descriptionMin": 0, "descriptionMax": 1000, "descriptionRequired": false,
                         "emailRequiredWhenFeedback": false, "requireLocation": true, "photoRequired": false],
            extra: ["descriptionTitle": text("Övrigt", "Anything else?")]
        )
    }

    /// Like invasivaarter: a required description, a map answer, no place field.
    static func invasiveJSON() throws -> [String: Any] {
        try form(
            id: "test.invasiva", service: "Invasiva växter", order: 3, category: "nature",
            pages: [["id": "newpage", "stage": "sendingReport", "fields": [
                field("answer", "invasivaarter_13", question: "species"),
                field("description", "invasivaarter_6", type: "textarea"),
                field("mapAnswer", "invasivaarter_11", "MapAnswer", type: "hidden"),
                field("answer", "invasivaarter_7", "radioButtonListFieldControl", type: "radio", question: "amount"),
            ]]],
            uploads: [["pageID": "newpage", "kind": "formFile", "key": "invasivaarter_8", "control": "fileUploadControl"]],
            questions: [
                question("species", "text", "Vilken växt?", suggestions: ["Blomsterlupin"]),
                question("amount", "choice", "Är det enstaka växter eller ett större bestånd?", options: ["Större bestånd", "Enstaka växter"]),
            ],
            tiles: [["id": "t-invasive", "questionIDs": ["species", "amount"]]],
            validation: ["descriptionMin": 10, "descriptionMax": 4000, "descriptionRequired": true,
                         "emailRequiredWhenFeedback": false, "requireLocation": true, "photoRequired": false]
        )
    }

    static func spec(_ json: [String: Any]) throws -> AdapterSpec {
        try AdapterCatalog.decode(try JSONSerialization.data(withJSONObject: json))
    }

    /// 2026-11-19 10:00 Stockholm.
    static let visited = "2026-11-19T10:00:00+01:00"
    static let now = ISO8601DateFormatter().date(from: "2026-11-19T11:00:00+01:00")!
}

final class ValidatorFormsTests: XCTestCase {
    private typealias F = FormsFixtures

    func testFelaterEmptyDraftAsksQuestionsAndPhotoOnly() throws {
        let spec = try F.spec(F.felaterJSON())
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-clean")
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [
            .init(field: .question, code: .missing, questionID: "station"),
            .init(field: .question, code: .missing, questionID: "cleanWhat"),
            .init(field: .question, code: .missing, questionID: "visited"),
            .init(field: .photo, code: .missing),
        ], "no category or description issue: the form has neither field")
    }

    func testFelaterCompleteDraftIsValid() throws {
        let spec = try F.spec(F.felaterJSON())
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-empty", photoJPEG: Data([1]), answers: [
            "station": ["780006, Hemmesta"], "emptyWhat": ["Batterier", "Glasförpackningar"], "visited": [F.visited],
            "cleanWhat": ["not asked on this tile"],
        ])
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [])
    }

    func testChoiceOutsideOptionsIsInvalid() throws {
        let spec = try F.spec(F.felaterJSON())
        var draft = ReportDraft(adapterID: spec.id, tileID: "t-clean", photoJPEG: Data([1]), answers: [
            "station": ["Nowhere"], "cleanWhat": ["Batterier", "Glass"], "visited": [F.visited],
        ])
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [
            .init(field: .question, code: .invalidFormat, questionID: "station"),
            .init(field: .question, code: .invalidFormat, questionID: "cleanWhat"),
        ])
        draft.answers["station"] = ["  "]
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now).first,
                       .init(field: .question, code: .missing, questionID: "station"), "blank counts as missing")
    }

    func testDateTimeMustParseAndNotLieInTheFuture() throws {
        let spec = try F.spec(F.felaterJSON())
        func issues(_ visited: String) -> [ValidationIssue] {
            ReportValidator.validate(ReportDraft(adapterID: spec.id, tileID: "t-clean", photoJPEG: Data([1]), answers: [
                "station": ["780006, Hemmesta"], "cleanWhat": ["Batterier"], "visited": [visited],
            ]), spec: spec, now: F.now)
        }
        let bad = [ValidationIssue(field: .question, code: .invalidFormat, questionID: "visited")]
        XCTAssertEqual(issues("igår"), bad)
        XCTAssertEqual(issues("2026-11-19T11:10:00+01:00"), bad, "10 minutes ahead")
        XCTAssertEqual(issues("2026-11-19T11:04:00+01:00"), [], "within the 5-minute tolerance")
        XCTAssertEqual(issues("2026-11-19T10:04:00Z"), [], "any offset parses")
    }

    func testRequiredEmailAndTextLength() throws {
        let spec = try F.spec(F.anmutbsopJSON())
        var draft = ReportDraft(adapterID: spec.id, tileID: "t-bins", answers: [
            "address": [String(repeating: "a", count: 201)], "missed": ["Matavfall"],
        ])
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [
            .init(field: .question, code: .tooLong, questionID: "address"),
            .init(field: .email, code: .missing),
        ])
        draft.answers["address"] = ["Skogsbovägen 9"]
        draft.contact.email = "namn@example.se"
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [])
        draft.contact.email = "namn@"
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [.init(field: .email, code: .invalidFormat)])
    }

    func testEmailRequiredNeedsAnEmailField() throws {
        var json = try F.felaterJSON()
        var validation = try XCTUnwrap(json["validation"] as? [String: Any])
        validation["emailRequired"] = true
        json["validation"] = validation
        let spec = try F.spec(json)
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-clean", photoJPEG: Data([1]), answers: [
            "station": ["780006, Hemmesta"], "cleanWhat": ["Batterier"], "visited": [F.visited],
        ])
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [])
    }

    func testOptionalDescriptionStillHasAMaximum() throws {
        let spec = try F.spec(F.vkskrotbilJSON())
        var draft = ReportDraft(adapterID: spec.id, tileID: "t-car", locationText: "Skogsbovägen 9", answers: [
            "vehicleType": ["Personbil"], "registration": ["ABC 123"],
        ])
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [], "empty optional description is fine")
        draft.description = "Ja"
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [], "no minimum when optional")
        draft.description = String(repeating: "a", count: 1001)
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [.init(field: .description, code: .tooLong)])
    }

    func testIssueOrderAcrossAllFields() throws {
        let spec = try F.spec(F.vkskrotbilJSON())
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-car", description: String(repeating: "a", count: 1001),
                                contact: Contact(phone: "x", email: "y"), answers: ["registration": [String(repeating: "A", count: 21)]])
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [
            .init(field: .question, code: .missing, questionID: "vehicleType"),
            .init(field: .question, code: .tooLong, questionID: "registration"),
            .init(field: .description, code: .tooLong),
            .init(field: .location, code: .missing),
            .init(field: .email, code: .invalidFormat),
            .init(field: .phone, code: .invalidFormat),
        ])
    }

    func testRequiredDescriptionKeepsItsMinimum() throws {
        let spec = try F.spec(F.invasiveJSON())
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-invasive", description: "Ja", locationText: "Ekvägen 3",
                                answers: ["species": ["Blomsterlupin"], "amount": ["Större bestånd"]])
        XCTAssertEqual(ReportValidator.validate(draft, spec: spec, now: F.now), [.init(field: .description, code: .tooShort)])
    }

    func testKSBUnchanged() throws {
        let spec = try F.ksb()
        let tile = try XCTUnwrap(spec.tiles.first)
        XCTAssertEqual(ReportValidator.validate(ReportDraft(adapterID: spec.id), spec: spec, now: F.now), [
            .init(field: .category, code: .missing),
            .init(field: .description, code: .missing),
            .init(field: .location, code: .missing),
        ].filter { $0.field != .location || spec.validation.requireLocation })
        let ok = ReportDraft(adapterID: spec.id, tileID: tile.id, description: "Lampan blinkar hela natten",
                             coordinate: spec.municipality.region.center)
        XCTAssertEqual(ReportValidator.validate(ok, spec: spec, now: F.now), [])
    }
}
