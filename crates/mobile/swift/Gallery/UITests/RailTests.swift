import XCTest

/// The catalogue's palette as the rail, against the Gallery playing the app.
@MainActor
final class RailTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-selection", "tool_palette"]
        app.launch()
        XCTAssertTrue(app.buttons["Tool Options"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    /// The rail's own buttons (the inspector holds a row of the same tools): the leftmost match.
    private func rail(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.buttons.matching(identifier: label).allElementsBoundByIndex
        return matches.min { $0.frame.minX < $1.frame.minX } ?? app.buttons[label]
    }

    private func sent(_ app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex.map { $0.label }.filter { $0.hasPrefix("{") }
    }

    func testATapSelectsTheTool() throws {
        let app = launch()
        rail(app, "Move").tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", #""value":"move""#)).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(rail(app, "Move").isSelected)
        XCTAssertFalse(rail(app, "Brush").isSelected)
    }

    func testALongPressOpensTheSlotsFlyout() throws {
        let app = launch()
        rail(app, "Brush").press(forDuration: 1.0)
        let pencil = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pencil")).firstMatch
        XCTAssertTrue(pencil.waitForExistence(timeout: 3))
        pencil.tap()
        sleep(1)
        XCTAssertTrue(sent(app).first?.contains(#""value":"pencil""#) == true, "\(sent(app))")
        XCTAssertTrue(rail(app, "Pencil").isSelected, "the slot shows the tool picked from its flyout")
    }

    func testOptionsOpenTheToolPanel() throws {
        let app = launch()
        rail(app, "Tool Options").tap()
        XCTAssertTrue(app.staticTexts["Size"].waitForExistence(timeout: 3), "the stand-in Brush panel")
    }

    func testADoubleTapOpensOptions() throws {
        let app = launch()
        rail(app, "Brush").doubleTap()
        XCTAssertTrue(app.staticTexts["Size"].waitForExistence(timeout: 3))
    }

    /// Every button in the rail says what it is: one element per slot, named for its tool, and no
    /// unnamed button inside it (a slot with a flyout is a menu with a primary action).
    func testEveryRailButtonIsLabelled() throws {
        let app = launch()
        let x = rail(app, "Tool Options").frame.midX
        let inRail = app.buttons.allElementsBoundByIndex.filter { abs($0.frame.midX - x) < 30 }
        XCTAssertEqual(inRail.map(\.label), ["Move", "Brush", "Smudge", "Tool Options"])
        XCTAssertTrue(rail(app, "Brush").isSelected)
    }
}
