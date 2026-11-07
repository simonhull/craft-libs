import SwiftUI

/// The app's menus as one toolbar button ("ellipsis.circle"), for touch: the same tree as the menu
/// bar, each menu a submenu. Choosing an item sends what the menu bar would (``CraftMenus/choose(_:)``).
/// Nothing while the app has no menus.
public struct CraftMenuButton: View {
    let menus: CraftMenus

    public init(menus: CraftMenus) {
        self.menus = menus
    }

    public var body: some View {
        if !menus.bar.menus.isEmpty {
            Menu {
                ForEach(Array(menus.bar.menus.enumerated()), id: \.offset) { _, menu in
                    Menu(menu.title) { CraftMenuItems(items: menu.items, choose: menus.choose) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Menus")
        }
    }
}

/// A menu's entries as SwiftUI menu content: separators as dividers, submenus as menus, a checked
/// item with a check mark and a shortcut as the item's trailing text.
struct CraftMenuItems: View {
    let items: [CraftMenuEntry]
    let choose: @MainActor (String) -> Void

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            switch item {
            case .separator:
                Divider()
            case let .submenu(label, children):
                Menu(label) { CraftMenuItems(items: children, choose: choose) }
            case let .command(command):
                Button {
                    choose(command.id)
                } label: {
                    if command.checked == true {
                        Label(command.label, systemImage: "checkmark")
                    } else {
                        Text(command.label)
                    }
                    if let shortcut = command.shortcut { Text(CraftMenuItems.symbols(shortcut)) }
                }
                .disabled(!command.enabled)
            }
        }
    }

    /// A shortcut as the Mac and iPad show it: ⌃⌥⇧⌘ then the key (`⇧⌘Z`).
    nonisolated static func symbols(_ shortcut: CraftShortcut) -> String {
        let modifiers = [(shortcut.ctrl, "⌃"), (shortcut.alt, "⌥"), (shortcut.shift, "⇧"), (shortcut.cmd, "⌘")].filter(\.0).map(\.1).joined()
        let keys = [
            "Enter": "↩", "Tab": "⇥", "Space": "Space", "Backspace": "⌫", "Delete": "⌦", "Escape": "⎋",
            "ArrowUp": "↑", "ArrowDown": "↓", "ArrowLeft": "←", "ArrowRight": "→", "PageUp": "⇞", "PageDown": "⇟",
            "Home": "↖", "End": "↘",
        ]
        return modifiers + (keys[shortcut.key] ?? shortcut.key)
    }
}
