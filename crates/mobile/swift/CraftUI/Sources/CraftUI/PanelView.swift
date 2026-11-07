import SwiftUI

/// Draws one described panel. `send` delivers edits to the app; it is called only for the user's own
/// gestures, never when a value from the app is shown.
public struct CraftPanelView: View {
    let panel: CraftPanel
    let send: @MainActor (CraftEdit) -> Void

    public init(panel: CraftPanel, send: @escaping @MainActor (CraftEdit) -> Void) {
        self.panel = panel
        self.send = send
    }

    public var body: some View {
        Form {
            ForEach(panel.nodes, id: \.id) { node in
                CraftNodeView(node: node, panel: panel.id, send: send)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(panel.title)
    }
}

struct CraftNodeView: View {
    let node: CraftNode
    let panel: String
    let send: @MainActor (CraftEdit) -> Void

    var body: some View {
        switch node {
        case let .section(_, title, collapsed, children):
            CraftSectionView(title: title, collapsed: collapsed) {
                ForEach(children, id: \.id) { CraftNodeView(node: $0, panel: panel, send: send) }
            }
        case let .number(id, label, value, min, max, step, unit, enabled):
            // The app checks `min <= max`; a bad range still must not trap here.
            CraftNumberView(
                id: id, label: label, value: value, range: min <= max ? min...max : min...min, step: step, unit: unit,
                panel: panel, send: send)
                .disabled(!enabled)
        case let .toggle(id, label, value, enabled):
            CraftToggleView(id: id, label: label, value: value, panel: panel, send: send)
                .disabled(!enabled)
        case let .choice(id, label, value, options, enabled):
            CraftChoiceView(id: id, label: label, value: value, options: options, panel: panel, send: send)
                .disabled(!enabled)
        case let .itemList(id, rows, reorderable):
            CraftItemListView(id: id, rows: rows, reorderable: reorderable, panel: panel, send: send)
        case let .unknown(type):
            Label("Needs a newer CraftKit: \(type)", systemImage: "questionmark.square.dashed")
                .foregroundStyle(.secondary)
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
    ])

    /// A tool popover with a menu choice and stepped numbers, for previews.
    static let previewBrush = CraftPanel(id: "brush", title: "Brush", role: .tool, nodes: [
        .number(id: "size", label: "Size", value: 24, min: 1, max: 500, step: 1, unit: .pixels, enabled: true),
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
