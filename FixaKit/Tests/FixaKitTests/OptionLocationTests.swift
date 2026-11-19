import XCTest
@testable import FixaKit

final class OptionLocationTests: XCTestCase {
    private typealias F = FormsFixtures

    private func located(_ value: String, _ latitude: Double, _ longitude: Double) -> [String: Any] {
        var option = F.option(value)
        option["location"] = ["latitude": latitude, "longitude": longitude]
        return option
    }

    private func question(_ options: [[String: Any]]) throws -> AdapterSpec.Question {
        let json: [String: Any] = ["id": "station", "kind": "choice", "title": F.text("Vilken station?"),
                                   "required": true, "options": options]
        return try JSONDecoder().decode(AdapterSpec.Question.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// Problems of the felater fixture after replacing the options of question `id`.
    private func problems(question id: String, options: [[String: Any]]) throws -> [String] {
        var json = try F.felaterJSON()
        var questions = try XCTUnwrap(json["questions"] as? [[String: Any]])
        let index = try XCTUnwrap(questions.firstIndex { $0["id"] as? String == id })
        questions[index]["options"] = options
        json["questions"] = questions
        return try JSONDecoder().decode(AdapterSpec.self, from: JSONSerialization.data(withJSONObject: json)).problems
    }

    func testDistance() {
        let a = Coordinate(latitude: 59.32, longitude: 18.40)
        XCTAssertEqual(a.distance(to: a), 0)
        // 0.01° of latitude on a 6 371 km sphere: 6 371 000 × 0.01 × π / 180 = 1 111.95 m.
        XCTAssertEqual(a.distance(to: Coordinate(latitude: 59.33, longitude: 18.40)), 1111.95, accuracy: 1)
        // Gustavsberg to Hemmesta along 59.32° N: 0.1° × 111 194.9 m × cos 59.32° (0.51024) = 5 673.6 m.
        let b = Coordinate(latitude: 59.32, longitude: 18.50)
        XCTAssertEqual(a.distance(to: b), 5673.6, accuracy: 2)
        XCTAssertEqual(b.distance(to: a), a.distance(to: b), accuracy: 1e-9)
    }

    func testLocatedOptionsNearestFirstTiesInOrderUnlocatedLeftOut() throws {
        let q = try question([
            located("far", 59.40, 18.80),
            F.option("nowhere"),
            located("tieA", 59.33, 18.40),
            located("near", 59.321, 18.40),
            located("tieB", 59.33, 18.40),
        ])
        let result = q.locatedOptions(nearestTo: Coordinate(latitude: 59.32, longitude: 18.40))
        XCTAssertEqual(result.map(\.option.value), ["near", "tieA", "tieB", "far"])
        XCTAssertEqual(result[0].meters, 111.2, accuracy: 0.5)
        XCTAssertEqual(try question([F.option("a")]).locatedOptions(nearestTo: Coordinate(latitude: 59.3, longitude: 18.4)).count, 0)
    }

    func testValidatorAcceptsLocationOnChoiceInsideRegion() throws {
        XCTAssertEqual(try problems(question: "station", options: [
            located("780005, Gustavsberg centrum|Coop", 59.3265, 18.3890), F.option("780006, Hemmesta"),
        ]), [])
    }

    func testValidatorRejectsLocationOutsideRegion() throws {
        XCTAssertEqual(try problems(question: "station", options: [
            located("780005, Gustavsberg centrum|Coop", 57.70, 11.97), F.option("780006, Hemmesta"),
        ]), ["question station option 780005, Gustavsberg centrum|Coop location is outside the municipality"])
    }

    func testValidatorRejectsLocationOnMultiChoice() throws {
        XCTAssertEqual(try problems(question: "cleanWhat", options: [located("Batterier", 59.3265, 18.3890), F.option("Tidningar")]),
                       ["question cleanWhat option Batterier location is only allowed on choice questions"])
    }

    func testValidatorRejectsLocationOnSuggestion() throws {
        var json = try F.felaterJSON()
        var questions = try XCTUnwrap(json["questions"] as? [[String: Any]])
        questions.append(F.question("note", "text", "Något mer?", required: false))
        questions[questions.count - 1]["suggestions"] = [located("Vid containern", 59.3265, 18.3890)]
        json["questions"] = questions
        var channel = try XCTUnwrap(json["channel"] as? [String: Any])
        var pages = try XCTUnwrap(channel["pages"] as? [[String: Any]])
        var fields = try XCTUnwrap(pages[0]["fields"] as? [[String: Any]])
        fields.append(F.field("answer", "FELATER_9", question: "note"))
        pages[0]["fields"] = fields
        channel["pages"] = pages
        json["channel"] = channel
        let spec = try JSONDecoder().decode(AdapterSpec.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(spec.problems, ["question note suggestion Vid containern location is only allowed on choice options"])
    }
}
