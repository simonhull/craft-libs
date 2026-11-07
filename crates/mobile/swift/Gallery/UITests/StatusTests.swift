import XCTest

/// The catalogue's status over the Gallery: a toast, and a job whose Cancel sends its command.
@MainActor
final class StatusTests: XCTestCase {
    func testTheToastShowsAndCancelSendsTheJobsCommand() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-selection", "status"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Error: Couldn't open b.psd: not a Photoshop file"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        let sent = app.staticTexts[#"{"action":"command","id":"job.cancel"}"#]
        XCTAssertTrue(sent.waitForExistence(timeout: 3))
        // An error toast goes away by itself.
        XCTAssertTrue(app.staticTexts["Error: Couldn't open b.psd: not a Photoshop file"].waitForNonExistence(timeout: 10))
        app.buttons["Saved"].tap()
        XCTAssertTrue(app.staticTexts["Saved a.psd"].waitForExistence(timeout: 3))
    }

    /// A countdown is one message: its toast updates in place, and once tapped away it stays away
    /// while the text keeps changing. A new message then shows its own toast.
    func testACountdownIsOneToastAndANewMessageAnother() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-selection", "status"]
        app.launch()
        let catalogue = app.staticTexts["Error: Couldn't open b.psd: not a Photoshop file"].firstMatch
        XCTAssertTrue(catalogue.waitForExistence(timeout: 10))
        catalogue.tap()
        XCTAssertTrue(catalogue.waitForNonExistence(timeout: 3))
        app.buttons["Countdown"].tap()
        // A toast's text may be found more than once (the capsule and its label): count one toast's.
        let toasts = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Error: Scratch disk low'"))
        XCTAssertTrue(toasts.firstMatch.waitForExistence(timeout: 3))
        let (first, one) = (toasts.firstMatch.label, toasts.count)
        let counted = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Error: Scratch disk low' AND label != %@", first))
        XCTAssertTrue(counted.firstMatch.waitForExistence(timeout: 3), "the text changes")
        XCTAssertEqual(toasts.count, one, "one toast, updated in place")
        toasts.firstMatch.tap()
        XCTAssertTrue(toasts.firstMatch.waitForNonExistence(timeout: 3))
        // The countdown goes on: dismissed, it stays so.
        XCTAssertFalse(toasts.firstMatch.waitForExistence(timeout: 2.5), "tapped away, the countdown doesn't come back")
        app.buttons["Saved"].tap()
        XCTAssertTrue(app.staticTexts["Saved a.psd"].firstMatch.waitForExistence(timeout: 3), "a new message, a new toast")
    }
}
