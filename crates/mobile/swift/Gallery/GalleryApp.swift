import CraftUI
import SwiftUI

/// Every CraftUI primitive from the generated catalogue, live: each in an inspector beside its
/// description and the edits it sent, and as a tool popover from the toolbar.
@main
struct GalleryApp: App {
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
