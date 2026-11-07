#if os(iOS)
import UIKit

/// Builds the iPad menu bar's menus from the app's (``CraftMenuBar``). Pure: the same bar always
/// builds the same menus, so it's tested without a menu system.
///
/// - Each menu is a `UIMenu`; separators split its items into inline groups.
/// - An item with a ⌘ or ⌃ shortcut is a `UIKeyCommand`, so the menu shows its keys; one without,
///   a `UICommand`. Any other shortcut (a bare letter, ⌥ or ⇧ alone, a function key) or one UIKit
///   can't press is a `UICommand` titled with the keys: the canvas passes such presses on as typed
///   text, and a key command would then run them a second time.
///
/// A shortcut runs once either way: the first responder gets a key press before any key command,
/// and the canvas takes every press with ⌘ or ⌃ for the app's own key handling, so the menu's key
/// command never fires for it. Chosen from the menu, the item sends the same shortcut.
/// - Every item's `propertyList` is its command id and its action `action`; its label, enabled and
///   checked are set again by `validate(_:)` (``CraftMenuResponder``), so changing them needs no
///   rebuild.
public enum CraftMenuBuilder {
    /// The menus, left to right. `action` is the selector the items send.
    @MainActor
    public static func menus(_ bar: CraftMenuBar, action: Selector) -> [UIMenu] {
        bar.menus.enumerated().map { index, menu in
            UIMenu(title: menu.title, identifier: identifier(index, menu.title), children: elements(menu.items, action: action))
        }
    }

    /// The menu's identifier: unique in the bar, and stable while its place and title are.
    static func identifier(_ index: Int, _ title: String) -> UIMenu.Identifier {
        UIMenu.Identifier("dev.craft.menu.\(index).\(title)")
    }

    @MainActor
    static func elements(_ items: [CraftMenuEntry], action: Selector) -> [UIMenuElement] {
        // Groups between separators; one group needs no wrapping.
        var groups: [[UIMenuElement]] = [[]]
        for item in items {
            switch item {
            case .separator:
                if groups.last?.isEmpty == false { groups.append([]) }
            case let .command(command):
                groups[groups.count - 1].append(element(command, action: action))
            case let .submenu(label, children):
                groups[groups.count - 1].append(UIMenu(title: label, children: elements(children, action: action)))
            }
        }
        groups.removeAll(where: \.isEmpty)
        guard groups.count > 1 else { return groups.first ?? [] }
        return groups.map { UIMenu(title: "", options: .displayInline, children: $0) }
    }

    @MainActor
    static func element(_ command: CraftMenuCommand, action: Selector) -> UIMenuElement {
        let id = command.id
        guard let shortcut = command.shortcut, isKeyCommand(shortcut), let input = input(shortcut.key) else {
            return UICommand(title: title(command), action: action, propertyList: id)
        }
        return UIKeyCommand(title: title(command), action: action, input: input, modifierFlags: flags(shortcut), propertyList: id)
    }

    /// Whether the item's shortcut is a key command: only with ⌘ or ⌃ (and a key UIKit can press).
    static func isKeyCommand(_ shortcut: CraftShortcut) -> Bool {
        shortcut.hasCommandModifier && input(shortcut.key) != nil
    }

    /// The item's title: its label, and the keys after it when they aren't a key command (UIKit
    /// shows a key command's keys itself). Set again as its menu opens (`validate(_:)`), so a new
    /// label needs no rebuild.
    static func title(_ command: CraftMenuCommand) -> String {
        guard let shortcut = command.shortcut, !isKeyCommand(shortcut) else { return command.label }
        return "\(command.label)\t\(shortcut.glyphs)"
    }

    /// UIKit's input string for a key, or `nil` for one it can't press.
    static func input(_ key: String) -> String? {
        if key.count == 1 { return key.lowercased() }
        if let n = key.dropFirst().wholeNumber, key.hasPrefix("F") { return functionKeys[safe: n - 1] }
        return named[key]
    }

    static func flags(_ shortcut: CraftShortcut) -> UIKeyModifierFlags {
        var flags: UIKeyModifierFlags = []
        if shortcut.cmd { flags.insert(.command) }
        if shortcut.ctrl { flags.insert(.control) }
        if shortcut.alt { flags.insert(.alternate) }
        if shortcut.shift { flags.insert(.shift) }
        return flags
    }

    private static let functionKeys = [
        UIKeyCommand.f1, UIKeyCommand.f2, UIKeyCommand.f3, UIKeyCommand.f4, UIKeyCommand.f5, UIKeyCommand.f6,
        UIKeyCommand.f7, UIKeyCommand.f8, UIKeyCommand.f9, UIKeyCommand.f10, UIKeyCommand.f11, UIKeyCommand.f12,
    ]

    private static let named: [String: String] = [
        "Enter": "\r", "Tab": "\t", "Space": " ", "Backspace": "\u{8}", "Escape": UIKeyCommand.inputEscape,
        "Delete": UIKeyCommand.inputDelete, "Home": UIKeyCommand.inputHome, "End": UIKeyCommand.inputEnd,
        "PageUp": UIKeyCommand.inputPageUp, "PageDown": UIKeyCommand.inputPageDown,
        "ArrowUp": UIKeyCommand.inputUpArrow, "ArrowDown": UIKeyCommand.inputDownArrow,
        "ArrowLeft": UIKeyCommand.inputLeftArrow, "ArrowRight": UIKeyCommand.inputRightArrow,
        "Minus": "-", "Equals": "=", "Plus": "+", "Comma": ",", "Period": ".", "Slash": "/", "Backslash": "\\",
        "Semicolon": ";", "Quote": "'", "Backtick": "`", "OpenBracket": "[", "CloseBracket": "]",
    ]
}

