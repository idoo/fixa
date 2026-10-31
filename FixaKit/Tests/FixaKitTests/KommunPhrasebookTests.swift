import Foundation
import XCTest
@testable import FixaKit

/// The kommun's Swedish, read into known sentences and an unknown remainder, from saved pages only.
final class KommunPhrasebookTests: XCTestCase {
    private let thankYouURL = URL(string: "\(base)/EServices/Common/ThankYou.aspx?eServiceName=KSB&PageId=ThankYou")!

    func testReceiptFixtureIsFullyKnownWithExactCaseNumber() throws {
        let receipt = try XCTUnwrap(AbouPageParser.parseReceipt(html: try fixture("09-thankyou-receipt"), url: thankYouURL, now: Date()))
        let reading = KommunPhrasebook.read(receipt.message)
        XCTAssertEqual(reading.phrases.map(\.id), [
            .thanksForUsingService, .caseNumber, .thanksForReport, .regards, .signature,
            .replyWithinWorkingDays, .longerHandlingTime,
        ])
        XCTAssertEqual(reading.unknown, [])
        XCTAssertEqual(reading.caseNumber, "261026-KSB-KS43")
        XCTAssertEqual(reading.caseNumber, receipt.caseNumber)
        XCTAssertEqual(reading.phrases.first { $0.id == .signature }?[.name], "Värmdö kommun")
        XCTAssertEqual(reading.phrases.first { $0.id == .replyWithinWorkingDays }?[.days], "5")
        // Two sentences on one line become two phrases on that line.
        XCTAssertEqual(reading.lines.count, 6)
        XCTAssertEqual(reading.lines.last?.count, 2)
        // Each phrase keeps the kommun's exact sentence.
        XCTAssertEqual(reading.phrases[1].original, "Här är ditt ärendenummer 261026-KSB-KS43")
    }

    func testProcessingFixture() throws {
        let text = try XCTUnwrap(AbouPageParser.receiptText(try fixture("08-thankyou-processing")))
        let reading = KommunPhrasebook.read(text)
        XCTAssertTrue(reading.phrases.contains { $0.id == .processing }, "\(reading)")
        XCTAssertNil(reading.caseNumber)
        XCTAssertEqual(reading.unknown, [])
    }

    func testValidationFixtureMessagesWithFieldRoles() throws {
        let fields = try varmdoSpec().channel.pages.flatMap(\.fields)
        let messages = AbouPageParser.validationErrors(try fixture("03-faultreport-validation"))
        let phrases = messages.map { KommunPhrasebook.read($0, fields: fields).phrases }
        XCTAssertEqual(phrases.map { $0.map(\.id) }, [[.chooseValue], [.fillIn], [.chooseValue]])
        XCTAssertEqual(phrases.map { $0.first?[.label] }, ["Välj område", "Beskriv felet här", "Jag vill ha återkoppling"])
        XCTAssertEqual(phrases.map { $0.first?[.role] }, ["category", "description", "feedback"])
        // Without the adapter the label still comes through, just with no role.
        let bare = KommunPhrasebook.read(messages[1]).phrases.first
        XCTAssertEqual(bare?[.label], "Beskriv felet här")
        XCTAssertNil(bare?[.role])
        // Curly quotes and an unknown field label.
        let curly = KommunPhrasebook.read("Fyll i fältet ‘Fastighetsbeteckning’", fields: fields).phrases.first
        XCTAssertEqual(curly?.id, .fillIn)
        XCTAssertEqual(curly?[.label], "Fastighetsbeteckning")
        XCTAssertNil(curly?[.role])
    }

    func testUnknownTextIsKeptAsRemainderInOrder() throws {
        let text = """
        Tack för din felanmälan! Planerat underhåll söndag 2 nov 20–22. Tjänsten är tillfälligt otillgänglig då.
        Kontakta Värmdö kommun
        Här är ditt ärendenummer 261026-KSB-KS43
        """
        let reading = KommunPhrasebook.read(text)
        XCTAssertEqual(reading.lines.count, 3)
        XCTAssertEqual(reading.lines[0], [
            .phrase(KommunPhrase(id: .thanksForReport, original: "Tack för din felanmälan!")),
            .unknown("Planerat underhåll söndag 2 nov 20–22. Tjänsten är tillfälligt otillgänglig då."),
        ])
        // A kommun name is a signature only right under the greeting.
        XCTAssertEqual(reading.lines[1], [.unknown("Kontakta Värmdö kommun")])
        XCTAssertEqual(reading.caseNumber, "261026-KSB-KS43")
        XCTAssertEqual(KommunPhrasebook.read("Något helt annat.").unknown, ["Något helt annat."])
        XCTAssertEqual(KommunPhrasebook.read("").lines, [])
    }

    func testCaseNumberIsExact() {
        XCTAssertEqual(KommunPhrasebook.read("Här är ditt ärendenummer\u{00A0} 261026-KSB-KS43").caseNumber, "261026-KSB-KS43")
        XCTAssertEqual(KommunPhrasebook.read("Ditt ärendenummer är KSB-2026-01234.").caseNumber, "KSB-2026-01234")
        // Lower case is not a case number the kommun gave; no digit is not one either.
        XCTAssertNil(KommunPhrasebook.read("Här är ditt ärendenummer ksb-12").caseNumber)
        XCTAssertNil(KommunPhrasebook.read("Här är ditt ärendenummer ABCD").caseNumber)
    }

    func testFiledTextIsWhatTheFormReceives() throws {
        let spec = try varmdoSpec()
        let d = validDraft()
        let filed = ReportComposer.filedText(for: d, spec: spec)
        XCTAssertTrue(filed.hasPrefix("Område: Belysning\nPlats: "))
        XCTAssertTrue(filed.hasSuffix(ReportComposer.description(for: d, spec: spec)))
        XCTAssertFalse(filed.contains(d.contact.email))
        XCTAssertTrue(WebFallback.text(d, spec: spec).hasPrefix(filed))
    }
}
