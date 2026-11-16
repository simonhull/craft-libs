import XCTest

/// A panel's controls and its presentations, against the Gallery playing the app.
@MainActor
final class PanelTests: XCTestCase {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// A number's slider, by its label.
    private func slider(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.sliders.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// A tool popover has the system's Close button, which closes it.
    func testThePopoversCloseButtonClosesIt() throws {
        let app = launch(["-selection", "number", "-inspector", "NO", "-popover", "YES"])
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(slider(app, "Size").exists)
        close.tap()
        XCTAssertTrue(slider(app, "Size").waitForNonExistence(timeout: 3))
    }

    /// The inspector has a Close button too, consistent with the popover's.
    func testTheInspectorsCloseButtonClosesIt() throws {
        let app = launch(["-selection", "number"])
        XCTAssertTrue(slider(app, "Size").waitForExistence(timeout: 10))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(slider(app, "Size").waitForNonExistence(timeout: 3))
    }
}
