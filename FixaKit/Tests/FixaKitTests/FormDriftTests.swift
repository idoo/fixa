import Foundation
import XCTest
@testable import FixaKit

/// Replays the saved Värmdö pages with in-code edits, as if the municipality had changed its e-service.
actor MutatedAbou: HTTPTransport {
    let faultID: String
    let mutateFault: @Sendable (String) -> String
    let mutateContact: @Sendable (String) -> String
    let afterFault: String?
    private(set) var requests: [URLRequest] = []

    init(
        faultID: String = "FaultReport",
        afterFault: String? = nil,
        fault: @escaping @Sendable (String) -> String = { $0 },
        contact: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.faultID = faultID
        self.afterFault = afterFault
        self.mutateFault = fault
        self.mutateContact = contact
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!.absoluteString
        let common = "\(base)/EServices/Common/"
        func respond(_ html: String, _ at: String) -> (Data, HTTPURLResponse) {
            (Data(html.utf8), HTTPURLResponse(url: URL(string: at)!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let faultAt = "\(common)BlockPage.aspx?eServiceName=KSB&PageId=\(faultID)"
        switch (request.httpMethod ?? "GET", url) {
        case ("GET", "\(base)/KSB"):
            return respond(try fixture("01-intro"), url)
        case ("GET", _) where url.contains("Setup.aspx"):
            let html = mutateFault(try fixture("02-faultreport")).replacingOccurrences(of: "PageId=FaultReport", with: "PageId=\(faultID)")
            return respond(html, faultAt)
        case ("POST", _) where url.contains("PageId=\(faultID)"):
            if let afterFault { return respond(afterFault, "\(common)BlockPage.aspx?eServiceName=KSB&PageId=Survey") }
            return respond(mutateContact(try fixture("04-contact")), "\(common)BlockPage.aspx?eServiceName=KSB&PageId=PersonalEmailInformation")
        case ("POST", _) where url.contains("PageId=PersonalEmailInformation"):
            return respond(try fixture("05-summary"), "\(common)Summary.aspx?eServiceName=KSB&PageId=SummaryPage")
        case ("POST", _) where url.contains("PageId=SummaryPage"):
            return respond("<html><head><title>Kvittens</title></head><body><main><p>Ärendenummer: KSB-123456</p></main></body></html>", "\(common)Receipt.aspx?eServiceName=KSB")
        default:
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
    }

    /// Posted fields of the first POST whose URL contains `marker`.
    func posted(_ marker: String) -> [String: String] {
        formFields(requests.first { $0.httpMethod == "POST" && $0.url!.absoluteString.contains(marker) }?.httpBody)
    }
}

func field(_ fields: [String: String], key: String) -> String? {
    fields.first { $0.key.contains("$\(key)_field$") }?.value
}

/// A required text question Värmdö might add, in Abou's markup.
let newRequiredBlock = """
<div class="row"><div class="col-sm-12 field_container_77"><div class="field-row-block row egovtextfield">
<div class="field-question-block col-xs-12">
<label for="new_KSB_77"><span>Fastighetsbeteckning</span>
<span class="required-label">*</span></label>
</div><div class="field-input col-xs-12">
<input name="ctl00$ctl00$LeftAndMainSection$MainSection$ServiceSection$ServicePageFieldsSection$PageFields1$ctl00$BlockRepeater$ctl09$ctl02$KSB_77_field$textFieldControl" type="text" id="new_KSB_77" class="form-control" />
</div></div></div></div>
"""
let descriptionAnchor = #"<div class="row"><div class="col-sm-12 field_container_29.1.1">"#

final class FormDriftTests: XCTestCase {
    func submit(_ fake: MutatedAbou, _ draft: ReportDraft = validDraft(), dryRun: Bool = true) async throws -> SubmissionReceipt? {
        try await AbouSubmitter(spec: try varmdoSpec(), transport: fake, pageDelay: .zero).submit(draft, dryRun: dryRun)
    }

    func expectDrift(_ fake: MutatedAbou, _ draft: ReportDraft = validDraft()) async throws -> FormDrift {
        do {
            _ = try await submit(fake, draft)
        } catch SubmissionError.formChanged(let drift) {
            return drift
        }
        XCTFail("expected .formChanged")
        return FormDrift(pageID: nil, missing: [], detail: "")
    }

    func testStructureOfSavedPages() throws {
        let fault = FormStructure(html: try fixture("02-faultreport"))
        XCTAssertEqual(fault.questions.filter(\.required).map(\.label), ["Välj område", "Beskriv felet här", "Jag vill ha återkoppling"])
        let category = try XCTUnwrap(fault.controls.first { $0.key == "KSB_14" })
        XCTAssertEqual(category.type, "select")
        XCTAssertEqual(category.options.count, 7)
        let feedback = try XCTUnwrap(fault.controls.first { $0.key == "KSB_54" })
        XCTAssertEqual(feedback.type, "radio")
        XCTAssertEqual(feedback.options.map(\.text), ["Ja", "Nej"])
        XCTAssertEqual(fault.controls.first { $0.key == "U_29_1_1" }?.type, "textarea")
        XCTAssertEqual(fault.controls.first { $0.key == "KSB_19" }?.type, "hidden")
        XCTAssertEqual(FormStructure(html: try fixture("04-contact")).questions.map(\.label), ["Förnamn:", "Efternamn:", "Telefon:", "E-post:"])
        XCTAssertEqual(FormStructure.normalize(" Beskriv  felet HÄR * "), "beskriv felet har")
    }

    func testRenamedKeysResolveByLabel() async throws {
        let fake = MutatedAbou(
            fault: {
                $0.replacingOccurrences(of: "KSB_14_field", with: "KSB_99_field")
                    .replacingOccurrences(of: "U_29_1_1_field", with: "U_40_1_1_field")
                    .replacingOccurrences(of: "<span>Beskriv felet här</span>", with: "<span>BESKRIV  FELET HAR:</span>")
                    .replacingOccurrences(of: "KSB_18_field$textFieldControl", with: "KSB_18_field$textBoxControl")
            },
            contact: { $0.replacingOccurrences(of: "U_29_3_1_field", with: "U_29_9_1_field") }
        )
        _ = try await submit(fake)
        let report = await fake.posted("PageId=FaultReport")
        XCTAssertEqual(field(report, key: "KSB_99"), "Belysning")
        XCTAssertEqual(field(report, key: "U_40_1_1"), "Gatubelysning ur funktion\n\nLampan vid busshållplatsen är släckt sedan i måndags.")
        XCTAssertEqual(field(report, key: "KSB_18"), "Gustavsbergs centrum (59.3262, 18.3856)")
        XCTAssertNil(field(report, key: "KSB_14"))
        XCTAssertNil(field(report, key: "U_29_1_1"))
        let contact = await fake.posted("PageId=PersonalEmailInformation")
        XCTAssertEqual(field(contact, key: "U_29_9_1"), "anna@example.se")
    }

    func testRenamedOptionValuesResolveByTextAndSynonyms() async throws {
        // Value changed, text kept: resolved by visible text. Radio value changed: by its label.
        let byText = MutatedAbou(fault: {
            $0.replacingOccurrences(of: #"<option value="Belysning">"#, with: #"<option value="BEL-01">"#)
                .replacingOccurrences(of: #"value="Ja" /"#, with: #"value="1" /"#)
        })
        _ = try await submit(byText)
        let report = await byText.posted("PageId=FaultReport")
        XCTAssertEqual(field(report, key: "KSB_14"), "BEL-01")
        XCTAssertEqual(field(report, key: "KSB_54"), "1")

        // Value and text both renamed to a configured synonym.
        let bySynonym = MutatedAbou(fault: {
            $0.replacingOccurrences(of: #"<option value="Belysning">Belysning</option>"#, with: #"<option value="Gatubelysning">Gatubelysning</option>"#)
        })
        _ = try await submit(bySynonym)
        let synonymReport = await bySynonym.posted("PageId=FaultReport")
        XCTAssertEqual(field(synonymReport, key: "KSB_14"), "Gatubelysning")
    }

    func testReorderedOptions() async throws {
        let fake = MutatedAbou(fault: {
            $0.replacingOccurrences(of: "<option value=\"Övrigt\">&#214;vrigt</option>", with: "")
                .replacingOccurrences(of: #"<option value="Belysning">"#, with: "<option value=\"Övrigt\">&#214;vrigt</option><option value=\"Belysning\">")
        })
        var draft = validDraft()
        draft.tileID = "other"
        _ = try await submit(fake, draft)
        let report = await fake.posted("PageId=FaultReport")
        XCTAssertEqual(field(report, key: "KSB_14"), "Övrigt")
        XCTAssertEqual(FormStructure(html: try fixture("02-faultreport")).controls.first { $0.key == "KSB_14" }?.options.count, 7)
    }

    func testRenamedPageIDIsFoundByItsFields() async throws {
        let fake = MutatedAbou(faultID: "Felanmalan")
        let receipt = try await submit(fake, dryRun: false)
        XCTAssertEqual(receipt?.caseNumber, "KSB-123456")
        let report = await fake.posted("PageId=Felanmalan")
        XCTAssertEqual(field(report, key: "KSB_14"), "Belysning")
        XCTAssertEqual(field(report, key: "KSB_54"), "Ja")
    }

    func testNewRequiredFieldIsDrift() async throws {
        let fake = MutatedAbou(fault: { $0.replacingOccurrences(of: descriptionAnchor, with: newRequiredBlock + descriptionAnchor) })
        let drift = try await expectDrift(fake)
        XCTAssertEqual(drift.pageID, "FaultReport")
        XCTAssertEqual(drift.missing, ["Fastighetsbeteckning"])
        let posts = await fake.requests.filter { $0.httpMethod == "POST" }
        XCTAssertTrue(posts.isEmpty, "a page with an unfilled required field must not be posted")
    }

    func testNewRequiredFieldOnRenamedPageIsDrift() async throws {
        let fake = MutatedAbou(faultID: "Felanmalan2", fault: { $0.replacingOccurrences(of: descriptionAnchor, with: newRequiredBlock + descriptionAnchor) })
        let drift = try await expectDrift(fake)
        XCTAssertEqual(drift.missing, ["Fastighetsbeteckning"])
    }

    func testMissingDescriptionIsDrift() async throws {
        let fake = MutatedAbou(fault: {
            $0.replacingOccurrences(of: "U_29_1_1_field", with: "U_31_1_1_field")
                .replacingOccurrences(of: "<span>Beskriv felet här</span>", with: "<span>Vad har hänt?</span>")
        })
        let drift = try await expectDrift(fake)
        XCTAssertEqual(drift.pageID, "FaultReport")
        XCTAssertEqual(drift.missing, ["Beskriv felet här", "Vad har hänt?"])
        XCTAssertTrue(drift.report.contains("Beskriv felet här"), drift.report)
    }

    func testUnknownOptionIsDrift() async throws {
        let fake = MutatedAbou(fault: {
            $0.replacingOccurrences(of: #"<option value="Belysning">Belysning</option>"#, with: #"<option value="Lampor">Lampor</option>"#)
        })
        let drift = try await expectDrift(fake)
        XCTAssertEqual(drift.missing, ["Välj område: Belysning"])
    }

    func testUnknownPageWithRequiredFieldIsDrift() async throws {
        let survey = """
        <html><body><form method="post" action="./BlockPage.aspx?eServiceName=KSB&amp;PageId=Survey" id="MainForm">
        <input type="hidden" name="__VIEWSTATE" value="x" />
        <fieldset><legend class="field-question-block"><span>Hur nöjd är du?</span><span class="required-label">*</span></legend>
        <div class="field-input"><input id="s1" type="radio" name="ctl00$KSB_88_field$radioButtonListFieldControl" value="5" /><label for="s1">Mycket</label></div></fieldset>
        </form></body></html>
        """
        let drift = try await expectDrift(MutatedAbou(afterFault: survey))
        XCTAssertEqual(drift.pageID, "Survey")
        XCTAssertEqual(drift.missing, ["Hur nöjd är du?"])
    }
}
