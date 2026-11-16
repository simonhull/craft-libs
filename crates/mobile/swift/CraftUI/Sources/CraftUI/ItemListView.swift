import SwiftUI

/// Rows of items such as layers: tap to select, swipe or tap the eye to hide, long-press to rename
/// (unless the row says it can't be) or for the row's own actions (a destructive one is a swipe too), drag to reorder (when `reorderable`). Select (under the list) picks several rows, a tap adding or
/// removing each, until Done; with a hardware keyboard, Command-tap does the same and Shift-tap
/// selects a range. Selected rows are tinted. Select and the list's own actions (New Layer, as icon
/// buttons) share one row under the list, as a layers panel's.
struct CraftItemListView: View {
    let id: String
    let rows: [CraftRow]
    let reorderable: Bool
    /// The list's own actions, for the footer.
    var actions: [CraftItemAction] = []
    let panel: String
    let send: @MainActor (CraftEdit) -> Void
    @State private var renaming: CraftRow?
    @State private var newName = ""
    /// Picking several rows: every tap adds or removes one.
    @State private var multiSelecting = false

    var body: some View {
        Section {
            ForEach(rows) { row in
                rowView(row)
            }
            .onMove(perform: reorderable ? { source, destination in move(from: source, to: destination) } : nil)
        } footer: {
            if rows.count > 1 || !actions.isEmpty {
                footer
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
    }

    private func rowView(_ row: CraftRow) -> some View {
        HStack {
            if multiSelecting {
                Image(systemName: row.selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.selected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
            }
            if let visible = row.visible {
                // Neutral, as the row's text: an accent eye on every row reads as a selection.
                Button { one(.setVisible(row: row.id, visible: !visible)) } label: {
                    Image(systemName: visible ? "eye" : "eye.slash")
                        .font(.body.weight(.medium))
                        .frame(minWidth: 32, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .tint(visible ? .primary : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(.subheadline).foregroundStyle(.craftSecondaryText)
                }
            }
            .padding(.leading, CGFloat(row.depth) * 16)
            Spacer()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .modifiedTap { select(row, modifiers: $0) }
        .listRowBackground(row.selected ? Color.accentColor.opacity(0.25) : nil)
        .swipeActions(edge: .trailing) {
            // The first is the full swipe's: a destructive action is never run by a swipe alone.
            if let visible = row.visible {
                Button(visible ? "Hide" : "Show") { one(.setVisible(row: row.id, visible: !visible)) }
            }
            ForEach(Self.swipeActions(row)) { action in
                actionButton(action, row: row)
            }
        }
        .contextMenu {
            if row.rename == .allowed {
                Button("Rename…", systemImage: "pencil") { startRenaming(row) }
            }
            if !row.actions.isEmpty {
                if row.rename == .allowed { Divider() }
                ForEach(row.actions) { action in
                    actionButton(action, row: row)
                }
            }
        }
        .modifier(RowAccessibility(
            row: row,
            select: { select(row, modifiers: []) },
            setVisible: { one(.setVisible(row: row.id, visible: $0)) },
            rename: { startRenaming(row) },
            act: { one(.action(row: row.id, action: $0.id)) }))
    }

    /// Under the list: Select (when there are rows to pick) leading, and the list's own actions
    /// trailing, as bordered buttons in the label's colour (the accent as text on the grouped
    /// background is under 4.5:1), each a 44 pt target.
    private var footer: some View {
        HStack(spacing: 8) {
            if rows.count > 1 {
                Button {
                    withAnimation { multiSelecting.toggle() }
                } label: {
                    Text(multiSelecting ? "Done" : "Select")
                        .font(.body.weight(multiSelecting ? .semibold : .medium))
                        .padding(.horizontal, 4)
                        .frame(minHeight: 30)
                }
                .buttonStyle(.bordered)
                // A colour: in a footer, `.primary` is the faint level.
                .tint(Color.primary)
                .accessibilityHint(multiSelecting ? "Stop picking rows" : "Pick several rows")
            }
            Spacer(minLength: 0)
            ForEach(actions) { action in
                Button {
                    send(Self.listActionEdit(action, panel: panel, control: id))
                } label: {
                    Group {
                        if let icon = action.icon {
                            Image(systemName: icon).font(.body.weight(.medium))
                        } else {
                            Text(action.label).font(.body.weight(.medium))
                        }
                    }
                    .frame(minWidth: 30, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(action.icon == nil ? .capsule : .circle)
                .tint(action.destructive ? Color.red : Color.primary)
                .accessibilityLabel(action.label)
                .help(action.label)
            }
        }
        .textCase(nil)
        .padding(.top, 4)
    }

    /// The edit a footer button sends: one commit, in a gesture of its own.
    nonisolated static func listActionEdit(_ action: CraftItemAction, panel: String, control: String) -> CraftEdit {
        CraftEdit(panel: panel, control: control, phase: .commit, gesture: GestureID.next(), value: .listAction(action: action.id))
    }

    /// One of the row's actions, red when destructive.
    private func actionButton(_ action: CraftItemAction, row: CraftRow) -> some View {
        Button(role: action.destructive ? .destructive : nil) {
            one(.action(row: row.id, action: action.id))
        } label: {
            if let icon = action.icon {
                Label(action.label, systemImage: icon)
            } else {
                Text(action.label)
            }
        }
    }

    /// The row's actions offered as a trailing swipe: the destructive ones, in the app's order.
    nonisolated static func swipeActions(_ row: CraftRow) -> [CraftItemAction] {
        row.actions.filter(\.destructive)
    }

    private func select(_ row: CraftRow, modifiers: EventModifiers) {
        one(.select(row: row.id, mode: Self.selectMode(multiSelecting: multiSelecting, modifiers: modifiers)))
    }

    /// How a tap with `modifiers` held changes the selection: Command adds or removes the row (and
    /// wins over Shift, as on the desktop), Shift selects a range, a plain tap selects the row alone,
    /// or adds or removes it while picking several.
    nonisolated static func selectMode(multiSelecting: Bool, modifiers: EventModifiers) -> CraftEdit.SelectMode {
        if modifiers.contains(.command) { return .toggle }
        if modifiers.contains(.shift) { return .range }
        return multiSelecting ? .toggle : .replace
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
    /// row". The list is flat, a row's `depth` its nesting, so:
    /// - A row's subtree (the rows after it that are deeper) moves with it in the app, so a drop
    ///   between its own descendants, or just below the last of them, is refused: a group can't go
    ///   inside itself.
    /// - Past the last row is the bottom of the top level: below the outermost group the list ends in
    ///   (the last top-level row), not inside it after its last child.
    /// - Anywhere else is above the row the drop lands before.
    ///
    /// A drop where the row was sends nothing, the last row's too (SwiftUI can't tell that from past
    /// the end), so it stays in its group.
    ///
    /// `nil` when the drop is refused or leaves the row where it was.
    nonisolated static func moveEdit(_ rows: [CraftRow], from source: IndexSet, to destination: Int) -> CraftEdit.Value? {
        guard source.count == 1, let from = source.first, destination != from, destination != from + 1,
              let row = rows[safe: from] else { return nil }
        let subtreeEnd = rows[(from + 1)...].firstIndex { $0.depth <= row.depth } ?? rows.endIndex
        if destination > from, destination <= subtreeEnd { return nil }
        if let below = rows[safe: destination] {
            return .move(row: row.id, target: below.id, position: .above)
        }
        let minDepth = rows.map(\.depth).min() ?? 0
        guard let last = rows.last(where: { $0.depth == minDepth }), last.id != row.id else { return nil }
        return .move(row: row.id, target: last.id, position: .below)
    }
}

extension View {
    /// A tap, with the hardware keyboard's modifier keys held for it. SwiftUI's taps don't carry them
    /// on iOS (`Gesture.modifiers` is macOS only), so a UIKit tap recognizer reads them there.
    func modifiedTap(_ action: @escaping (EventModifiers) -> Void) -> some View {
        #if os(iOS)
            gesture(ModifiedTap(action: action))
        #else
            onTapGesture { action([]) }
        #endif
    }
}

#if os(iOS)
    /// A UIKit tap: its event's modifier flags, which a SwiftUI tap lacks.
    private struct ModifiedTap: UIGestureRecognizerRepresentable {
        let action: (EventModifiers) -> Void

        func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
            UITapGestureRecognizer()
        }

        func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
            guard recognizer.state == .ended else { return }
            let flags = recognizer.modifierFlags
            var held: EventModifiers = []
            if flags.contains(.command) { held.insert(.command) }
            if flags.contains(.shift) { held.insert(.shift) }
            action(held)
        }
    }
#endif

/// One VoiceOver element per row: activating it selects the row; hiding, renaming and the row's own
/// actions are named actions.
private struct RowAccessibility: ViewModifier {
    let row: CraftRow
    let select: () -> Void
    let setVisible: (Bool) -> Void
    let rename: () -> Void
    let act: (CraftItemAction) -> Void

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
                if row.rename == .allowed {
                    Button("Rename", action: rename)
                }
                ForEach(row.actions) { action in
                    Button(action.label) { act(action) }
                }
            }
    }
}

// Private: apps compile CraftUI into their own module, where a public-looking `safe:` could clash.
fileprivate extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
