import XCTest

/// Screenshot sweep, run via the `FixaUI` scheme:
/// `xcodebuild test -scheme FixaUI -only-testing:FixaUITests/FixaUITests/testScreens`.
final class FixaUITests: XCTestCase {
    private let screens = [
        "home", "report", "location", "review", "receipt", "history", "about",
        "settings", "contact", "textsize", "language",
    ]

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testScreens() {
        for screen in screens {
            let app = XCUIApplication()
            app.launchArguments = ["-FixaDemo", "1", "-FixaScreen", screen]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App did not start for \(screen)")
            // Let maps, sheets and the receipt stamp settle.
            Thread.sleep(forTimeInterval: screen == "location" || screen == "receipt" ? 3 : 1.5)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = screen
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
