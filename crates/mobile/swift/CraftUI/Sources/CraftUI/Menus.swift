import Foundation
import Observation

/// A keyboard shortcut in the portable form (`Cmd+Shift+Z`): modifiers, then one key. `ctrl` is
/// the Control key and `cmd` ⌘, never folded together. The key is one character (letters upper
/// case) or egui's name for it (`Enter`, `ArrowUp`, `F5`).
public struct CraftShortcut: Equatable, Hashable, Sendable {
    public var ctrl = false
    public var cmd = false
    public var alt = false
    public var shift = false
    public var key: String

    /// Parse the portable form; `nil` for anything craft-mobile's `Shortcut::parse` refuses.
    public init?(_ text: String) {
        let modifiers: Substring
        if text == "+" {
            (modifiers, key) = ("", "+")
        } else if text.hasSuffix("++") {
            (modifiers, key) = (text.dropLast(2), "+")
        } else if let plus = text.lastIndex(of: "+") {
            (modifiers, key) = (text[..<plus], String(text[text.index(after: plus)...]))
        } else {
            (modifiers, key) = ("", text)
        }
        guard !key.isEmpty else { return nil }
        if key.count == 1 { key = key.uppercased() }
        if !modifiers.isEmpty {
            for name in modifiers.split(separator: "+", omittingEmptySubsequences: false) {
                switch name {
                case "Ctrl" where !ctrl: ctrl = true
                case "Cmd" where !cmd: cmd = true
                case "Alt" where !alt: alt = true
                case "Shift" where !shift: shift = true
                default: return nil
                }
            }
        }
    }

    /// The portable form, modifiers in craft-mobile's order (`Ctrl+Cmd+Alt+Shift+Key`).
    public var text: String {
        ([(ctrl, "Ctrl"), (cmd, "Cmd"), (alt, "Alt"), (shift, "Shift")].filter(\.0).map(\.1) + [key]).joined(separator: "+")
    }
}

/// One item of a native menu that runs a command (craft-mobile's `ui::MenuCommand`).
public struct CraftMenuCommand: Decodable, Equatable, Sendable {
    public let id: String
    public let label: String
    /// `nil` when it has none, or one this kit can't read.
    public let shortcut: CraftShortcut?
    public let enabled: Bool
    /// `nil`: no check mark.
    public let checked: Bool?

    public init(id: String, label: String, shortcut: CraftShortcut? = nil, enabled: Bool = true, checked: Bool? = nil) {
        (self.id, self.label, self.shortcut, self.enabled, self.checked) = (id, label, shortcut, enabled, checked)
    }

    private enum Key: String, CodingKey { case id, label, shortcut, enabled, checked }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self = try CraftMenuCommand(
            id: c.decode(String.self, forKey: .id), label: c.decode(String.self, forKey: .label),
            shortcut: c.decodeIfPresent(String.self, forKey: .shortcut).flatMap(CraftShortcut.init),
            enabled: c.decode(Bool.self, forKey: .enabled), checked: c.decodeIfPresent(Bool.self, forKey: .checked))
    }

    /// What choosing it sends: its shortcut when it has one, so the app's own key handling decides
    /// (as for the key itself), else its command.
    public var message: CraftChromeMessage {
        shortcut.map { .shortcut($0.text) } ?? .command(id)
    }

    /// The item without its state (enabled, checked on or off): what a menu is built from.
    var structure: CraftMenuCommand {
        CraftMenuCommand(id: id, label: label, shortcut: shortcut, enabled: true, checked: checked.map { _ in false })
    }
}

