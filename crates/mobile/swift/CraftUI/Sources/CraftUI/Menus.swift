import Foundation
import Observation

/// A keyboard shortcut in the portable form (`Cmd+Shift+Z`): modifiers, then one key. `ctrl` is
/// the Control key and `cmd` ⌘, never folded together. The key is one character (letters upper
/// case) or egui's canonical name for it (`Enter`, `ArrowUp`, `F5`), as craft-mobile prints it.
public struct CraftShortcut: Equatable, Hashable, Sendable {
    public var ctrl = false
    public var cmd = false
    public var alt = false
    public var shift = false
    public var key: String

    /// Parse the portable form exactly as craft-mobile's `Shortcut::parse` does (the catalogue's
    /// shortcut cases test both); `nil` for anything it refuses. Named keys must be canonical, as
    /// the app always sends them.
    public init?(_ text: String) {
        let modifiers: Substring?
        let key: Substring
        if text.hasSuffix("++") {
            (modifiers, key) = (text.dropLast(2), "+")
        } else if text == "+" {
            (modifiers, key) = (nil, "+")
        } else if let plus = text.lastIndex(of: "+") {
            (modifiers, key) = (text[..<plus], text[text.index(after: plus)...])
        } else {
            (modifiers, key) = (nil, Substring(text))
        }
        guard let name = Self.keyName(key) else { return nil }
        self.key = name
        for modifier in modifiers.map({ $0.split(separator: "+", omittingEmptySubsequences: false) }) ?? [] {
            switch modifier {
            case "Ctrl" where !ctrl: ctrl = true
            case "Cmd" where !cmd: cmd = true
            case "Alt" where !alt: alt = true
            case "Shift" where !shift: shift = true
            default: return nil
            }
        }
    }

    /// A key press as a shortcut: `key` as CraftKit names hardware keys (egui's names).
    public init(key: String, ctrl: Bool = false, cmd: Bool = false, alt: Bool = false, shift: Bool = false) {
        (self.key, self.ctrl, self.cmd, self.alt, self.shift) = (key, ctrl, cmd, alt, shift)
    }

    /// One printable character (a letter upper-cased), or a canonical named key.
    private static func keyName(_ key: Substring) -> String? {
        if key.count == 1, let c = key.first, !c.isWhitespace, !(c.unicodeScalars.first.map(CharacterSet.controlCharacters.contains) ?? true) {
            return key.uppercased()
        }
        return namedKeys.contains(String(key)) ? String(key) : nil
    }

    /// The named keys craft-mobile prints (`ui::named_keys`, in the catalogue).
    public static let namedKeys: Set<String> = Set([
        "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowUp", "Escape", "Tab", "Backspace", "Enter", "Space", "Insert", "Delete",
        "Home", "End", "PageUp", "PageDown", "Copy", "Cut", "Paste", "Colon", "Comma", "Backslash", "Slash", "Pipe",
        "Questionmark", "Exclamationmark", "OpenBracket", "CloseBracket", "OpenCurlyBracket", "CloseCurlyBracket", "Backtick",
        "Minus", "Period", "Plus", "Equals", "Semicolon", "Quote",
        "BrowserBack", "BrowserForward", "BrowserRefresh", "BrowserSearch", "BrowserHome", "BrowserFavorites", "BrowserStop",
        "MediaPlayPause", "MediaTrackNext", "MediaTrackPrevious", "MediaStop", "AudioVolumeMute", "AudioVolumeDown", "AudioVolumeUp",
        "LaunchMail", "LaunchApp1", "LaunchApp2", "ShiftLeft", "ShiftRight", "ControlLeft", "ControlRight", "AltLeft", "AltRight",
        "SuperLeft", "SuperRight", "IntlBackslash", "CapsLock", "NumLock", "ScrollLock", "PrintScreen", "Pause", "Menu", "Fn",
        "Eject", "Help", "Power", "Sleep", "Clear",
    ]).union((1...35).map { "F\($0)" })

    /// The portable form, modifiers in craft-mobile's order (`Ctrl+Cmd+Alt+Shift+Key`).
    public var text: String {
        ([(ctrl, "Ctrl"), (cmd, "Cmd"), (alt, "Alt"), (shift, "Shift")].filter(\.0).map(\.1) + [key]).joined(separator: "+")
    }

