import XCTest
@testable import FixaKit

final class AdapterFormsProblemsTests: XCTestCase {
    private typealias F = FormsFixtures

    private func problems(_ json: [String: Any], _ edit: (inout [String: Any]) throws -> Void) throws -> [String] {
        var json = json
        try edit(&json)
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AdapterSpec.self, from: data).problems
    }

    private func editPage(_ json: inout [String: Any], _ edit: (inout [[String: Any]]) -> Void) throws {
        var channel = try XCTUnwrap(json["channel"] as? [String: Any])
        var pages = try XCTUnwrap(channel["pages"] as? [[String: Any]])
        var fields = try XCTUnwrap(pages[0]["fields"] as? [[String: Any]])
        edit(&fields)
        pages[0]["fields"] = fields
        channel["pages"] = pages
        json["channel"] = channel
    }

    private func editQuestions(_ json: inout [String: Any], _ edit: (inout [[String: Any]]) -> Void) throws {
        var questions = try XCTUnwrap(json["questions"] as? [[String: Any]])
        edit(&questions)
        json["questions"] = questions
    }

    private func editTile(_ json: inout [String: Any], _ edit: (inout [String: Any]) -> Void) throws {
        var tiles = try XCTUnwrap(json["tiles"] as? [[String: Any]])
        edit(&tiles[0])
        json["tiles"] = tiles
    }

    func testFormFixturesHaveNoProblems() throws {
        for json in [try F.felaterJSON(), try F.anmutbsopJSON(), try F.vkskrotbilJSON(), try F.invasiveJSON()] {
            XCTAssertEqual(try problems(json) { _ in }, [], json["id"] as? String ?? "")
        }
    }

    func testCategoryAndDescriptionFieldsOnlyRequiredForPrimary() throws {
        XCTAssertEqual(try problems(F.felaterJSON()) { _ in }, [], "no category or description field is fine with a service")
        let primary = try problems(F.felaterJSON()) { $0["service"] = nil }
        XCTAssertTrue(primary.contains("no category field"), "\(primary)")
        XCTAssertTrue(primary.contains("no description field"), "\(primary)")
        XCTAssertTrue(try problems(F.felaterJSON()) { $0["categories"] = [] as [Any] }.contains("no categories"))
    }

    func testAnswerFieldNeedsAKnownQuestion() throws {
        let p = try problems(F.anmutbsopJSON()) { json in
            try editPage(&json) { $0.append(F.field("answer", "anmutbsop_11", question: "nope")) }
        }
        XCTAssertTrue(p.contains("answer field anmutbsop_11 has unknown question nope"), "\(p)")
        let missing = try problems(F.anmutbsopJSON()) { json in
            try editPage(&json) { $0.append(F.field("answer", "anmutbsop_12")) }
        }
        XCTAssertTrue(missing.contains("answer field anmutbsop_12 has unknown question -"), "\(missing)")
    }

    func testEveryQuestionIsSent() throws {
        let p = try problems(F.anmutbsopJSON()) { json in
            try editQuestions(&json) { $0.append(F.question("extra", "text", "Extra")) }
        }
        XCTAssertTrue(p.contains("question extra is not sent by any answer field"), "\(p)")
    }

    func testQuestionIdsAreUnique() throws {
        let p = try problems(F.anmutbsopJSON()) { json in
            try editQuestions(&json) { $0.append(F.question("missed", "text", "Igen")) }
        }
        XCTAssertTrue(p.contains("duplicate question id"), "\(p)")
    }

    func testChoicesNeedUniqueOptions() throws {
        let empty = try problems(F.anmutbsopJSON()) { json in
            try editQuestions(&json) { $0[1]["options"] = [] as [Any] }
        }
        XCTAssertTrue(empty.contains("question missed has no options"), "\(empty)")
        let absent = try problems(F.anmutbsopJSON()) { json in
            try editQuestions(&json) { $0[1]["options"] = nil }
        }
        XCTAssertTrue(absent.contains("question missed has no options"), "\(absent)")
        let duplicate = try problems(F.anmutbsopJSON()) { json in
            try editQuestions(&json) { $0[1]["options"] = [F.option("Båda"), F.option("Båda")] }
        }
        XCTAssertTrue(duplicate.contains("question missed has duplicate option values"), "\(duplicate)")
    }

    func testTileAnswersAndQuestionIDs() throws {
        let unknown = try problems(F.felaterJSON()) { json in
            try editTile(&json) { $0["answers"] = ["nope": ["x"]] }
        }
        XCTAssertTrue(unknown.contains("tile t-clean answers unknown question nope"), "\(unknown)")
        let badValue = try problems(F.felaterJSON()) { json in
            try editTile(&json) { $0["answers"] = ["action": ["Rivning"]] }
        }
        XCTAssertTrue(badValue.contains("tile t-clean answer Rivning is not an option of action"), "\(badValue)")
        let asks = try problems(F.felaterJSON()) { json in
            try editTile(&json) { $0["questionIDs"] = ["station", "ghost"] }
        }
        XCTAssertTrue(asks.contains("tile t-clean asks unknown question ghost"), "\(asks)")
    }

    func testUploadPageAndCondition() throws {
        let p = try problems(F.felaterJSON()) { json in
            var channel = try XCTUnwrap(json["channel"] as? [String: Any])
            var uploads = try XCTUnwrap(channel["uploads"] as? [[String: Any]])
            uploads[0]["pageID"] = "elsewhere"
            uploads[1]["when"] = ["question": "ghost", "value": "x"]
            channel["uploads"] = uploads
            json["channel"] = channel
        }
        XCTAssertTrue(p.contains("upload page elsewhere is not a page"), "\(p)")
        XCTAssertTrue(p.contains("upload on page depends on unknown question ghost"), "\(p)")
    }

    func testServiceTitleNeedsSwedishAndEnglish() throws {
        let p = try problems(F.felaterJSON()) { json in
            json["service"] = ["title": ["sv": "Återvinning", "en": " "], "symbol": "leaf"]
        }
        XCTAssertEqual(p, ["service title needs en"])
        let noSv = try problems(F.felaterJSON()) { json in
            json["service"] = ["title": ["en": "Recycling"], "symbol": "leaf"]
        }
        XCTAssertEqual(noSv, ["service title needs sv"])
    }

    func testTileLinkAdapterIDNotEmpty() throws {
        let link: [String: Any] = ["title": F.text("Återvinning"), "url": "https://www.varmdo.se/atervinning", "adapterID": ""]
        let p = try problems(F.felaterJSON()) { json in
            try editTile(&json) { $0["links"] = [link] }
        }
        XCTAssertEqual(p, ["tile t-clean link has an empty adapterID"])
        var good = link
        good["adapterID"] = "se.varmdo.felater"
        XCTAssertEqual(try problems(F.felaterJSON()) { json in try editTile(&json) { $0["links"] = [good] } }, [])
    }

    func testQuestionListSizes() throws {
        let many = (0...AdapterSpecValidator.maxCategories).map { "v\($0)" }
        let options = try problems(F.anmutbsopJSON()) { json in
            try editQuestions(&json) { $0[1]["options"] = many.map { F.option($0) } }
        }
        XCTAssertTrue(options.contains("a question has more than \(AdapterSpecValidator.maxCategories) options or suggestions"), "\(options)")
        let suggestions = try problems(F.anmutbsopJSON()) { json in
            try editQuestions(&json) { $0[0]["suggestions"] = many.map { F.option($0) } }
        }
        XCTAssertTrue(suggestions.contains("a question has more than \(AdapterSpecValidator.maxCategories) options or suggestions"))
        let questions = try problems(F.anmutbsopJSON()) { json in
            try editQuestions(&json) { $0 += many.map { F.question($0, "text", $0) } }
        }
        XCTAssertTrue(questions.contains("more than \(AdapterSpecValidator.maxCategories) questions"), "\(questions)")
    }

    func testKSBStillHasNoProblems() throws {
        XCTAssertEqual(try problems(F.ksbJSON()) { _ in }, [])
    }

    /// Every adapter file shipped in FixaKit decodes with no problems, and tile ids are unique across them
    /// (history and SendGuard key on tile id).
    func testBundledAdaptersDecodeWithUniqueTileIDs() throws {
        let urls = AdapterCatalog.bundledURLs().filter { $0.lastPathComponent.hasPrefix("se-") }
        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            XCTAssertNoThrow(try AdapterCatalog.load(from: url), url.lastPathComponent)
        }
        let bundled = AdapterCatalog.bundled()
        XCTAssertEqual(bundled.count, Set(urls.map(\.lastPathComponent)).count)
        XCTAssertEqual(bundled.filter(\.isPrimary).count, 1, "one adapter fills Home's grid")
        let tileIDs = bundled.flatMap { $0.tiles.map(\.id) }
        XCTAssertEqual(Set(tileIDs).count, tileIDs.count, "duplicate tile id across adapters: \(tileIDs)")
        let ids = Set(bundled.map(\.id))
        for spec in bundled {
            for link in spec.tiles.flatMap({ $0.links ?? [] }) {
                if let target = link.adapterID { XCTAssertTrue(ids.contains(target), "link to unknown adapter \(target)") }
            }
        }
    }
}
