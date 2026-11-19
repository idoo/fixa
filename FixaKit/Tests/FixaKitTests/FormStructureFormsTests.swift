import Foundation
import XCTest
@testable import FixaKit

/// FormStructure on the captured pages of the Värmdö e-services beyond KSB.
final class FormStructureFormsTests: XCTestCase {
    private func form(_ service: String, _ page: String) throws -> FormStructure {
        let url = try XCTUnwrap(Bundle.module.url(forResource: page, withExtension: "html", subdirectory: "Fixtures/forms/\(service)"))
        return FormStructure(html: String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }

    private func control(_ form: FormStructure, _ key: String) throws -> FormControl {
        try XCTUnwrap(form.controls.first { $0.key == key }, key)
    }

    private func field(_ role: String, _ key: String, _ control: String, _ type: String, label: String) throws -> AdapterSpec.FieldSpec {
        let json = #"{"role":"\#(role)","key":"\#(key)","control":"\#(control)","type":"\#(type)","labels":{"sv":["\#(label)"]}}"#
        return try JSONDecoder().decode(AdapterSpec.FieldSpec.self, from: Data(json.utf8))
    }

    func testFelaterCheckboxListsAreOneControlEach() throws {
        let page = try form("felater", "01-page")
        XCTAssertEqual(try control(page, "FELATER_1").options.count, 24)
        XCTAssertEqual(try control(page, "FELATER_1").type, "select")

        let action = try control(page, "FELATER_2")
        XCTAssertEqual(action.control, "checkBoxListFieldControl")
        XCTAssertEqual(action.type, "checkbox")
        XCTAssertTrue(action.name.hasSuffix("$FELATER_2_field$checkBoxListFieldControl"))
        XCTAssertEqual(action.options.map(\.value), ["Städning", "Extra tömning"])
        XCTAssertEqual(action.options.map(\.text), ["Städning", "Extra tömning"])
        XCTAssertEqual(action.options.compactMap(\.inputName).map { String($0.suffix(2)) }, ["$0", "$1"])
        XCTAssertEqual(page.controls.filter { $0.key == "FELATER_2" }.count, 1)

        XCTAssertEqual(try control(page, "FELATER_3").options.count, 8)
        XCTAssertEqual(try control(page, "FELATER_4").options.count, 7)
        XCTAssertTrue(try control(page, "FELATER_3").options.allSatisfy { $0.inputName != nil })
    }

    func testFelaterListResolvesByKeyAndByLegend() throws {
        let page = try form("felater", "01-page")
        let exact = try field("answer", "FELATER_2", "checkBoxListFieldControl", "checkbox", label: "Vad bör göras?")
        XCTAssertEqual(page.control(for: exact)?.key, "FELATER_2")
        let drifted = try field("answer", "FELATER_99", "checkBoxListFieldControl", "checkbox", label: "Vad behöver städas?")
        XCTAssertEqual(page.control(for: drifted)?.key, "FELATER_3")
        XCTAssertTrue(page.questions.contains { $0.label == "Vad bör göras?" && $0.required && $0.controls.map(\.key) == ["FELATER_2"] })
    }

    func testFelaterActivationRules() throws {
        let page = try form("felater", "01-page")
        let cleaning = page.inactiveKeys(posting: ["FELATER_2": ["Städning"]])
        XCTAssertTrue(cleaning.isSuperset(of: ["FELATER_4", "FELATER_6"]))
        XCTAssertTrue(cleaning.isDisjoint(with: ["FELATER_3", "FELATER_5", "FELATER_15"]))

        let both = page.inactiveKeys(posting: ["FELATER_2": ["Städning", "Extra tömning"]])
        XCTAssertTrue(both.isDisjoint(with: ["FELATER_3", "FELATER_4", "FELATER_5", "FELATER_6"]))

        XCTAssertTrue(page.inactiveKeys(posting: [:]).isSuperset(of: ["FELATER_3", "FELATER_4", "FELATER_5", "FELATER_6", "FELATER_15"]))
    }

    func testFelaterUnfilledRequiredHonoursListsAndHiddenBlocks() throws {
        let page = try form("felater", "01-page")
        let inactive = page.inactiveKeys(posting: ["FELATER_2": ["Städning"]])
        let action = try control(page, "FELATER_2"), clean = try control(page, "FELATER_3")
        let filled: Set<String> = [
            try control(page, "FELATER_1").name,
            try XCTUnwrap(action.options.first { $0.value == "Städning" }?.inputName),
            try XCTUnwrap(clean.options.first?.inputName),
            try control(page, "FELATER_5").name,
        ]
        XCTAssertEqual(page.unfilledRequired(filled: filled, inactive: inactive), [])
        XCTAssertTrue(page.unfilledRequired(filled: []).contains("Vad bör göras?"))
    }

    func testAnmutbsopRequiredQuestions() throws {
        let page = try form("anmutbsop", "01-dinauppgifter")
        XCTAssertEqual(page.questions.filter(\.required).map(\.label), ["Hämtadress", "E-post", "Vad har inte hämtats"])
    }

    func testVkskrotbilFieldPageLayout() throws {
        let page = try form("vkskrotbil", "01-uppgifterombilen")
        for n in 1...9 { XCTAssertNoThrow(try control(page, "VKSKROTBIL_\(n)")) }
        XCTAssertEqual(try control(page, "VKSKROTBIL_10").control, "fileUploadControl")

        let label = { (key: String) in page.questions.first { $0.controls.contains { $0.key == key } }?.label }
        XCTAssertEqual(label("VKSKROTBIL_5"), "Var står fordonet?")
        XCTAssertEqual(label("VKSKROTBIL_1"), "Typ av fordon (ex personbil)")
        XCTAssertEqual(label("VKSKROTBIL_9"), "Övrig information")

        let required = page.questions.filter(\.required).flatMap { $0.controls.map(\.key) }
        XCTAssertEqual(required, (1...5).map { "VKSKROTBIL_\($0)" })

        let drifted = try field("place", "VKSKROTBIL_55", "textFieldControl", "text", label: "Var står fordonet?")
        XCTAssertEqual(page.control(for: drifted)?.key, "VKSKROTBIL_5")
    }

    func testVkskrotbilValidationPageAgrees() throws {
        let page = try form("vkskrotbil", "02-uppgifterombilen-validation")
        let required = page.questions.filter(\.required).flatMap { $0.controls.map(\.key) }
        XCTAssertEqual(required, (1...5).map { "VKSKROTBIL_\($0)" })
    }
}