    /// As the Mac and iPad show it, everywhere the kit shows a shortcut: ⌃⌥⇧⌘ then the key (`⇧⌘Z`).
    public var glyphs: String {
        let modifiers = [(ctrl, "⌃"), (alt, "⌥"), (shift, "⇧"), (cmd, "⌘")].filter(\.0).map(\.1).joined()
        return modifiers + (Self.keyGlyphs[key] ?? Self.character[key] ?? key)
    }

    /// The glyph a menu shows for a named key.
    private static let keyGlyphs = [
        "Enter": "↩", "Tab": "⇥", "Space": "Space", "Backspace": "⌫", "Delete": "⌦", "Escape": "⎋",
        "ArrowUp": "↑", "ArrowDown": "↓", "ArrowLeft": "←", "ArrowRight": "→", "PageUp": "⇞", "PageDown": "⇟",
        "Home": "↖", "End": "↘",
    ]

    /// The character a named punctuation key types: `Minus` and `-` are the same key.
    static let character = [
        "Minus": "-", "Equals": "=", "Plus": "+", "Comma": ",", "Period": ".", "Slash": "/", "Backslash": "\\",
        "Semicolon": ";", "Colon": ":", "Quote": "'", "Backtick": "`", "OpenBracket": "[", "CloseBracket": "]",
        "OpenCurlyBracket": "{", "CloseCurlyBracket": "}", "Pipe": "|", "Questionmark": "?", "Exclamationmark": "!",
    ]

    /// Whether ⌘ or ⌃ is held: only such a shortcut is a key command (see ``CraftMenuBuilder``).
    public var hasCommandModifier: Bool { cmd || ctrl }

    /// The same key and modifiers, whichever way the key is spelled (`Minus` or `-`).
    public func sameKeys(as other: CraftShortcut) -> Bool {
        let key = { (s: CraftShortcut) in Self.character[s.key] ?? s.key }
        return (ctrl, cmd, alt, shift) == (other.ctrl, other.cmd, other.alt, other.shift) && key(self) == key(other)
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

    /// The item without its state (label, enabled, checked on or off): what a menu is built from.
    /// The rest is read as its menu opens (`validate(_:)`), so changing it needs no rebuild.
    var structure: CraftMenuCommand {
        CraftMenuCommand(id: id, label: "", shortcut: shortcut, enabled: true, checked: checked.map { _ in false })
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
    /// The system menu an app menu takes the place of (`ui::MenuRole`), matched by role, never by
    /// its translated title.
    public enum Role: String, Decodable, Sendable { case file, edit, view, window, help }

    public let title: String
    /// `nil` for a menu of the app's own (also when the app doesn't say, or says a role this kit
    /// doesn't know).
    public let role: Role?
    public let items: [CraftMenuEntry]

    public init(title: String, role: Role? = nil, items: [CraftMenuEntry]) {
        (self.title, self.role, self.items) = (title, role, items)
    }

    private enum Key: String, CodingKey { case title, role, items }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let role = (try? c.decodeIfPresent(String.self, forKey: .role)).flatMap { $0 }.flatMap(Role.init(rawValue:))
        self = try CraftMenu(title: c.decode(String.self, forKey: .title), role: role, items: CraftMenuEntry.decodeEach(c, forKey: .items))
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
        CraftMenuBar(menus: menus.map { CraftMenu(title: $0.title, role: $0.role, items: $0.items.map(\.structure)) })
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

    /// Whether a key press is an enabled menu item's key command: the canvas then lets it go on to
    /// the key command (which sends it as a `shortcut`, once) instead of taking it itself.
    public func claims(_ press: CraftShortcut) -> Bool {
        guard press.hasCommandModifier else { return false }
        return commands.values.contains { command in
            command.enabled && command.shortcut.map { $0.hasCommandModifier && $0.sameKeys(as: press) } == true
        }
    }

    /// The user chose `id` in a menu (or pressed its keys): send it, if the app still has it enabled.
    public func choose(_ id: String) {
        guard let command = commands[id], command.enabled else { return }
        send(command.message)
    }
}
