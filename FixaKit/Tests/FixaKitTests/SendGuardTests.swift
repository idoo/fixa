import Foundation
import XCTest
@testable import FixaKit

final class SendGuardTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_088_900)
    let pin = Coordinate(latitude: 59.3262, longitude: 18.3856)

    func draft(tile: String = "streetlight", at coordinate: Coordinate? = nil, place: String = "Gustavsbergs centrum") -> ReportDraft {
        ReportDraft(adapterID: "se.varmdo.ksb", tileID: tile, description: "Släckt", coordinate: coordinate, locationText: place)
    }

    func sent(_ hoursAgo: Double, tile: String = "streetlight", at coordinate: Coordinate? = nil, place: String = "Gustavsbergs centrum") -> SentRecord {
        SentRecord(date: now.addingTimeInterval(-hoursAgo * 3600), tileID: tile, coordinate: coordinate, locationText: place)
    }

    /// `metres` north of `pin`.
    func north(_ metres: Double) -> Coordinate {
        Coordinate(latitude: pin.latitude + metres / 111_195, longitude: pin.longitude)
    }

    func testEmptyHistoryIsOK() {
        XCTAssertEqual(SendGuard.check(draft(at: pin), history: [], now: now), .ok)
    }

    func testDuplicateWithinRadius() {
        let previous = sent(3, at: north(149))
        XCTAssertEqual(SendGuard.check(draft(at: pin), history: [previous], now: now), .duplicate(previous: previous.date))
        XCTAssertEqual(SendGuard.check(draft(at: pin), history: [sent(3, at: north(151))], now: now), .ok)
    }

    func testDuplicateNeedsSameTile() {
        XCTAssertEqual(SendGuard.check(draft(tile: "pothole", at: pin), history: [sent(1, at: pin)], now: now), .ok)
    }

    func testDuplicateWindowIs48Hours() {
        let previous = sent(47.9, at: pin)
        XCTAssertEqual(SendGuard.check(draft(at: pin), history: [previous], now: now), .duplicate(previous: previous.date))
        XCTAssertEqual(SendGuard.check(draft(at: pin), history: [sent(48.1, at: pin)], now: now), .ok)
    }

    func testDuplicateReportsTheLatestMatch() {
        let older = sent(30, at: pin), newer = sent(2, at: north(50))
        XCTAssertEqual(SendGuard.check(draft(at: pin), history: [newer, older], now: now), .duplicate(previous: newer.date))
    }

    func testPlaceTextComparedWhenEitherHasNoPin() {
        let previous = sent(5, place: "Storvägen 3, Brunn")
        XCTAssertEqual(SendGuard.check(draft(at: pin, place: "  storvagen 3 brunn "), history: [previous], now: now), .duplicate(previous: previous.date))
        XCTAssertEqual(SendGuard.check(draft(place: "Storvägen 5, Brunn"), history: [previous], now: now), .ok)
        // Both pinned far apart: the same street name doesn't make it a duplicate.
        XCTAssertEqual(SendGuard.check(draft(at: pin, place: "Storvägen 3, Brunn"), history: [sent(5, at: north(500), place: "Storvägen 3, Brunn")], now: now), .ok)
        // Empty place text never matches.
        XCTAssertEqual(SendGuard.check(draft(place: ""), history: [sent(5, place: " ")], now: now), .ok)
    }

    func testFiveAnHourThenWait() {
        // Different places so nothing is a duplicate.
        let history = (0..<5).map { sent(Double($0) * 0.1 + 0.05, tile: "graffiti", place: "Plats \($0)") }
        XCTAssertEqual(SendGuard.check(draft(), history: Array(history.prefix(4)), now: now), .ok)
        let oldest = history.map(\.date).min()!
        XCTAssertEqual(SendGuard.check(draft(), history: history, now: now), .tooMany(retryAfter: oldest.addingTimeInterval(3600)))
        // Once it ages out the next send is fine.
        XCTAssertEqual(SendGuard.check(draft(), history: history, now: oldest.addingTimeInterval(3600)), .ok)
    }

    func testFifteenADayThenWait() {
        // Two per hour over 7.5 hours: never more than 5 in an hour.
        let history = (0..<15).map { sent(Double($0) * 0.5 + 1.25, tile: "graffiti", place: "Plats \($0)") }
        let oldest = history.map(\.date).min()!
        XCTAssertEqual(SendGuard.check(draft(), history: Array(history.prefix(14)), now: now), .ok)
        XCTAssertEqual(SendGuard.check(draft(), history: history, now: now), .tooMany(retryAfter: oldest.addingTimeInterval(24 * 3600)))
    }

    func testMoreThanTheLimitWaitsForEnoughToAgeOut() {
        // Seven in the last hour (e.g. history merged from two devices): two must age out.
        let history = (0..<7).map { sent(Double($0) * 0.1 + 0.05, tile: "graffiti", place: "Plats \($0)") }
        let sorted = history.map(\.date).sorted()
        XCTAssertEqual(SendGuard.check(draft(), history: history, now: now), .tooMany(retryAfter: sorted[2].addingTimeInterval(3600)))
    }

    func testDuplicateWinsOverRateLimit() {
        var history = (0..<5).map { sent(Double($0) * 0.1 + 0.05, tile: "graffiti", place: "Plats \($0)") }
        let same = sent(0.01, at: pin)
        history.append(same)
        XCTAssertEqual(SendGuard.check(draft(at: pin), history: history, now: now), .duplicate(previous: same.date))
    }

    func testDistance() {
        XCTAssertEqual(SendGuard.distance(pin, north(150)), 150, accuracy: 1)
        XCTAssertEqual(SendGuard.distance(pin, pin), 0)
    }

    func testSentRecordFromDraft() {
        let d = draft(at: pin)
        XCTAssertEqual(SentRecord(d, date: now), SentRecord(date: now, tileID: "streetlight", coordinate: pin, locationText: "Gustavsbergs centrum"))
    }
}
