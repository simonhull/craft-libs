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

    /// The edits sent, oldest first.
    private func sent(_ app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.hasPrefix("{") }.reversed()
    }

    /// A drag on a stepped slider (the system's, with ticks) is one gesture: begin, a change for
    /// each new step, commit, all with one gesture number, every value a multiple of the step.
    func testADragOnASteppedSliderIsOneGestureOnItsSteps() throws {
        let app = launch(["-selection", "number"])
        let hardness = slider(app, "Hardness")
        XCTAssertTrue(hardness.waitForExistence(timeout: 10))
        let start = hardness.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = hardness.coordinate(withNormalizedOffset: CGVector(dx: 0.83, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)
        let commit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", #""phase":"commit""#)).firstMatch
        XCTAssertTrue(commit.waitForExistence(timeout: 3))
        let edits = sent(app)
        XCTAssertTrue(edits.first?.contains(#""phase":"begin""#) == true, "\(edits)")
        let gestures = Set(edits.compactMap { $0.firstMatch(of: /"gesture":(\d+)/).map { String($0.1) } })
        XCTAssertEqual(gestures.count, 1, "one gesture: \(edits)")
        let values = edits.compactMap { $0.firstMatch(of: /"value":([0-9.]+)/).flatMap { Double($0.1) } }
        XCTAssertFalse(values.isEmpty, "\(edits)")
        for value in values {
            XCTAssertEqual((value * 10).rounded(), value * 10, accuracy: 1e-9, "\(value) is on a step")
        }
        XCTAssertGreaterThan(values.last ?? 0, 0.5, "it moved right: \(edits)")
    }

    /// The value is the system's bordered capsule, shorter than 44 pt; a tap just above it, inside
    /// its 44 pt row, still opens the field to type one.
    func testTheValuesTargetIsTallerThanItsCapsule() throws {
        let app = launch(["-selection", "number"])
        let value = app.buttons.matching(NSPredicate(format: "label == %@", "Hardness")).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        XCTAssertEqual(value.frame.height, 44, accuracy: 0.5)
        // 2 pt from the top of the row: above the capsule, which is about 32 pt tall.
        value.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 2)).tap()
        XCTAssertTrue(app.alerts["Hardness"].waitForExistence(timeout: 3))
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
