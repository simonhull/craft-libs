import CraftUI
import Foundation
import Observation

/// The catalogue's examples, played by the Gallery as an app would: each edit is applied to the
/// Gallery's own copy (so the controls respond) and logged as the JSON the app would receive.
@MainActor
@Observable
final class GalleryStore {
    /// One primitive from the catalogue.
    struct Entry: Decodable, Identifiable {
        let name: String
        let about: String
        var example: CraftNode
        var id: String { name }
    }

    private struct Catalogue: Decodable {
        let primitives: [Entry]
    }

    /// The id of the panel that shows every example at once, as an inspector would.
    static let everything = "everything"

    private(set) var entries: [Entry] = []
    /// Why the catalogue didn't load, if it didn't.
    private(set) var problem: String?
    /// One edit as sent.
    struct Sent: Identifiable {
        let id: Int
        let json: String
    }

    /// The edits sent, newest first.
    private(set) var log: [Sent] = []
    private var sentCount = 0
    /// Each drag in progress, by gesture: its control and the value it started from, which a
    /// cancelled drag puts back (and nothing else: other controls may have changed meanwhile).
    private var drags: [UInt64: (control: String, from: CraftEdit.Value)] = [:]

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "ui", withExtension: "json") else {
                problem = "ui.json is missing from the app bundle."
                return
            }
            entries = try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url)).primitives
        } catch {
            problem = "Couldn't read the catalogue: \(error.localizedDescription)"
        }
    }

    /// One primitive's example as a panel of its own.
    func panel(for entry: Entry, role: CraftPanelInfo.Role) -> CraftPanel {
        CraftPanel(id: entry.name, title: entry.name, role: role, nodes: [entry.example])
    }

    /// Every example in one panel.
    func everythingPanel(role: CraftPanelInfo.Role) -> CraftPanel {
        CraftPanel(id: Self.everything, title: "Everything", role: role, nodes: entries.map(\.example))
    }

    /// Log the edit as the app would receive it, then apply it as the app would and describe the
    /// panel again.
    func send(_ edit: CraftEdit) {
        let encoder = JSONEncoder()
        // Sorted, so every edit reads the same way (the app doesn't mind the order).
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let json = try? encoder.encode(edit) {
            sentCount += 1
            log.insert(Sent(id: sentCount, json: String(decoding: json, as: UTF8.self)), at: 0)
            log.removeLast(max(0, log.count - 50))
        }
        switch edit.phase {
        case .begin:
            if let from = entries.lazy.compactMap({ $0.example.value(of: edit.control) }).first {
                drags[edit.gesture] = (edit.control, from)
            }
        case .change, .commit:
            apply(edit.value, to: edit.control)
            if edit.phase == .commit { drags[edit.gesture] = nil }
        case .cancel:
            if let drag = drags.removeValue(forKey: edit.gesture) { apply(drag.from, to: drag.control) }
        }
    }

    private func apply(_ value: CraftEdit.Value, to control: String) {
        for index in entries.indices {
            entries[index].example = entries[index].example.applying(value, to: control)
        }
    }

    func clearLog() {
        log.removeAll()
    }
}

extension CraftNode {
    /// The value of the control `control` (looked for inside sections too), as an edit would carry it.
    func value(of control: String) -> CraftEdit.Value? {
        switch self {
        case let .section(_, _, _, children): children.lazy.compactMap { $0.value(of: control) }.first
        case let .number(id, _, value, _, _, _, _, _) where id == control: .number(value)
        case let .toggle(id, _, value, _) where id == control: .toggle(value)
        case let .choice(id, _, value, _, _) where id == control: .choice(value)
        default: nil
        }
    }

    /// The node with an edit's value applied to the control `control` (looked for inside sections
    /// too), as an app would describe it next. Other nodes, and edits that don't fit, change nothing.
    func applying(_ value: CraftEdit.Value, to control: String) -> CraftNode {
        switch (self, value) {
        case let (.section(id, title, collapsed, children), _):
            return .section(id: id, title: title, collapsed: collapsed, children: children.map { $0.applying(value, to: control) })
        case let (.number(id, label, _, min, max, step, unit, enabled), .number(new)) where id == control:
            return .number(id: id, label: label, value: Swift.min(Swift.max(new, min), max), min: min, max: max, step: step, unit: unit, enabled: enabled)
        case let (.toggle(id, label, _, enabled), .toggle(new)) where id == control:
            return .toggle(id: id, label: label, value: new, enabled: enabled)
        case let (.choice(id, label, _, options, enabled), .choice(new)) where id == control && options.contains { $0.id == new }:
            return .choice(id: id, label: label, value: new, options: options, enabled: enabled)
        case let (.itemList(id, rows, reorderable), _) where id == control:
            return .itemList(id: id, rows: rows.applying(value, reorderable: reorderable), reorderable: reorderable)
        default:
            return self
        }
    }
}

extension [CraftRow] {
    /// The rows after a list edit.
    func applying(_ value: CraftEdit.Value, reorderable: Bool) -> [CraftRow] {
        switch value {
        case let .select(row):
            return map { $0.with(selected: $0.id == row) }
        case let .setVisible(row, visible):
            return map { $0.id == row && $0.visible != nil ? $0.with(visible: visible) : $0 }
        case let .rename(row, name):
            return map { $0.id == row ? $0.with(title: name) : $0 }
        case let .move(row, target, position):
            guard reorderable, row != target, let moving = first(where: { $0.id == row }) else { return self }
            var rows = filter { $0.id != row }
            guard let at = rows.firstIndex(where: { $0.id == target }) else { return self }
            rows.insert(moving, at: position == .above ? at : at + 1)
            return rows
        case .number, .toggle, .choice:
            return self
        }
    }
}

extension CraftRow {
    func with(title: String? = nil, visible: Bool? = nil, selected: Bool? = nil) -> CraftRow {
        CraftRow(
            id: id, title: title ?? self.title, subtitle: subtitle, depth: depth,
            visible: visible ?? self.visible, selected: selected ?? self.selected)
    }
}
