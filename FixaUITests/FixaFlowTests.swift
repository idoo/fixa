import XCTest

/// End-to-end flows in demo mode (`-FixaDemo 1`): nothing leaves the phone, nothing is saved.
/// Run: `xcodebuild test -scheme FixaUI -only-testing:FixaUITests/FixaFlowTests`.
final class FixaFlowTests: XCTestCase {
    private let shotDir = URL(fileURLWithPath: "/tmp/fixa-qa", isDirectory: true)

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FixaDemo", "1", "-FixaEmptyHistory", "1"] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    @MainActor
    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: shotDir.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let match = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: timeout), "Missing \(id)", file: file, line: line)
        return match
    }

    /// Scrolls until the element is hittable (Report is long at large text sizes).
    @MainActor
    private func reveal(_ app: XCUIApplication, _ target: XCUIElement, up: Bool = false) {
        var tries = 0
        while !target.isHittable && tries < 8 {
            if up { app.swipeDown() } else { app.swipeUp() }
            tries += 1
        }
    }

    @MainActor
    private func replaceDescription(_ app: XCUIApplication, with text: String) {
        let editor = element(app, "report.description")
        reveal(app, editor)
        editor.tap()
        let current = (editor.value as? String) ?? ""
        if !current.isEmpty {
            editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 5))
        }
        if !text.isEmpty { editor.typeText(text) }
    }

    @MainActor
    private func pickPlaceBySearch(_ app: XCUIApplication) {
        let place = element(app, "report.place")
        reveal(app, place, up: true)
        place.tap()
        let search = element(app, "location.search")
        search.tap()
        search.typeText("Odelbergs väg")
        // Suggestions come from MapKit; Return picks the first one.
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Odelberg'")).firstMatch
        _ = suggestion.waitForExistence(timeout: 10)
        search.typeText("\n")
        let confirm = element(app, "location.confirm")
        XCTAssertTrue(confirm.waitForHittable(timeout: 10), "Confirm place not tappable")
        confirm.tap()
    }

    /// Onboarding -> Gatlampa släckt -> place by search -> description -> Review -> Send -> receipt -> history.
    @MainActor
    private func runReportFlow(_ app: XCUIApplication, prefix: String, onboarding: Bool) {
        if onboarding {
            let cont = element(app, "onboarding.continue")
            shot("\(prefix)-onboarding")
            cont.tap()
        }
        element(app, "home.tile.streetlight").tap()
        shot("\(prefix)-report")
        pickPlaceBySearch(app)
        replaceDescription(app, with: "Lampan vid busshållplatsen är släckt.")
        let review = element(app, "report.review")
        review.tap()
        let send = element(app, "review.send")
        XCTAssertTrue(send.waitForHittable(timeout: 20), "Send never became available")
        shot("\(prefix)-review")
        send.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'DEMO-1234'")).firstMatch.waitForExistence(timeout: 10), "Receipt without case number")
        shot("\(prefix)-receipt")
        // Done on the receipt returns Home (the receipt has no identifier of its own).
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Klar", "تم"])).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "No Done on the receipt")
        done.tap()
        element(app, "home.history").tap()
        let row = app.descendants(matching: .any).matching(identifier: "history.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Sent report missing from history")
        shot("\(prefix)-history")
    }

    // MARK: Tests

    @MainActor
    func testA_FullReportFlowSwedishDemo() {
        let app = launch(["-FixaScreen", "onboarding", "-FixaLanguage", "sv"])
        runReportFlow(app, prefix: "a-sv", onboarding: true)
    }

    @MainActor
    func testB_ArabicViaSettingsRTL() {
        let app = launch(["-FixaLanguage", "en"])
        element(app, "home.settings").tap()
        element(app, "settings.language").tap()
        // Arabic is the last of 22 languages: scroll to it first.
        let arabic = element(app, "language.ar")
        reveal(app, arabic)
        arabic.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let tile = element(app, "home.tile.streetlight")
        shot("b-ar-home")
        // RTL: the first tile sits on the right half.
        XCTAssertGreaterThan(tile.frame.midX, app.windows.firstMatch.frame.midX, "Tiles are not mirrored in Arabic")
        runReportFlow(app, prefix: "b-ar", onboarding: false)
    }

    @MainActor
    func testC_Accessibility3ButtonsHittable() {
        let app = launch(["-FixaTextSize", "accessibility3", "-FixaLanguage", "en"])
        let tile = element(app, "home.tile.streetlight")
        reveal(app, tile)
        XCTAssertTrue(tile.isHittable)
        XCTAssertTrue(element(app, "home.settings").isHittable)
        XCTAssertTrue(element(app, "home.history").isHittable)
        shot("c-ax3-home")
        tile.tap()
        let review = element(app, "report.review")
        XCTAssertTrue(review.isHittable, "Review button hidden at accessibility3")
        XCTAssertFalse(review.label.isEmpty)
        let place = element(app, "report.place")
        XCTAssertFalse(place.label.hasSuffix("…"), "Place label truncated: \(place.label)")
        shot("c-ax3-report")
        review.tap()
        let send = element(app, "review.send")
        // Send stays disabled while the on-device translation runs (capped at 15 s).
        XCTAssertTrue(send.waitForHittable(timeout: 20), "Send button hidden at accessibility3")
        XCTAssertTrue(send.label.contains("Värmdö"), "Send label lost the municipality: \(send.label)")
        shot("c-ax3-review")
    }

    @MainActor
    func testD_EmptyDescriptionBlocksReview() {
        let app = launch(["-FixaLanguage", "en"])
        element(app, "home.tile.streetlight").tap()
        replaceDescription(app, with: "")
        app.keyboards.buttons.firstMatch.tapIfExists()
        element(app, "report.review").tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "review.send").firstMatch.waitForExistence(timeout: 2), "Review opened with an empty description")
        let editor = element(app, "report.description")
        XCTAssertTrue(editor.isHittable, "Report did not scroll to the empty description")
        let value = "\(editor.label) \((editor.value as? String) ?? "")"
        XCTAssertTrue(value.lowercased().contains("describe") || value.lowercased().contains("write") || value.lowercased().contains("what"), "No issue announced on the description: \(value)")
        shot("d-validation")
    }

    @MainActor
    func testE_DeleteAllDataEmptiesHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-FixaDemo", "1", "-FixaLanguage", "en"]
        app.launch()
        element(app, "home.history").tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "history.row").firstMatch.waitForExistence(timeout: 5), "Demo history not seeded")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        element(app, "home.settings").tap()
        let delete = element(app, "settings.deleteAll")
        reveal(app, delete)
        delete.tap()
        let confirm = app.buttons["Delete all data"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        element(app, "home.history").tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "history.row").firstMatch.waitForExistence(timeout: 3), "History not empty after Delete all my data")
        shot("e-history-empty")
    }

    /// Build 5 crashed (NSInternalInconsistencyException in `_UITraitOverrides`) the moment
    /// Higher contrast was on, and then at every launch. Flip it twice from whatever state is
    /// saved (display settings persist across runs), so both on and off are exercised, and
    /// check the app stays alive and other screens still open.
    @MainActor
    func testF_HigherContrastDoesNotCrash() {
        let app = launch(["-FixaLanguage", "en"])
        element(app, "home.settings").tap()
        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Higher contrast")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "No Higher contrast switch")
        reveal(app, toggle)
        let initial = toggle.value as? String
        let flipped = initial == "1" ? "0" : "1"
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(app.state, .runningForeground, "App died after switching Higher contrast")
        XCTAssertEqual(toggle.value as? String, flipped, "Higher contrast did not switch")
        shot("f-contrast-\(flipped)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        element(app, "home.history").tap()
        XCTAssertEqual(app.state, .runningForeground, "App died navigating after switching Higher contrast")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        element(app, "home.settings").tap()
        reveal(app, toggle)
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(app.state, .runningForeground, "App died after switching Higher contrast back")
        XCTAssertEqual(toggle.value as? String, initial, "Higher contrast did not switch back")
    }
}

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isHittable && isEnabled { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    func tapIfExists() {
        if exists && isHittable { tap() }
    }
}
