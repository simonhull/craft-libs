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
        } else if selection == "status", let chrome = store.chrome.first(where: { $0.id == "status" }) {
            GalleryStatusDetail(about: chrome.about, store: store)
        } else if selection == "tool_palette", let entry = store.entries.first(where: { $0.id == selection }) {
            GalleryDetail(title: entry.name, about: entry.about, store: store) { store.panel(for: entry, role: $0) }
                .overlay(alignment: .leading) { GalleryRail(store: store).padding(.leading, 16) }
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
/// standing in for the canvas (first responder, as CraftCanvas is), so a shortcut that ran twice
/// shows twice. A native field takes the keyboard and gives it back, as a typed number does.
struct GalleryMenuDetail: View {
    let about: String
    let store: GalleryStore
    @State private var typed = ""

    var body: some View {
        List {
            Section { Text(about) }
            Section("Canvas") {
                GalleryKeyProbe { store.logLine("key reached the canvas: \($0)") }
                    .frame(height: 44)
                    .overlay {
                        Text("Stands in for the canvas: first responder, takes key presses").foregroundStyle(.secondary).allowsHitTesting(false)
                    }
            }
            Section("A Native Field") {
                // As a typed number or a rename takes the keyboard from the canvas, then gives it back.
                TextField("Type here", text: $typed).accessibilityIdentifier("field")
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

/// A view that becomes first responder and logs the key presses that reach it, as CraftCanvas does:
/// the same menu responder after it, the same rule for which presses go on to the menu's key
/// commands, and first responder taken back on a touch or when a native field ends editing.
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
        private var ended: NSObjectProtocol?
        override var canBecomeFirstResponder: Bool { true }
        override var next: UIResponder? { menuResponder.after(super.next) }

        override init(frame: CGRect) {
            super.init(frame: frame)
            ended = NotificationCenter.default.addObserver(forName: UITextField.textDidEndEditingNotification, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if CraftFirstResponder.current() == nil { self?.becomeFirstResponder() }
                    }
                }
            }
        }

        required init?(coder: NSCoder) { nil }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if !isFirstResponder { becomeFirstResponder() }
            super.touchesBegan(touches, with: event)
        }

        /// The app takes each key press, except an enabled menu item's key command, which goes on to
        /// the menu; of the rest, only one that types text goes on up the responder chain.
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var rest: Set<UIPress> = []
            for press in presses {
                guard let key = press.key, !key.charactersIgnoringModifiers.isEmpty else {
                    rest.insert(press)
                    continue
                }
                let flags = key.modifierFlags
                let shortcut = CraftShortcut(
                    key: key.charactersIgnoringModifiers.uppercased(), ctrl: flags.contains(.control), cmd: flags.contains(.command),
                    alt: flags.contains(.alternate), shift: flags.contains(.shift))
                NSLog("Gallery canvas pressesBegan \(shortcut.text)")
                if CraftMenus.shared.claims(shortcut) {
                    rest.insert(press)
                    continue
                }
                pressed(shortcut.glyphs.lowercased())
                if !shortcut.hasCommandModifier { rest.insert(press) }
            }
            super.pressesBegan(rest, with: event)
        }
    }
}

/// The catalogue's tool palette as the shell's rail: picks are applied and logged; options open a
/// stand-in Tool panel as a popover from the rail, or log the fallback command.
struct GalleryRail: View {
    let store: GalleryStore
    @State private var options: String?

    var body: some View {
        if let palette = store.palette {
            CraftRailView(
                palette: palette, panel: "tools", send: store.send,
                command: { store.logMessage(CraftChromeMessage.command($0)) }, optionsPanel: $options
            ) { id in
                CraftPanelView(panel: store.optionsPanel(id), send: store.send)
            }
        }
    }
}

/// The status: the catalogue's example over the detail, as the shell shows it over the canvas, with
/// buttons that play the app setting a new message or a job. Cancel is logged.
struct GalleryStatusDetail: View {
    let about: String
    @Bindable var store: GalleryStore

    var body: some View {
        List {
            Section { Text(about) }
            Section("The App Says") {
                Button("Saved") { store.status = CraftStatus(message: .init(text: "Saved a.psd"), progress: store.status.progress) }
                Button("Error") { store.status = CraftStatus(message: .init(text: "Couldn't open b.psd: not a Photoshop file", tone: .error), progress: store.status.progress) }
                Button("Start a Job") { store.status = CraftStatus(message: store.status.message, progress: .init(label: "Exporting a.png", fraction: 0.4, cancel: "job.cancel")) }
                Button("Finish the Job") { store.status = CraftStatus(message: store.status.message) }
            }
            Section("Sent") {
                ForEach(store.log) { sent in
                    Text(sent.json).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("status")
        .overlay {
            CraftStatusView(status: store.status) { store.logMessage(CraftChromeMessage.command($0)) }
        }
    }
}
