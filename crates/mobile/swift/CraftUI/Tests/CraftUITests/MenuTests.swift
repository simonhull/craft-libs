import Foundation
import Testing
@testable import CraftUI

@Suite struct MenuTests {
    static func catalogueMenus() throws -> CraftMenuBar {
        let url = try #require(Bundle.module.url(forResource: "ui", withExtension: "json", subdirectory: "Fixtures"))
        struct Catalogue: Decodable { let chrome: [Lenient] }
        struct Lenient: Decodable {
            let name: String
            let menus: CraftMenuBar?
            enum Key: String, CodingKey { case name, example }
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: Key.self)
                name = try c.decode(String.self, forKey: .name)
                menus = name == "menu_bar" ? try c.decode(CraftMenuBar.self, forKey: .example) : nil
            }
        }
        let catalogue = try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url))
        return try #require(catalogue.chrome.first { $0.name == "menu_bar" }?.menus)
    }

    @Test func theCataloguesMenusDecode() throws {
        let bar = try Self.catalogueMenus()
        #expect(bar.menus.map(\.title) == ["Edit", "View", "Layer"])
        #expect(bar.menus.map(\.role) == [.edit, .view, nil])
        let edit = try #require(bar.menus.first)
        #expect(edit.items.count == 4)
        #expect(edit.items.first == .command(CraftMenuCommand(id: "edit.undo", label: "Undo", shortcut: CraftShortcut("Cmd+Z"))))
        #expect(edit.items[safe: 2] == .separator)
        #expect(bar.commands["edit.redo"]?.enabled == false)
        #expect(bar.commands["view.rulers"]?.checked == true)
        #expect(bar.commands["image.flip_horizontal"] != nil, "found inside a submenu")
    }

    /// A role this kit doesn't know, or none, is a menu of the app's own.
    @Test func anUnknownRoleIsNone() throws {
        let json = #"{"menus":[{"title":"Bearbeiten","role":"edit","items":[]},{"title":"Dock","role":"dock","items":[]},{"title":"Layer","items":[]}]}"#
        let bar = try JSONDecoder().decode(CraftMenuBar.self, from: Data(json.utf8))
        #expect(bar.menus.map(\.role) == [.edit, nil, nil])
    }

    /// A newer entry type, or a broken one, is skipped; so is a broken menu. The rest still show.
    @Test func entriesAndMenusItCantReadAreSkipped() throws {
        let json = #"""
        {"menus":[{"title":"Edit","items":[
            {"type":"command","id":"a","label":"A","shortcut":null,"enabled":true,"checked":null},
            {"type":"slider","id":"s"},
            {"type":"command","id":"b"},
            {"type":"separator"}]},
          {"items":[]},
          {"title":"View","items":[]}]}
        """#
        let bar = try JSONDecoder().decode(CraftMenuBar.self, from: Data(json.utf8))
        #expect(bar.menus.map(\.title) == ["Edit", "View"])
        #expect(bar.menus.first?.items == [.command(CraftMenuCommand(id: "a", label: "A")), .separator])
    }

    struct ShortcutCases: Decodable {
        struct Case: Decodable { let text: String; let parsed: String? }
        let named_keys: [String]
        let cases: [Case]
    }

    static func shortcutCases() throws -> ShortcutCases {
        struct Catalogue: Decodable { let shortcuts: ShortcutCases }
        let url = try #require(Bundle.module.url(forResource: "ui", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url)).shortcuts
    }

    /// The catalogue's cases are what Rust's `Shortcut::parse` makes of each text (its tests check the
    /// same list): the Swift parser must agree, refusals included.
    @Test func shortcutsParseAsRustDoes() throws {
        let shared = try Self.shortcutCases()
        #expect(shared.cases.count > 20)
        for c in shared.cases {
            #expect(CraftShortcut(c.text)?.text == c.parsed, "\(c.text.debugDescription)")
        }
        #expect(CraftShortcut.namedKeys == Set(shared.named_keys), "the named keys Rust prints")
        let ctrl = CraftShortcut("Ctrl+Z")
        #expect(ctrl?.ctrl == true && ctrl?.cmd == false, "Ctrl is the Control key, never ⌘")
    }

    /// An item with a shortcut sends the shortcut, so the app's key handling decides; one without
    /// sends its command.
    @Test func anItemSendsItsShortcutElseItsCommand() {
        #expect(CraftMenuCommand(id: "edit.undo", label: "Undo", shortcut: CraftShortcut("Cmd+Z")).message == .shortcut("Cmd+Z"))
        #expect(CraftMenuCommand(id: "image.flip", label: "Flip").message == .command("image.flip"))
    }

    /// Only a structural change rebuilds the menu bar; labels, enabled and checked are read as menus open.
    @Test @MainActor func onlyAStructuralChangeRebuilds() throws {
        let menus = CraftMenus()
        var rebuilds = 0
        var sent: [CraftChromeMessage] = []
        menus.rebuild = { rebuilds += 1 }
        menus.send = { sent.append($0) }
        func bar(enabled: Bool, checked: Bool, label: String = "Rulers") -> CraftMenuBar {
            CraftMenuBar(menus: [CraftMenu(title: "View", items: [.command(CraftMenuCommand(id: "view.rulers", label: label, enabled: enabled, checked: checked))])])
        }
        menus.update(bar(enabled: true, checked: false))
        #expect(rebuilds == 1)
        menus.update(bar(enabled: false, checked: true))
        #expect(rebuilds == 1, "state only")
        #expect(menus.commands["view.rulers"]?.checked == true)
        menus.choose("view.rulers")
        #expect(sent.isEmpty, "disabled")
        menus.update(bar(enabled: true, checked: true))
        menus.choose("view.rulers")
        menus.choose("nope")
        #expect(sent == [.command("view.rulers")])
        menus.update(bar(enabled: true, checked: true, label: "Show Rulers"))
        #expect(rebuilds == 1, "a new label (Undo Brush Stroke, Undo Smudge) is read as the menu opens")
        #expect(menus.commands["view.rulers"]?.label == "Show Rulers")
        menus.update(CraftMenuBar(menus: [CraftMenu(title: "View", items: [.separator])]))
        #expect(rebuilds == 2)
    }

    /// The canvas lets a press go on to the menu only when it is an enabled item's key command.
    @Test @MainActor func onlyAnEnabledKeyCommandClaimsAPress() {
        let menus = CraftMenus()
        menus.update(CraftMenuBar(menus: [CraftMenu(title: "Edit", items: [
            .command(CraftMenuCommand(id: "undo", label: "Undo", shortcut: CraftShortcut("Cmd+Z"))),
            .command(CraftMenuCommand(id: "redo", label: "Redo", shortcut: CraftShortcut("Cmd+Shift+Z"), enabled: false)),
            .command(CraftMenuCommand(id: "zoom", label: "Zoom Out", shortcut: CraftShortcut("Cmd+-"))),
            .command(CraftMenuCommand(id: "brush", label: "Brush", shortcut: CraftShortcut("B"))),
        ])]))
        #expect(menus.claims(CraftShortcut(key: "Z", cmd: true)))
        #expect(!menus.claims(CraftShortcut(key: "Z", cmd: true, shift: true)), "disabled: the app decides")
        #expect(menus.claims(CraftShortcut(key: "Minus", cmd: true)), "Minus is -")
        #expect(!menus.claims(CraftShortcut(key: "B")), "not a key command")
        #expect(!menus.claims(CraftShortcut(key: "Z", ctrl: true)), "⌃Z isn't ⌘Z")
    }

    @Test func shortcutsShowAsGlyphs() {
        #expect(CraftShortcut("Cmd+Shift+Z")?.glyphs == "⇧⌘Z")
        #expect(CraftShortcut("Ctrl+Alt+ArrowUp")?.glyphs == "⌃⌥↑")
        #expect(CraftShortcut("Cmd+Minus")?.glyphs == "⌘-")
        #expect(CraftShortcut("B")?.glyphs == "B")
    }
}

#if os(iOS)
import UIKit

@Suite @MainActor struct MenuBuilderTests {
    let action = CraftMenuResponder.action

    @Test func menusHaveTitlesGroupsAndSubmenus() throws {
        let menus = CraftMenuBuilder.menus(try MenuTests.catalogueMenus(), action: action)
        #expect(menus.map(\.title) == ["Edit", "View", "Layer"])
        let edit = try #require(menus.first)
        // The separator splits Edit into two inline groups: Undo and Redo, then Transform.
        #expect(edit.children.count == 2)
        let groups = edit.children.compactMap { $0 as? UIMenu }
        #expect(groups.allSatisfy { $0.options.contains(.displayInline) })
        #expect(groups.first?.children.compactMap { ($0 as? UICommand)?.title } == ["Undo", "Redo"])
        let transform = try #require(groups.last?.children.first as? UIMenu)
        #expect(transform.title == "Transform")
        #expect((transform.children.first as? UICommand)?.propertyList as? String == "image.flip_horizontal")
        #expect(menus.map(\.identifier) == [CraftMenuBuilder.identifier(0, "Edit"), CraftMenuBuilder.identifier(1, "View"), CraftMenuBuilder.identifier(2, "Layer")])
    }

    @Test func shortcutsBecomeKeyCommands() throws {
        let undo = try #require(CraftMenuBuilder.element(CraftMenuCommand(id: "edit.undo", label: "Undo", shortcut: CraftShortcut("Cmd+Shift+Z")), action: action) as? UIKeyCommand)
        #expect(undo.input == "z")
        #expect(undo.modifierFlags == [.command, .shift])
        #expect(undo.propertyList as? String == "edit.undo")
        #expect(undo.action == action)
        let control = try #require(CraftMenuBuilder.element(CraftMenuCommand(id: "a", label: "A", shortcut: CraftShortcut("Ctrl+Tab")), action: action) as? UIKeyCommand)
        #expect(control.input == "\t" && control.modifierFlags == .control)
        let arrow = try #require(CraftMenuBuilder.element(CraftMenuCommand(id: "b", label: "B", shortcut: CraftShortcut("Cmd+Alt+ArrowUp")), action: action) as? UIKeyCommand)
        #expect(arrow.input == UIKeyCommand.inputUpArrow && arrow.modifierFlags == [.command, .alternate])
        let f5 = try #require(CraftMenuBuilder.element(CraftMenuCommand(id: "c", label: "C", shortcut: CraftShortcut("Cmd+F5")), action: action) as? UIKeyCommand)
        #expect(f5.input == UIKeyCommand.f5)
    }

    /// The canvas passes on a press without ⌘ or ⌃ as typed text, where a key command would run it a
    /// second time: such a shortcut is only shown.
    @Test func aShortcutWithoutCommandOrControlIsOnlyShown() {
        for keys in ["B", "Alt+ArrowUp", "Shift+F5", "F5"] {
            let element = CraftMenuBuilder.element(CraftMenuCommand(id: "t", label: "Tool", shortcut: CraftShortcut(keys)), action: action)
            #expect(!(element is UIKeyCommand), "\(keys)")
            #expect((element as? UICommand)?.title == "Tool\t\(CraftShortcut(keys)?.glyphs ?? "")", "\(keys)")
        }
    }

    @Test func aPlainItemIsACommandAndAnUnpressableShortcutIsShown() throws {
        let plain = CraftMenuBuilder.element(CraftMenuCommand(id: "a", label: "Flip"), action: action)
        #expect(!(plain is UIKeyCommand) && (plain as? UICommand)?.title == "Flip")
        let odd = CraftMenuBuilder.element(CraftMenuCommand(id: "b", label: "Odd", shortcut: CraftShortcut("Cmd+Insert")), action: action)
        #expect(!(odd is UIKeyCommand))
        #expect((odd as? UICommand)?.title == "Odd\t⌘Insert")
    }

    /// Menus take system menus' places by role, never by their (translated) titles.
    @Test func menusArePlacedByRole() {
        #expect(CraftMenuDelegate.placement(.file) == .replace(.file))
        #expect(CraftMenuDelegate.placement(.edit) == .replace(.edit))
        #expect(CraftMenuDelegate.placement(.view) == .replace(.view))
        #expect(CraftMenuDelegate.placement(.help) == .replace(.help))
        #expect(CraftMenuDelegate.placement(.window) == .startOfWindow)
        #expect(CraftMenuDelegate.placement(nil) == .beforeWindow)
    }

    /// A system bar as UIKit builds it: Settings (⌘,) in the app menu, undo and redo (⌘Z, ⇧⌘Z) and
    /// the standard edit items in Edit, Minimize (⌘M) right in Window, and Full Screen in a group.
    static func systemBar() -> UIMenu {
        let sel = CraftMenuResponder.action
        func key(_ title: String, _ input: String, _ flags: UIKeyModifierFlags = .command) -> UIKeyCommand {
            UIKeyCommand(title: title, action: sel, input: input, modifierFlags: flags)
        }
        let app = UIMenu(title: "App", identifier: .application, children: [
            UICommand(title: "About", action: sel),
            UIMenu(title: "", identifier: .preferences, options: .displayInline, children: [key("Settings…", ",")]),
        ])
        let edit = UIMenu(title: "Edit", identifier: .edit, children: [
            UIMenu(title: "", identifier: .undoRedo, options: .displayInline, children: [key("Undo", "z"), key("Redo", "Z", [.command, .shift])]),
            UIMenu(title: "", identifier: .standardEdit, options: .displayInline, children: [key("Cut", "x"), key("Copy", "c"), UICommand(title: "Delete", action: sel)]),
            UIMenu(title: "Find", identifier: .find, children: [UIMenu(title: "", identifier: .findPanel, options: .displayInline, children: [key("Find…", "f")])]),
        ])
        let window = UIMenu(title: "Window", identifier: .window, children: [
            key("Minimize", "m"),
            UIMenu(title: "", identifier: .fullscreen, options: .displayInline, children: [key("Full Screen", "f", [.command, .control])]),
        ])
        return UIMenu(title: "", identifier: .root, children: [app, edit, window])
    }

    /// The app's menus with these key commands, as a bar.
    func appMenus(_ keys: [(String, String)]) -> [UIMenu] {
        let items = keys.map { CraftMenuEntry.command(CraftMenuCommand(id: $0.0, label: $0.0, shortcut: CraftShortcut($0.1))) }
        return CraftMenuBuilder.menus(CraftMenuBar(menus: [CraftMenu(title: "Mine", items: items)]), action: action)
    }

    /// Before the app's menus go in, every system command whose keys they take comes out: a group
    /// inside a system menu goes whole (half of undo and redo means nothing), a command right in a
    /// top-level menu alone, so Window stays. A menu the app's replaces is left to that.
    @Test func systemCommandsWhoseKeysTheAppTakesComeOut() {
        let mine = appMenus([("prefs", "Cmd+,"), ("undo", "Cmd+Z"), ("cut", "Cmd+X"), ("min", "Cmd+M"), ("plain", "Ctrl+Tab")])
        let taken = CraftMenuDelegate.chords(mine)
        #expect(taken.contains(.init(input: ",", flags: .command)))
        #expect(taken.count == 5)
        let removal = CraftMenuDelegate.collisions(in: Self.systemBar(), with: taken, replacing: [])
        #expect(removal.menus == [.preferences, .undoRedo, .standardEdit], "Find (⌘F) is no one's")
        #expect(removal.commandsIn == [.window])
        let replaced = CraftMenuDelegate.collisions(in: Self.systemBar(), with: taken, replacing: [.edit])
        #expect(replaced.menus == [.preferences], "Edit goes whole")
        #expect(CraftMenuDelegate.collisions(in: Self.systemBar(), with: CraftMenuDelegate.chords(appMenus([("x", "Cmd+K")])), replacing: []).isEmpty)
    }

    /// Keys match whatever case UIKit gives the input: ⇧⌘Z is "Z" or "z" with Shift.
    @Test func keysMatchInAnyCase() {
        let taken = CraftMenuDelegate.chords(appMenus([("redo", "Cmd+Shift+Z"), ("find", "Cmd+Ctrl+F")]))
        let removal = CraftMenuDelegate.collisions(in: Self.systemBar(), with: taken, replacing: [])
        #expect(removal.menus == [.undoRedo, .fullscreen])
        #expect(removal.commandsIn.isEmpty)
    }

    /// Only an app command that is a key command takes keys: one only shown (a bare letter) doesn't.
    @Test func shownShortcutsTakeNoKeys() {
        #expect(CraftMenuDelegate.chords(appMenus([("tool", "B"), ("flip", "F5")])).isEmpty)
    }

    @Test func leadingTrailingAndRepeatedSeparatorsAreDropped() {
        let items: [CraftMenuEntry] = [.separator, .command(CraftMenuCommand(id: "a", label: "A")), .separator, .separator]
        let built = CraftMenuBuilder.elements(items, action: action)
        #expect(built.count == 1 && (built.first as? UICommand)?.title == "A")
    }
}
#endif

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
