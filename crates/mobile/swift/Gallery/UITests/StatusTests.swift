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
}
