import XCTest
@testable import FixaKit

final class ComposerFormsTests: XCTestCase {
    private typealias F = FormsFixtures

    func testPlatsLineWhenTheFormHasNoPlaceField() throws {
        let spec = try F.spec(F.invasiveJSON())
        var draft = ReportDraft(adapterID: spec.id, tileID: "t-invasive", description: "Bakom röda huset vid stranden",
                                locationText: "Ekvägen 3")
        XCTAssertEqual(ReportComposer.description(for: draft, spec: spec, now: F.now),
                       "Bakom röda huset vid stranden\n\nPlats: Ekvägen 3")
        draft.coordinate = Coordinate(latitude: 59.3262123, longitude: 18.3856)
        XCTAssertEqual(ReportComposer.description(for: draft, spec: spec, now: F.now),
                       "Bakom röda huset vid stranden\n\nPlats: Ekvägen 3 (59.32621, 18.3856)")
        draft.locationText = ""
        draft.coordinate = nil
        XCTAssertEqual(ReportComposer.description(for: draft, spec: spec, now: F.now), "Bakom röda huset vid stranden")
    }

    func testPlatsLineIsNeverCut() throws {
        var json = try F.invasiveJSON()
        var validation = try XCTUnwrap(json["validation"] as? [String: Any])
        validation["descriptionMax"] = 40
        json["validation"] = validation
        let spec = try F.spec(json)
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-invasive",
                                description: String(repeating: "lupiner ", count: 10), locationText: "Ekvägen 3")
        let text = ReportComposer.description(for: draft, spec: spec, now: F.now)
        XCTAssertTrue(text.hasSuffix("\n\nPlats: Ekvägen 3"), text)
        XCTAssertLessThanOrEqual(text.count, 40)
    }

    func testNoPlatsLineWhenTheFormHasAPlaceField() throws {
        let spec = try F.spec(F.vkskrotbilJSON())
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-car", description: "Står sedan i somras",
                                locationText: "Skogsbovägen 9")
        XCTAssertEqual(ReportComposer.description(for: draft, spec: spec, now: F.now), "Står sedan i somras")
    }

    func testFiledTextWithAnswersOnly() throws {
        let spec = try F.spec(F.felaterJSON())
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-clean", answers: [
            "station": ["780006, Hemmesta"], "cleanWhat": ["Batterier", "Tidningar"], "visited": [F.visited],
            "emptyWhat": ["Batterier"],
        ])
        XCTAssertEqual(ReportComposer.filedText(for: draft, spec: spec, now: F.now), """
        Vilken station?: 780006, Hemmesta
        Vad behöver städas?: Batterier, Tidningar
        När var du där?: 2026-11-19 10:00
        Vad bör göras?: Städning
        """)
    }

    func testFiledTextWithPlaceAndDescription() throws {
        let spec = try F.spec(F.vkskrotbilJSON())
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-car", description: "Står sedan i somras",
                                locationText: "Skogsbovägen 9", answers: ["vehicleType": ["Husvagn"], "registration": [" "]])
        XCTAssertEqual(ReportComposer.filedText(for: draft, spec: spec, now: F.now), """
        Typ av fordon: Husvagn
        Plats: Skogsbovägen 9

        Beskrivning:
        Står sedan i somras
        """)
    }

    func testFiledTextPlatsWhenAPlaceWasGivenWithoutAPlaceField() throws {
        let spec = try F.spec(F.anmutbsopJSON())
        var draft = ReportDraft(adapterID: spec.id, tileID: "t-bins", answers: ["missed": ["Båda"]])
        XCTAssertEqual(ReportComposer.filedText(for: draft, spec: spec, now: F.now), "Vad har inte hämtats: Båda")
        draft.locationText = "Skogsbovägen 9"
        XCTAssertEqual(ReportComposer.filedText(for: draft, spec: spec, now: F.now),
                       "Vad har inte hämtats: Båda\nPlats: Skogsbovägen 9")
    }

    func testKSBFiledTextUnchanged() throws {
        let spec = try F.ksb()
        let tile = try XCTUnwrap(spec.tiles.first)
        let draft = ReportDraft(adapterID: spec.id, tileID: tile.id, description: "Lampan blinkar")
        let description = ReportComposer.description(for: draft, spec: spec, now: F.now)
        XCTAssertEqual(ReportComposer.filedText(for: draft, spec: spec, now: F.now), """
        Område: \(spec.category(for: draft)?.value ?? "-")
        Plats: -

        Beskrivning:
        \(description)
        """)
        XCTAssertFalse(description.contains("Plats:"))
    }

    func testWebFallbackContactLinesWithoutFeedbackField() throws {
        let spec = try F.spec(F.anmutbsopJSON())
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-bins",
                                contact: Contact(firstName: "Anna", lastName: "Berg", phone: "070-123 45 67", email: "anna@example.se"),
                                answers: ["address": ["Skogsbovägen 9"], "missed": ["Matavfall"]])
        XCTAssertEqual(WebFallback.text(draft, spec: spec, now: F.now), """
        Hämtadress: Skogsbovägen 9
        Vad har inte hämtats: Matavfall

        Namn: Anna Berg
        Telefon: 070-123 45 67
        E-post: anna@example.se
        """)
    }

    func testWebFallbackOnlyNamesFieldsTheFormHas() throws {
        let spec = try F.spec(F.felaterJSON())
        let draft = ReportDraft(adapterID: spec.id, tileID: "t-empty",
                                contact: Contact(firstName: "Anna", lastName: "Berg", phone: "070-123 45 67", email: "anna@example.se"),
                                answers: ["station": ["780006, Hemmesta"], "emptyWhat": ["Batterier"], "visited": [F.visited]])
        XCTAssertEqual(WebFallback.text(draft, spec: spec, now: F.now), """
        Vilken station?: 780006, Hemmesta
        Vad behöver tömmas?: Batterier
        När var du där?: 2026-11-19 10:00
        Vad bör göras?: Extra tömning

        Namn: Anna Berg
        """)
    }

    func testKSBWebFallbackStillNeedsFeedbackForContact() throws {
        let spec = try F.ksb()
        let tile = try XCTUnwrap(spec.tiles.first)
        var draft = ReportDraft(adapterID: spec.id, tileID: tile.id, description: "Lampan blinkar",
                                contact: Contact(firstName: "Anna", phone: "070-123 45 67", email: "anna@example.se"))
        let filed = ReportComposer.filedText(for: draft, spec: spec, now: F.now)
        XCTAssertEqual(WebFallback.text(draft, spec: spec, now: F.now), filed)
        draft.wantsFeedback = true
        XCTAssertEqual(WebFallback.text(draft, spec: spec, now: F.now),
                       filed + "\n\nJag vill ha återkoppling.\nNamn: Anna\nTelefon: 070-123 45 67\nE-post: anna@example.se")
    }
}
