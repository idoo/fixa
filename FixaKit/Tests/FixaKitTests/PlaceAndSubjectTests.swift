import XCTest
@testable import FixaKit

/// Contact checks only for fields the form has, the place of forms without a place field, what makes a
/// report a repeat, and free-text answers sent with a Swedish translation.
final class PlaceAndSubjectTests: XCTestCase {
    private typealias F = FormsFixtures

    private func felater() throws -> AdapterSpec {
        var json = try F.felaterJSON()
        json["placeQuestion"] = "station"
        return try F.spec(json)
    }

    private func felaterDraft(station: String) -> ReportDraft {
        ReportDraft(adapterID: "test.felater", tileID: "t-clean", photoJPEG: Data([1]), answers: [
            "station": [station], "cleanWhat": ["Batterier"], "visited": [F.visited],
        ])
    }

    // MARK: Validator

    func testProfileContactTheFormDoesNotTakeNeverBlocks() throws {
        var draft = felaterDraft(station: "780006, Hemmesta")
        draft.contact = Contact(firstName: "Ivan", phone: "070-12", email: "a@b")
        draft.wantsFeedback = true
        XCTAssertEqual(ReportValidator.validate(draft, spec: try felater(), now: F.now), [])
    }

    func testKSBStillChecksEmailFormat() throws {
        let spec = try F.ksb()
        let tile = try XCTUnwrap(spec.tiles.first)
        let draft = ReportDraft(adapterID: spec.id, tileID: tile.id, description: "Lampan blinkar hela natten",
                                coordinate: spec.municipality.region.center, contact: Contact(email: "a@b"))
        XCTAssertTrue(ReportValidator.validate(draft, spec: spec, now: F.now).contains(.init(field: .email, code: .invalidFormat)))
    }

    // MARK: Place

    func testPlaceTextComesFromThePlaceQuestion() throws {
        let spec = try felater()
        var draft = felaterDraft(station: " 780006, Hemmesta ")
        XCTAssertEqual(spec.placeText(for: draft), "780006, Hemmesta")
        draft.locationText = "Vid containern"
        XCTAssertEqual(spec.placeText(for: draft), "Vid containern", "a typed place wins")
        XCTAssertEqual(try F.spec(F.felaterJSON()).placeText(for: felaterDraft(station: "780006, Hemmesta")), "",
                       "no placeQuestion, no place")
    }

    func testBundledFormsNameTheirPlaceQuestion() {
        XCTAssertEqual(AdapterCatalog.shipped(id: "se.varmdo.felater")?.placeQuestion, "station")
        XCTAssertEqual(AdapterCatalog.shipped(id: "se.varmdo.anmutbsop")?.placeQuestion, "address")
        XCTAssertNil(AdapterCatalog.shipped(id: "se.varmdo.ksb")?.placeQuestion)
    }

