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
        #expect(bar.menus.map(\.title) == ["Edit", "View"])
        let edit = try #require(bar.menus.first)
        #expect(edit.items.count == 4)
        #expect(edit.items.first == .command(CraftMenuCommand(id: "edit.undo", label: "Undo", shortcut: CraftShortcut("Cmd+Z"))))
        #expect(edit.items[safe: 2] == .separator)
        #expect(bar.commands["edit.redo"]?.enabled == false)
        #expect(bar.commands["view.rulers"]?.checked == true)
        #expect(bar.commands["image.flip_horizontal"] != nil, "found inside a submenu")
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

    @Test func shortcutsParseAndPrintAsRustDoes() {
        #expect(CraftShortcut("Shift+Cmd+z")?.text == "Cmd+Shift+Z")
        #expect(CraftShortcut("Cmd++")?.key == "+")
        #expect(CraftShortcut("Ctrl+Cmd+M")?.text == "Ctrl+Cmd+M")
        #expect(CraftShortcut("F5")?.text == "F5")
        #expect(CraftShortcut("Cmd+") == nil)
        #expect(CraftShortcut("Cmd+Cmd+Z") == nil)
        #expect(CraftShortcut("Hyper+Z") == nil)
        let ctrl = CraftShortcut("Ctrl+Z")
        #expect(ctrl?.ctrl == true && ctrl?.cmd == false, "Ctrl is the Control key, never ⌘")
    }

    /// An item with a shortcut sends the shortcut, so the app's key handling decides; one without
    /// sends its command.
    @Test func anItemSendsItsShortcutElseItsCommand() {
        #expect(CraftMenuCommand(id: "edit.undo", label: "Undo", shortcut: CraftShortcut("Cmd+Z")).message == .shortcut("Cmd+Z"))
        #expect(CraftMenuCommand(id: "image.flip", label: "Flip").message == .command("image.flip"))
    }

    /// Only a structural change rebuilds the menu bar; enabled and checked are read as menus open.
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
        #expect(rebuilds == 2)
    }

    @Test func shortcutsShowAsSymbols() {
        #expect(CraftMenuItems.symbols(CraftShortcut("Cmd+Shift+Z")!) == "⇧⌘Z")
        #expect(CraftMenuItems.symbols(CraftShortcut("Ctrl+Alt+ArrowUp")!) == "⌃⌥↑")
    }
}

#if os(iOS)
import UIKit

@Suite @MainActor struct MenuBuilderTests {
    let action = CraftMenuResponder.action

    @Test func menusHaveTitlesGroupsAndSubmenus() throws {
        let menus = CraftMenuBuilder.menus(try MenuTests.catalogueMenus(), action: action)
        #expect(menus.map(\.title) == ["Edit", "View"])
        let edit = try #require(menus.first)
        // The separator splits Edit into two inline groups: Undo and Redo, then Transform.
        #expect(edit.children.count == 2)
        let groups = edit.children.compactMap { $0 as? UIMenu }
        #expect(groups.allSatisfy { $0.options.contains(.displayInline) })
        #expect(groups.first?.children.compactMap { ($0 as? UICommand)?.title } == ["Undo", "Redo"])
        let transform = try #require(groups.last?.children.first as? UIMenu)
        #expect(transform.title == "Transform")
        #expect((transform.children.first as? UICommand)?.propertyList as? String == "image.flip_horizontal")
        #expect(menus.map(\.identifier) == [CraftMenuBuilder.identifier(0, "Edit"), CraftMenuBuilder.identifier(1, "View")])
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
            #expect((element as? UICommand)?.title == "Tool\t\(CraftShortcut(keys)?.text ?? "")", "\(keys)")
        }
    }

    @Test func aPlainItemIsACommandAndAnUnpressableShortcutIsShown() throws {
        let plain = CraftMenuBuilder.element(CraftMenuCommand(id: "a", label: "Flip"), action: action)
        #expect(!(plain is UIKeyCommand) && (plain as? UICommand)?.title == "Flip")
        let odd = CraftMenuBuilder.element(CraftMenuCommand(id: "b", label: "Odd", shortcut: CraftShortcut("Cmd+Insert")), action: action)
        #expect(!(odd is UIKeyCommand))
        #expect((odd as? UICommand)?.title == "Odd\tCmd+Insert")
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