private extension Substring {
    var wholeNumber: Int? { Int(self) }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// The app delegate that puts the app's menus (``CraftMenus``) in the iPad menu bar. Add it to the
/// app with `@UIApplicationDelegateAdaptor(CraftMenuDelegate.self) private var menus`.
///
/// The menus are built only when their structure changes. Their items act through
/// ``CraftMenuResponder``, which the canvas puts in the responder chain: under SwiftUI the
/// application's delegate is SwiftUI's own, which forwards `buildMenu(with:)` here but never an
/// item's action or `validate(_:)`.
open class CraftMenuDelegate: UIResponder, UIApplicationDelegate {
    public override init() {
        super.init()
        MainActor.assumeIsolated {
            CraftMenus.shared.rebuild = { UIMenuSystem.main.setNeedsRebuild() }
        }
    }

    open override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        let (menus, roles) = MainActor.assumeIsolated {
            let bar = CraftMenus.shared.bar
            return (CraftMenuBuilder.menus(bar, action: CraftMenuResponder.action), bar.menus.map(\.role))
        }
        Self.install(menus, roles: roles, in: builder)
    }

    /// Put the app's menus in the bar by their role, never by title (titles are translated): a
    /// File, Edit, View or Help menu takes the system menu's place; a Window menu's items go before
    /// the system's window items; a menu of the app's own goes before Window. The system's Format
    /// menu is for text views, which the app doesn't have.
    static func install(_ menus: [UIMenu], roles: [CraftMenu.Role?], in builder: any UIMenuBuilder) {
        builder.remove(menu: .format)
        for (menu, role) in zip(menus, roles) {
            switch Self.placement(role) {
            case let .replace(system) where builder.menu(for: system) != nil:
                builder.replace(menu: system, with: menu)
            case .startOfWindow where builder.menu(for: .window) != nil:
                builder.insertChild(UIMenu(title: "", options: .displayInline, children: menu.children), atStartOfMenu: .window)
            default:
                if builder.menu(for: .window) != nil {
                    builder.insertSibling(menu, beforeMenu: .window)
                } else {
                    builder.insertSibling(menu, afterMenu: .application)
                }
            }
        }
    }

    /// Where a menu of `role` goes in the bar.
    enum Placement: Equatable {
        case replace(UIMenu.Identifier)
        case startOfWindow
        case beforeWindow
    }

    static func placement(_ role: CraftMenu.Role?) -> Placement {
        switch role {
        case .file: .replace(.file)
        case .edit: .replace(.edit)
        case .view: .replace(.view)
        case .help: .replace(.help)
        case .window: .startOfWindow
        case nil: .beforeWindow
        }
    }
}

/// Where the menu bar's items act: chosen (or their keys pressed), they send what the app's menus
/// say (``CraftMenus/choose(_:)``); as a menu opens, each item's enabled and checked state comes
/// from the latest menus (`validate(_:)`), so a state change needs no rebuild, and a disabled
/// item's keys pass on to the first responder.
///
/// The view that is first responder while the app has the keyboard (the canvas) puts it in the
/// responder chain, after itself:
///
/// ```swift
/// private let menuResponder = CraftMenuResponder()
/// override var next: UIResponder? { menuResponder.after(super.next) }
/// ```
public final class CraftMenuResponder: UIResponder {
    /// The selector every menu bar item sends.
    public static let action = #selector(craftMenuCommand(_:))

    private weak var following: UIResponder?

    /// This responder, followed by `next` (the view's own next responder).
    public func after(_ next: UIResponder?) -> UIResponder {
        following = next
        return self
    }

    public override var next: UIResponder? { following }

    @objc func craftMenuCommand(_ sender: UICommand) {
        guard let id = sender.propertyList as? String else { return }
        MainActor.assumeIsolated { CraftMenus.shared.choose(id) }
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard action == Self.action else { return super.canPerformAction(action, withSender: sender) }
        // A disabled item's keys aren't taken: they reach the first responder as a press.
        guard let id = (sender as? UICommand)?.propertyList as? String else { return true }
        return MainActor.assumeIsolated { CraftMenus.shared.commands[id]?.enabled ?? false }
    }

    public override func validate(_ command: UICommand) {
        super.validate(command)
        guard command.action == Self.action, let id = command.propertyList as? String else { return }
        guard let item = MainActor.assumeIsolated({ CraftMenus.shared.commands[id] }) else {
            command.attributes = .disabled
            return
        }
        command.title = CraftMenuBuilder.title(item)
        command.attributes = item.enabled ? [] : .disabled
        command.state = item.checked == true ? .on : .off
    }
}

/// Which responder is first, if any: UIKit only says by sending an action to it.
@MainActor
public enum CraftFirstResponder {
    private static weak var found: UIResponder?

    /// The first responder, or `nil` when there is none.
    public static func current() -> UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.craftReportFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    fileprivate static func report(_ responder: UIResponder) {
        found = responder
    }
}

extension UIResponder {
    /// Sent to the first responder by ``CraftFirstResponder/current()``.
    @objc fileprivate func craftReportFirstResponder() {
        MainActor.assumeIsolated { CraftFirstResponder.report(self) }
    }
}
#endif
