import CraftUI
import SwiftUI

/// Every CraftUI primitive from the generated catalogue, live: each in an inspector beside its
/// description and the edits it sent, and as a tool popover from the toolbar.
@main
struct GalleryApp: App {
    /// The catalogue's menus in the iPad menu bar, as CraftShell's apps have them.
    @UIApplicationDelegateAdaptor(CraftMenuDelegate.self) private var menus
    @State private var store = GalleryStore()
    /// The sidebar's choice: a primitive's name, or ``GalleryStore/everything``. Kept between launches;
    /// `-selection item_list` on the command line picks one.
    @AppStorage("selection") private var selection: String?

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(selection: $selection) {
                    Section("Primitives") {
                        ForEach(store.entries) { entry in
                            Text(entry.name).monospaced().tag(entry.id)
                        }
                    }
                    Section("Chrome") {
                        ForEach(store.chrome) { chrome in
                            Text(chrome.name).monospaced().tag(chrome.id)
                        }
                    }
                    Section("Panels") {
                        Label("Everything", systemImage: "square.stack.3d.up").tag(GalleryStore.everything)
                    }
                }
                .navigationTitle("CraftUI")
            } detail: {
                detail
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let problem = store.problem {
            ContentUnavailableView("No Catalogue", systemImage: "exclamationmark.triangle", description: Text(problem))
        } else if selection == GalleryStore.everything {
            GalleryDetail(
                title: "Everything", about: "Every example in one panel, as an app's inspector would put them.",
                store: store, panel: store.everythingPanel(role:))
        } else if selection == "menu_bar", let chrome = store.chrome.first(where: { $0.id == "menu_bar" }) {
            GalleryMenuDetail(about: chrome.about, store: store)
        } else if let entry = store.entries.first(where: { $0.id == selection }) {
            GalleryDetail(title: entry.name, about: entry.about, store: store) { store.panel(for: entry, role: $0) }
        } else {
            ContentUnavailableView("Pick a Primitive", systemImage: "square.grid.2x2")
        }
    }
}

/// One primitive (or all of them): what it is and the edits it sent; the panel itself in the
/// inspector, and as a popover from the toolbar.
struct GalleryDetail: View {
    let title: String
    let about: String
    let store: GalleryStore
    let panel: (CraftPanelInfo.Role) -> CraftPanel

    @State private var showsInspector = true
    @State private var showsPopover = false

    var body: some View {
        List {
            Section {
                Text(about)
            }
            Section("Edits Sent") {
                if store.log.isEmpty {
                    Text("Use the controls: each edit shows here as the JSON the app would receive.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.log) { sent in
                    Text(sent.json)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Button("Clear Log", systemImage: "trash") { store.clearLog() }
                    .disabled(store.log.isEmpty)
                Button("Popover", systemImage: "rectangle.on.rectangle") { showsPopover.toggle() }
                    .popover(isPresented: $showsPopover) {
                        CraftPopover { CraftPanelView(panel: panel(.tool), send: store.send) }
                    }
                Button("Inspector", systemImage: "sidebar.trailing") { showsInspector.toggle() }
            }
        }
        .inspector(isPresented: $showsInspector) {
            NavigationStack {
                CraftPanelView(panel: panel(.inspector), send: store.send)
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
    }
}

/// The menu bar: the catalogue's menus in the iPad menu bar (pointer to the top edge, or hold ⌘)
/// and the toolbar's menu button; what each sends, and every key press that reached the view
/// standing in for the canvas (first responder, as CraftCanvas is), so a shortcut that also
/// reached the canvas shows twice.
struct GalleryMenuDetail: View {
    let about: String
    let store: GalleryStore

    var body: some View {
        List {
            Section { Text(about) }
            Section("Canvas") {
                GalleryKeyProbe { store.logLine("key reached the canvas: \($0)") }
                    .frame(height: 44)
                    .overlay { Text("Stands in for the canvas: first responder, takes key presses").foregroundStyle(.secondary) }
            }
            Section("Sent") {
                if store.log.isEmpty {
                    Text("Choose a menu item, or press its keys.").foregroundStyle(.secondary)
                }
                ForEach(store.log) { sent in
                    Text(sent.json).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("menu_bar")
        .toolbar {
            ToolbarItemGroup {
                Button("Clear Log", systemImage: "trash") { store.clearLog() }
                    .disabled(store.log.isEmpty)
                CraftMenuButton(menus: CraftMenus.shared)
            }
        }
    }
}

/// A view that becomes first responder and logs the key presses that reach it, then passes them on,
/// as CraftCanvas does.
struct GalleryKeyProbe: UIViewRepresentable {
    let pressed: (String) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.pressed = pressed
        DispatchQueue.main.async { probe.becomeFirstResponder() }
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.pressed = pressed
    }

    final class Probe: UIView {
        var pressed: (String) -> Void = { _ in }
        private let menuResponder = CraftMenuResponder()
        override var canBecomeFirstResponder: Bool { true }
        override var next: UIResponder? { menuResponder.after(super.next) }

        /// As CraftCanvas does (`CraftKeys.forward`): the app takes each key press, and only one that
        /// types text goes on up the responder chain.
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var rest: Set<UIPress> = []
            for press in presses {
                guard let key = press.key, !key.charactersIgnoringModifiers.isEmpty else {
                    rest.insert(press)
                    continue
                }
                pressed("\(Self.describe(key.modifierFlags))\(key.charactersIgnoringModifiers)")
                let shortcut = key.modifierFlags.contains(.command) || key.modifierFlags.contains(.control)
                if !shortcut { rest.insert(press) }
            }
            super.pressesBegan(rest, with: event)
        }


        static func describe(_ flags: UIKeyModifierFlags) -> String {
            [(UIKeyModifierFlags.control, "⌃"), (.alternate, "⌥"), (.shift, "⇧"), (.command, "⌘")].filter { flags.contains($0.0) }.map(\.1).joined()
        }
    }
}