/// One entry of a menu (`ui::MenuEntry`).
public indirect enum CraftMenuEntry: Decodable, Equatable, Sendable {
    case command(CraftMenuCommand)
    case separator
    case submenu(label: String, items: [CraftMenuEntry])

    private enum Key: String, CodingKey { case type, label, items }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "command": self = try .command(CraftMenuCommand(from: decoder))
        case "separator": self = .separator
        case "submenu": self = try .submenu(label: c.decode(String.self, forKey: .label), items: Self.decodeEach(c, forKey: .items))
        case let type: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown menu entry \(type)")
        }
    }

    /// Entries decoded one by one: one this kit can't read (a newer type, or broken) is skipped.
    static func decodeEach<K: CodingKey>(_ c: KeyedDecodingContainer<K>, forKey key: K) throws -> [CraftMenuEntry] {
        try c.decode([Skippable<CraftMenuEntry>].self, forKey: key).compactMap(\.value)
    }

    var structure: CraftMenuEntry {
        switch self {
        case let .command(command): .command(command.structure)
        case .separator: .separator
        case let .submenu(label, items): .submenu(label: label, items: items.map(\.structure))
        }
    }
}

/// One menu of the bar (`ui::Menu`).
public struct CraftMenu: Decodable, Equatable, Sendable {
    public let title: String
    public let items: [CraftMenuEntry]

    public init(title: String, items: [CraftMenuEntry]) {
        (self.title, self.items) = (title, items)
    }

    private enum Key: String, CodingKey { case title, items }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self = try CraftMenu(title: c.decode(String.self, forKey: .title), items: CraftMenuEntry.decodeEach(c, forKey: .items))
    }
}

/// The app's menu bar (wire kind 15, `ui::MenuBar`). An entry or menu this kit can't read is left
/// out; the rest still show.
public struct CraftMenuBar: Decodable, Equatable, Sendable {
    public let menus: [CraftMenu]

    public init(menus: [CraftMenu] = []) {
        self.menus = menus
    }

    private enum Key: String, CodingKey { case menus }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        menus = try c.decode([Skippable<CraftMenu>].self, forKey: .menus).compactMap(\.value)
    }

    /// The bar without its items' state: when only enabled or checked changed, it's the same, and
    /// the menus needn't be built again.
    public var structure: CraftMenuBar {
        CraftMenuBar(menus: menus.map { CraftMenu(title: $0.title, items: $0.items.map(\.structure)) })
    }

    /// Every command, by id (the first, should one repeat).
    public var commands: [String: CraftMenuCommand] {
        var all: [String: CraftMenuCommand] = [:]
        func walk(_ items: [CraftMenuEntry]) {
            for item in items {
                switch item {
                case let .command(command): if all[command.id] == nil { all[command.id] = command }
                case let .submenu(_, items): walk(items)
                case .separator: break
                }
            }
        }
        menus.forEach { walk($0.items) }
        return all
    }
}

/// One entry of a list, `nil` if it doesn't decode, so the list moves past it.
struct Skippable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: any Decoder) {
        value = try? T(from: decoder)
    }
}

/// The app's menus as the shell shows them: in the iPad menu bar (``CraftMenuDelegate``) and the
/// toolbar menu (``CraftMenuButton``). One per process, like the menu bar.
@MainActor
@Observable
public final class CraftMenus {
    public static let shared = CraftMenus()

    /// The latest menus, state and all.
    public private(set) var bar = CraftMenuBar()
    /// The commands, by id: what the menu bar's items look up when a menu opens.
    @ObservationIgnored private(set) var commands: [String: CraftMenuCommand] = [:]
    /// Where the menus send what the user chose (the app, or the Gallery's log).
    @ObservationIgnored public var send: @MainActor (CraftChromeMessage) -> Void = { _ in }
    /// Called when the menus' structure changed and the menu bar must be built again
    /// (`UIMenuSystem.main.setNeedsRebuild()`; the delegate sets it).
    @ObservationIgnored var rebuild: @MainActor () -> Void = {}

    public init() {}

    /// New menus from the app. The menu bar is built again only when its structure changed; enabled
    /// and checked are read as each menu opens.
    public func update(_ new: CraftMenuBar) {
        guard new != bar else { return }
        let rebuilt = new.structure != bar.structure
        bar = new
        commands = new.commands
        if rebuilt { rebuild() }
    }

    /// The user chose `id` in a menu (or pressed its keys): send it, if the app still has it enabled.
    public func choose(_ id: String) {
        guard let command = commands[id], command.enabled else { return }
        send(command.message)
    }
}
