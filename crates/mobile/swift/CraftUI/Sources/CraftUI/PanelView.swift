import SwiftUI

/// Draws one described panel. `send` delivers edits to the app; it is called only for the user's own
/// gestures, never when a value from the app is shown.
///
/// `descriptions` counts the descriptions the app has sent, changed or not (a refused edit is
/// answered with the panel again, unchanged): a number control shows the value its drag ended on
/// until the next one.
public struct CraftPanelView: View {
    let panel: CraftPanel
    let descriptions: UInt64
    let send: @MainActor (CraftEdit) -> Void

    public init(panel: CraftPanel, descriptions: UInt64 = 0, send: @escaping @MainActor (CraftEdit) -> Void) {
        self.panel = panel
        self.descriptions = descriptions
        self.send = send
    }

    public var body: some View {
        Form {
            ForEach(CraftNodeView.keyed(panel.nodes), id: \.key) { item in
                CraftNodeView(node: item.node, panel: panel.id, send: send)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(panel.title)
        .environment(\.craftDescriptions, descriptions)
    }
}

extension EnvironmentValues {
    /// How many descriptions of the panel the app has sent (``CraftPanelView``'s `descriptions`).
    @Entry var craftDescriptions: UInt64 = 0
}

struct CraftNodeView: View {
    let node: CraftNode
    let panel: String
    let send: @MainActor (CraftEdit) -> Void

    var body: some View {
        switch node {
        case let .section(_, title, collapsed, children):
            CraftSectionView(title: title, collapsed: collapsed) {
                ForEach(Self.keyed(children), id: \.key) { CraftNodeView(node: $0.node, panel: panel, send: send) }
            }
        case let .number(id, label, value, min, max, step, unit, enabled, scale):
            // The app checks `min <= max`; a bad range still must not trap here.
            CraftNumberView(
                id: id, label: label, value: value, range: min <= max ? min...max : min...min, step: step, unit: unit,
                scale: scale, panel: panel, send: send)
                .disabled(!enabled)
        case let .toggle(id, label, value, enabled):
            CraftToggleView(id: id, label: label, value: value, panel: panel, send: send)
                .disabled(!enabled)
        case let .choice(id, label, value, options, enabled):
            CraftChoiceView(id: id, label: label, value: value, options: options, panel: panel, send: send)
                .disabled(!enabled)
        case let .itemList(id, rows, reorderable):
            CraftItemListView(id: id, rows: rows, reorderable: reorderable, panel: panel, send: send)
        case let .toolPalette(palette):
            // In a panel, a row of the same tools; the rail itself is the shell's (`rail` role).
            ScrollView(.horizontal) {
                CraftRailView(palette: palette.withoutOptions, panel: panel, axis: .horizontal, send: send, command: { _ in }, optionsPanel: .constant(nil)) { _ in
                    EmptyView()
                }
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
        case let .unknown(type):
            Label("Needs a newer CraftKit: \(type)", systemImage: "questionmark.square.dashed")
                .foregroundStyle(.secondary)
        case let .malformed(type):
            Label("This \(type) couldn't be shown", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    /// Each node with a key unique among its siblings: its id, and `#n` for the n-th repeat. The app
    /// keeps ids unique, but placeholders share theirs, and a repeat mustn't take another's view.
    /// A node keeps its key (and its view, a drag in progress) when others come and go.
    nonisolated static func keyed(_ nodes: [CraftNode]) -> [(key: String, node: CraftNode)] {
        var seen: [String: Int] = [:]
        return nodes.map { node in
            let id = node.id
            let count = seen[id, default: 0]
            seen[id] = count + 1
            return (count == 0 ? id : "\(id)#\(count)", node)
        }
    }
}

#if DEBUG
#Preview("Layers inspector") {
    NavigationStack {
        CraftPanelView(panel: .previewLayers, send: { print($0) })
    }
}

#Preview("Layers inspector, dark") {
    NavigationStack {
        CraftPanelView(panel: .previewLayers, send: { print($0) })
    }
    .preferredColorScheme(.dark)
}

#Preview("Brush popover") {
    NavigationStack {
        CraftPanelView(panel: .previewBrush, send: { print($0) })
    }
}

extension CraftPanel {
    /// The catalogue's examples as a Layers inspector, for previews.
    static let previewLayers = CraftPanel(id: "layers", title: "Layers", role: .inspector, nodes: [
        .choice(id: "blend", label: "Blend Mode", value: "normal", options: [
            .init(id: "normal", label: "Normal"), .init(id: "multiply", label: "Multiply"), .init(id: "screen", label: "Screen"),
        ], enabled: true),
        .number(id: "opacity", label: "Opacity", value: 0.8, min: 0, max: 1, step: nil, unit: .percent, enabled: true),
        .section(id: "layer", title: "Layer", collapsed: false, children: [
            .toggle(id: "locked", label: "Lock", value: false, enabled: true),
        ]),
        .itemList(id: "layers", rows: [
            .init(id: 2, title: "Sky", subtitle: "Pixel", depth: 0, visible: true, selected: true),
            .init(id: 1, title: "Background", subtitle: "Pixel", depth: 0, visible: false, selected: false),
        ], reorderable: true),
        .unknown(type: "hologram"),
        .malformed(type: "number"),
    ])

    /// A tool popover with a menu choice, stepped numbers (Size on a log scale) and a collapsed
    /// section, for previews.
    static let previewBrush = CraftPanel(id: "brush", title: "Brush", role: .tool, nodes: [
        .number(id: "size", label: "Size", value: 24, min: 1, max: 5000, step: 1, unit: .pixels, enabled: true, scale: .log),
        .number(id: "angle", label: "Angle", value: 45, min: 0, max: 360, step: 1, unit: .degrees, enabled: false),
        .choice(id: "tip", label: "Tip", value: "round", options: [
            .init(id: "round", label: "Round"), .init(id: "square", label: "Square"), .init(id: "chalk", label: "Chalk"),
            .init(id: "ink", label: "Ink"), .init(id: "spray", label: "Spray"),
        ], enabled: true),
        .section(id: "dynamics", title: "Dynamics", collapsed: true, children: [
            .toggle(id: "pressure", label: "Pressure", value: true, enabled: true),
        ]),
    ])
}
#endif
