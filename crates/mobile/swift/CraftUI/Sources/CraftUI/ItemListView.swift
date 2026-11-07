import SwiftUI

/// Rows of items such as layers: tap to select, swipe or tap the eye to hide, long-press to rename,
/// drag to reorder (when `reorderable`).
struct CraftItemListView: View {
    let id: String
    let rows: [CraftRow]
    let reorderable: Bool
    let panel: String
    let send: @MainActor (CraftEdit) -> Void
    @State private var renaming: CraftRow?
    @State private var newName = ""

    var body: some View {
        Section {
            ForEach(rows) { row in
                rowView(row)
            }
            .onMove(perform: reorderable ? { source, destination in move(from: source, to: destination) } : nil)
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
    }

    private func rowView(_ row: CraftRow) -> some View {
        HStack {
            if let visible = row.visible {
                Button { one(.setVisible(row: row.id, visible: !visible)) } label: {
                    Image(systemName: visible ? "eye" : "eye.slash")
                        .foregroundStyle(visible ? .primary : .secondary)
                }
                .buttonStyle(.borderless)
            }
            VStack(alignment: .leading) {
                Text(row.title)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, CGFloat(row.depth) * 16)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { one(.select(row: row.id)) }
        .listRowBackground(row.selected ? Color.accentColor.opacity(0.18) : nil)
        .swipeActions(edge: .trailing) {
            if let visible = row.visible {
                Button(visible ? "Hide" : "Show") { one(.setVisible(row: row.id, visible: !visible)) }
            }
        }
        .contextMenu {
            Button("Rename…") { startRenaming(row) }
        }
        .modifier(RowAccessibility(
            row: row,
            select: { one(.select(row: row.id)) },
            setVisible: { one(.setVisible(row: row.id, visible: $0)) },
            rename: { startRenaming(row) }))
    }

    private func startRenaming(_ row: CraftRow) {
        newName = row.title
        renaming = row
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let row = renaming, !name.isEmpty, name != row.title else { return }
        one(.rename(row: row.id, name: name))
    }

    private func one(_ value: CraftEdit.Value) {
        send(CraftEdit(panel: panel, control: id, phase: .commit, gesture: GestureID.next(), value: value))
    }

    private func move(from source: IndexSet, to destination: Int) {
        if let value = Self.moveEdit(rows, from: source, to: destination) { one(value) }
    }

    /// SwiftUI gives a destination index in the list before the move; the app wants "above or below a
    /// row". `nil` when the drop leaves the row where it was.
    nonisolated static func moveEdit(_ rows: [CraftRow], from source: IndexSet, to destination: Int) -> CraftEdit.Value? {
        guard source.count == 1, let from = source.first, destination != from, destination != from + 1,
              let row = rows[safe: from] else { return nil }
        if let below = rows[safe: destination] {
            return .move(row: row.id, target: below.id, position: .above)
        }
        guard let last = rows.last, last.id != row.id else { return nil }
        return .move(row: row.id, target: last.id, position: .below)
    }
}

/// One VoiceOver element per row: activating it selects the row; hiding and renaming are named actions.
private struct RowAccessibility: ViewModifier {
    let row: CraftRow
    let select: () -> Void
    let setVisible: (Bool) -> Void
    let rename: () -> Void

    func body(content: Content) -> some View {
        let traits: AccessibilityTraits = row.selected ? [.isButton, .isSelected] : [.isButton]
        let label = row.subtitle.isEmpty ? row.title : "\(row.title), \(row.subtitle)"
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityValue(row.visible == false ? "Hidden" : "")
            .accessibilityAddTraits(traits)
            .accessibilityAction { select() }
            .accessibilityActions {
                if let visible = row.visible {
                    Button(visible ? "Hide" : "Show") { setVisible(!visible) }
                }
                Button("Rename", action: rename)
            }
    }
}

// Private: apps compile CraftUI into their own module, where a public-looking `safe:` could clash.
fileprivate extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