    func testUnknownPlaceQuestionIsAProblem() throws {
        var json = try F.felaterJSON()
        json["placeQuestion"] = "nowhere"
        let spec = try JSONDecoder().decode(AdapterSpec.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(spec.problems.contains("placeQuestion nowhere is not a question"))
    }

    // MARK: Repeat guard

    func testSameStationTwiceIsARepeat() throws {
        let spec = try felater()
        let first = SentRecord(felaterDraft(station: "780006, Hemmesta"), spec: spec, date: F.now.addingTimeInterval(-3600))
        XCTAssertEqual(first.locationText, "780006, Hemmesta")
        XCTAssertEqual(SendGuard.check(felaterDraft(station: "780006, Hemmesta"), spec: spec, history: [first], now: F.now),
                       .duplicate(previous: first.date, caseNumber: nil))
        XCTAssertEqual(SendGuard.check(felaterDraft(station: "780005, Gustavsberg centrum|Coop"), spec: spec, history: [first], now: F.now),
                       .ok, "another station")
        XCTAssertEqual(SendGuard.check(felaterDraft(station: "780006, Hemmesta"), spec: spec, history: [first], now: F.now,
                                       checksDuplicate: false), .ok, "rate limit only")
    }

    func testDifferentPlantAtOnePinIsNoRepeat() throws {
        let spec = try F.spec(F.invasiveJSON())
        let pin = spec.municipality.region.center
        func draft(_ species: String) -> ReportDraft {
            ReportDraft(adapterID: spec.id, tileID: "t-invasive", description: "Stort bestånd vid vägen", coordinate: pin,
                        answers: ["species": [species], "amount": ["Större bestånd"]])
        }
        let lupins = SentRecord(draft("Blomsterlupin"), spec: spec, date: F.now.addingTimeInterval(-3600))
        XCTAssertEqual(SendGuard.check(draft("Jättebjörnloka"), spec: spec, history: [lupins], now: F.now), .ok)
        XCTAssertEqual(SendGuard.check(draft(" blomsterlupin "), spec: spec, history: [lupins], now: F.now),
                       .duplicate(previous: lupins.date, caseNumber: nil))
    }

    func testRecordsWithoutSubjectStillMatch() throws {
        let spec = try F.spec(F.invasiveJSON())
        let pin = spec.municipality.region.center
        let old = SentRecord(date: F.now.addingTimeInterval(-3600), tileID: "t-invasive", coordinate: pin, locationText: "")
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-invasive", coordinate: pin, answers: ["species": ["Blomsterlupin"]])
        XCTAssertEqual(SendGuard.check(draft, spec: spec, history: [old], now: F.now), .duplicate(previous: old.date, caseNumber: nil))
    }

    func testKSBRecordHasNoSubject() throws {
        let spec = try F.ksb()
        let draft = ReportDraft(adapterID: spec.id, tileID: spec.tiles.first?.id, locationText: "Brunn")
        let record = SentRecord(draft, spec: spec, date: F.now)
        XCTAssertNil(record.subject)
        XCTAssertEqual(record.locationText, "Brunn")
    }

    func testOldSentRecordDecodesWithoutSubject() throws {
        let old = #"{"date":0,"tileID":"streetlight","locationText":"Brunn","caseNumber":"K-1"}"#
        let record = try JSONDecoder().decode(SentRecord.self, from: Data(old.utf8))
        XCTAssertNil(record.subject)
        XCTAssertEqual(record.caseNumber, "K-1")
    }

    // MARK: Translated answers

    func testTranslatedAnswerIsSentAsSwedishThenOriginal() throws {
        let spec = try F.spec(F.vkskrotbilJSON())
        var draft = ReportDraft(adapterID: spec.id, tileID: "t-car", locationText: "Skogsbovägen 9", answers: [
            "vehicleType": ["фургон"], "registration": ["ABC 123"],
        ])
        draft.translation = MachineTranslation(sourceLanguage: "ru", text: "", answers: ["vehicleType": "Skåpbil"])
        XCTAssertEqual(spec.answers(for: draft)["vehicleType"], ["Skåpbil (фургон)"])
        XCTAssertEqual(spec.answers(for: draft)["registration"], ["ABC 123"])
        let filed = ReportComposer.filedText(for: draft, spec: spec, now: F.now)
        XCTAssertTrue(filed.contains("Typ av fordon: Skåpbil (фургон)"), filed)
        XCTAssertFalse(filed.contains("Översatt"), "an empty description translation adds no block")
    }

    func testUnflaggedOrTooLongAnswerGoesAsTyped() throws {
        let spec = try F.spec(F.vkskrotbilJSON())
        var draft = ReportDraft(adapterID: spec.id, tileID: "t-car", locationText: "Skogsbovägen 9", answers: [
            "vehicleType": ["грузовой фургон с прицепом"], "registration": ["DOG 123"],
        ])
        // registration has no `translate`: a translation never reaches the form.
        draft.translation = MachineTranslation(sourceLanguage: "ru", text: "", answers: [
            "vehicleType": "Skåpbil med släpvagn", "registration": "HUND 123",
        ])
        XCTAssertEqual(spec.answers(for: draft)["registration"], ["DOG 123"])
        // "Skåpbil med släpvagn (грузовой фургон с прицепом)" passes maxLength 30: sent as typed.
        XCTAssertEqual(spec.answers(for: draft)["vehicleType"], ["грузовой фургон с прицепом"])
    }

    func testOldTranslationDecodesWithoutAnswers() throws {
        let old = #"{"sourceLanguage":"uk","text":"Lampan lyser inte"}"#
        XCTAssertNil(try JSONDecoder().decode(MachineTranslation.self, from: Data(old.utf8)).answers)
    }
}
