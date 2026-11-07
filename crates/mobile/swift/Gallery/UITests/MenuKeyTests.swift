import XCTest

/// Shortcuts on a hardware keyboard and the toolbar's menu, against the catalogue's menus. A
/// first-responder view stands in for the canvas, with CraftCanvas's rules: an enabled menu item's
/// key command goes on to the menu, which sends it as a `shortcut`; every other press it takes and
/// logs. So a shortcut that ran twice, or not through the menu, shows.
///
/// XCUITest presses keys on the simulated device itself, so the Mac's Simulator app (whose own Edit
/// menu would take ⌘Z when the window has focus) never sees them. ⌘Z works as any shortcut does,
/// but the first ⌘Z after launch never reaches the app (no `pressesBegan`, no `pressesEnded`, no
/// key command; measured: a second ⌘Z, or one after another key, arrives). So `launch()` first
/// presses Shift alone, which the canvas ignores. Worth a look on an iPad with a Magic Keyboard.
@MainActor
final class MenuKeyTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-selection", "menu_bar"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Choose a menu item, or press its keys."].waitForExistence(timeout: 10))
        app.typeKey(XCUIKeyboardKey.shift.rawValue, modifierFlags: [])
        sleep(1)
        XCTAssertEqual(lines(app), [], "Shift alone reaches nothing")
        return app
    }

    /// A menu item by the start of its label (an item with a shortcut has the keys after it).
    private func item(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    private func lines(_ app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex.map { $0.label }.filter { $0.hasPrefix("{") || $0.hasPrefix("key reached") }
    }

    private func press(_ app: XCUIApplication, _ key: String, _ flags: XCUIElement.KeyModifierFlags) -> [String] {
        app.typeKey(key, modifierFlags: flags)
        sleep(1)
        return lines(app)
    }

    /// ⌘R is View › Rulers' key command: it reaches the menu, which sends it once, and the canvas
    /// doesn't take it too.
    func testAMenuShortcutRunsOnceThroughTheMenu() throws {
        XCTAssertEqual(press(launch(), "r", .command), [#"{"action":"shortcut","keys":"Cmd+R"}"#])
    }

    /// ⌘Z is Edit › Undo's.
    func testUndoRunsOnceThroughTheMenu() throws {
        XCTAssertEqual(press(launch(), "z", .command), [#"{"action":"shortcut","keys":"Cmd+Z"}"#])
    }

    /// ⇧⌘Z is Redo's, which the catalogue disables: the key goes to the canvas, and the app decides.
    func testADisabledItemsKeysGoToTheCanvas() throws {
        XCTAssertEqual(press(launch(), "z", [.command, .shift]), ["key reached the canvas: ⇧⌘z"])
    }

    /// A key no menu item has reaches the canvas.
    func testOtherKeysReachTheCanvas() throws {
        XCTAssertEqual(press(launch(), "k", .command), ["key reached the canvas: ⌘k"])
    }

    /// After typing in a native field and ending it, the canvas has the keyboard again and the menu's
    /// shortcuts work.
    func testShortcutsWorkAfterANativeField() throws {
        let app = launch()
        let field = app.textFields["field"]
        field.tap()
        field.typeText("abc\n")
        XCTAssertEqual(press(app, "r", .command), [#"{"action":"shortcut","keys":"Cmd+R"}"#])
    }

    /// The toolbar's menu button is named, and so is every button it is made of (a menu's label is
    /// a button of its own): none of them unnamed.
    func testTheToolbarMenuButtonIsNamed() throws {
        let app = launch()
        let menus = app.buttons["Menus"].firstMatch
        XCTAssertTrue(menus.waitForExistence(timeout: 5))
        let within = app.buttons.allElementsBoundByIndex.filter { menus.frame.intersects($0.frame) }
        XCTAssertFalse(within.isEmpty)
        XCTAssertEqual(Set(within.map(\.label)), ["Menus"])
    }

    /// The toolbar's menu holds the same tree, and a touch sends the item's command, shortcut or
    /// not (a text field with the keyboard mustn't take Edit › Copy), a submenu's item too.
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
        XCTAssertEqual(lines(app), [#"{"action":"command","id":"image.flip_horizontal"}"#, #"{"action":"command","id":"view.rulers"}"#])
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
