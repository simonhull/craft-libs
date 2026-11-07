import SwiftUI

// The app's native panels in the shell. Only the views here read `bridge.panels` and `bridge.open`,
// so a new description (wire kind 13, at most once a frame) redraws them and not the whole shell.
// The toolbar reads only `bridge.panels`, which changes when the panels offered do, so a drag
// redraws the open panel and not the toolbar or its popovers.

/// What the shell's inspector column holds.
enum CraftInspector: Hashable {
    /// The items panel (`chrome`).
    case items
    /// One of the app's inspector panels, by id.
    case panel(String)

    /// The app's panel, if it is one.
    var panelID: String? {
        if case let .panel(id) = self { id } else { nil }
    }
}

/// The app's panels as toolbar buttons, like the items button: an inspector one toggles the column,
/// a tool one opens its popover. The open one is tinted. Nothing while the app offers none.
struct CraftPanelTools: View {
    let bridge: CraftBridge
    /// The inspector the column shows, if it's open.
    let openInspector: CraftInspector?
    @Binding var popover: String?
    let toggleInspector: (CraftInspector) -> Void

    var body: some View {
        ForEach(bridge.panels) { info in
            switch info.role {
            case .inspector:
                button(info, open: openInspector == .panel(info.id)) { toggleInspector(.panel(info.id)) }
            case .tool:
                button(info, open: popover == info.id) { popover = popover == info.id ? nil : info.id }
                    .popover(isPresented: Binding(get: { popover == info.id }, set: { if !$0, popover == info.id { popover = nil } })) {
                        CraftPopover { CraftPanelHost(bridge: bridge, id: info.id) }
                    }
            }
        }
    }

    private func button(_ info: CraftPanelInfo, open: Bool, action: @escaping () -> Void) -> some View {
        CraftToolButton(label: info.title, symbol: info.icon, action: action)
            .padding(6)
            .glassEffect(open ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .circle)
            .accessibilityAddTraits(open ? .isSelected : [])
    }
}

/// One of the app's panels as described. Until the app describes it, a spinner; if the app answered
/// without it (it offers the panel but can't describe it now), "Not Available".
struct CraftPanelHost: View {
    let bridge: CraftBridge
    let id: String

    var body: some View {
        if let panel = bridge.open[id] {
            CraftPanelView(panel: panel, send: bridge.send)
        } else {
            let title = bridge.panels.first { $0.id == id }?.title ?? ""
            Group {
                if bridge.describedSinceShowing {
                    ContentUnavailableView("Not Available", systemImage: "rectangle.dashed", description: Text("\(title) has nothing to show right now."))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
        }
    }
}

/// Closes a panel the app no longer offers; one it still offers stays open, however often it is
/// described again. Draws nothing.
struct CraftPanelCloser: View {
    let bridge: CraftBridge
    @Binding var inspector: CraftInspector
    @Binding var inspectorShown: Bool
    @Binding var popover: String?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: bridge.panels) { _, offered in
                let ids = Set(offered.map(\.id))
                if let id = inspector.panelID, !ids.contains(id) { inspectorShown = false }
                if let open = popover, !ids.contains(open) { popover = nil }
            }
    }
}

/// Opens a panel the app asked for (wire kind 14) as its toolbar button would: an inspector in the
/// column (another gives way), a tool in its popover. Opening it changes the panels on screen, so
/// the app hears of it and describes it as usual. An id the app doesn't offer opens nothing. Draws
/// nothing.
struct CraftPanelOpener: View {
    let bridge: CraftBridge
    @Binding var inspector: CraftInspector
    @Binding var inspectorShown: Bool
    @Binding var popover: String?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: bridge.openRequest, initial: true) { _, request in
                guard let request else { return }
                bridge.openRequestHandled()
                guard let info = bridge.panels.first(where: { $0.id == request.id }) else {
                    craftLog.debug("the app asked to open panel \(request.id, privacy: .public), which it doesn't offer")
                    return
                }
                withAnimation {
                    switch info.role {
                    case .inspector:
                        inspector = .panel(info.id)
                        inspectorShown = true
                    case .tool:
                        popover = info.id
                    }
                }
            }
    }
}

/// A toolbar button: an SF Symbol, 44 pt square.
struct CraftToolButton: View {
    let label: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
