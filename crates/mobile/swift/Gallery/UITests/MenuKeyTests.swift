import XCTest

/// Shortcuts on a hardware keyboard and the toolbar's menu, against the catalogue's menus. A
/// first-responder view stands in for the canvas: it takes every key press with ⌘ or ⌃ and logs it,
/// as CraftCanvas forwards presses to the app, so a shortcut that ran twice shows twice.
@MainActor
final class MenuKeyTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-selection", "menu_bar"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Choose a menu item, or press its keys."].waitForExistence(timeout: 10))
        return app
    }

    /// A menu item by the start of its label (an item with a shortcut has the keys after it).
    private func item(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    private func lines(_ app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex.map { $0.label }.filter { $0.hasPrefix("{") || $0.hasPrefix("key reached") }
    }

    /// ⌘R is View › Rulers' shortcut: the press reaches the canvas once, and the menu's key command
    /// doesn't run it again (the first responder gets a press before key commands do).
    func testAMenuShortcutRunsOnce() throws {
        let app = launch()
        app.typeKey("r", modifierFlags: .command)
        sleep(1)
        XCTAssertEqual(lines(app), ["key reached the canvas: ⌘r"])
    }

    /// A key no menu item has reaches the canvas the same way.
    func testOtherKeysReachTheCanvas() throws {
        let app = launch()
        app.typeKey("k", modifierFlags: .command)
        sleep(1)
        XCTAssertEqual(lines(app), ["key reached the canvas: ⌘k"])
    }

    /// The toolbar's menu holds the same tree: an item with a shortcut sends the shortcut, one
    /// without sends its command, a submenu's item too.
    func testTheToolbarMenuSendsWhatTheMenuBarWould() throws {
        let app = launch()
        app.buttons["Menus"].tap()
        app.buttons["View"].tap()
        item(app, "Rulers").tap()
        app.buttons["Menus"].tap()
        app.buttons["Edit"].tap()
        app.buttons["Transform"].tap()
        item(app, "Flip Horizontal").tap()
        sleep(1)
        XCTAssertEqual(lines(app), [#"{"action":"command","id":"image.flip_horizontal"}"#, #"{"action":"shortcut","keys":"Cmd+R"}"#])
    }

    /// Redo is disabled in the catalogue: its item in the toolbar's menu can't be chosen.
    func testADisabledItemCantBeChosen() throws {
        let app = launch()
        app.buttons["Menus"].tap()
        app.buttons["Edit"].tap()
        let redo = item(app, "Redo")
        XCTAssertTrue(redo.waitForExistence(timeout: 3))
        XCTAssertFalse(redo.isEnabled)
        XCTAssertTrue(item(app, "Undo").isEnabled)
    }
}
