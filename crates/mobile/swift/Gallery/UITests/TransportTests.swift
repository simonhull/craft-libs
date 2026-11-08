import XCTest

/// The catalogue's transport as the shell's floating bar, against the Gallery playing the app.
@MainActor
final class TransportTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-selection", "transport"]
        app.launch()
        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    /// The floating bar's element (the inspector holds the same transport): the lowest match.
    private func bar(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(identifier: label).allElementsBoundByIndex
        return matches.max { $0.frame.maxY < $1.frame.maxY } ?? app.buttons[label]
    }

    /// The edits sent, oldest first.
    private func sent(_ app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.hasPrefix("{") }.reversed()
    }

    private func value(_ element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    /// Play sends one edit; then the playhead moves by live positions alone, in the bar and the
    /// inspector, until Pause.
    func testPlayingMovesThePlayheadWithoutEdits() throws {
        let app = launch()
        let playhead = bar(app, "Playhead")
        XCTAssertEqual(value(playhead), "Frame 12 of 30")
        bar(app, "Play").tap()
        XCTAssertTrue(bar(app, "Pause").waitForExistence(timeout: 3), "the button shows Pause while playing")
        let moved = expectation(for: NSPredicate(format: "value != %@", "Frame 12 of 30"), evaluatedWith: playhead)
        wait(for: [moved], timeout: 3)
        XCTAssertEqual(sent(app).count, 1, "playing sends no edits: \(sent(app))")
        XCTAssertTrue(sent(app).first?.contains(#""value":"play""#) == true, "\(sent(app))")
        bar(app, "Pause").tap()
        XCTAssertTrue(bar(app, "Play").waitForExistence(timeout: 3))
        let paused = value(playhead)
        sleep(1)
        XCTAssertEqual(value(playhead), paused, "paused, it stays")
    }

    /// A tap on the track seeks there: begin, then commit, one gesture.
    func testATapOnTheScrubberSeeks() throws {
        let app = launch()
        let playhead = bar(app, "Playhead")
        playhead.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        let seeks = expectation(for: NSPredicate(format: "value == %@", "Frame 1 of 30"), evaluatedWith: playhead)
        wait(for: [seeks], timeout: 3)
        let edits = sent(app)
        XCTAssertEqual(edits.count, 2, "\(edits)")
        XCTAssertTrue(edits.first?.contains(#""phase":"begin""#) == true && edits.first?.contains(#""frame":0"#) == true, "\(edits)")
        XCTAssertTrue(edits.last?.contains(#""phase":"commit""#) == true && edits.last?.contains(#""frame":0"#) == true, "\(edits)")
    }

    /// A drag sends a change for each new frame (never twice the same), then commit where it ended.
    func testADragScrubsFrameByFrame() throws {
        let app = launch()
        let playhead = bar(app, "Playhead")
        let start = playhead.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let end = playhead.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 60, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end)
        let lands = expectation(for: NSPredicate(format: "value == %@", "Frame 30 of 30"), evaluatedWith: playhead)
        wait(for: [lands], timeout: 3)
        let edits = sent(app)
        // The log lists the newest first; the oldest (the begin) may be scrolled away.
        XCTAssertTrue(edits.last?.contains(#""phase":"commit""#) == true && edits.last?.contains(#""frame":29"#) == true, "\(edits)")
        let changes = edits.filter { $0.contains(#""phase":"change""#) }
        XCTAssertGreaterThan(changes.count, 3, "\(edits)")
        XCTAssertEqual(Set(changes).count, changes.count, "a change only for a new frame: \(changes)")
    }
}
