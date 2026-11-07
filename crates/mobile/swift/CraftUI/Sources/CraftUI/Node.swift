import Foundation

/// A panel the app offers (craft-mobile's `ui::PanelInfo`).
public struct CraftPanelInfo: Decodable, Equatable, Identifiable, Sendable {
    /// Where a panel shows: `inspector` slides in beside the canvas, `tool` is a popover.
    public enum Role: String, Decodable, Sendable { case inspector, tool }

    public let id: String
    public let title: String
    /// An SF Symbol name.
    public let icon: String
    public let role: Role

    public init(id: String, title: String, icon: String, role: Role) {
        (self.id, self.title, self.icon, self.role) = (id, title, icon, role)
    }
}

/// One panel's contents (`ui::Panel`).
public struct CraftPanel: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let role: CraftPanelInfo.Role
    public let nodes: [CraftNode]

    public init(id: String, title: String, role: CraftPanelInfo.Role, nodes: [CraftNode]) {
        (self.id, self.title, self.role, self.nodes) = (id, title, role, nodes)
    }
}

/// Everything the app sent: its panels, and the open ones described (wire kind 13).
public struct CraftPanels: Decodable, Equatable, Sendable {
    public var panels: [CraftPanelInfo]
    public var open: [String: CraftPanel]

    public init(panels: [CraftPanelInfo] = [], open: [String: CraftPanel] = [:]) {
        (self.panels, self.open) = (panels, open)
    }
}

/// One option of a `choice` node.
public struct CraftChoiceOption: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        (self.id, self.label) = (id, label)
    }
}

/// One row of an `item_list` node. `id` is the app's own (a layer id).
public struct CraftRow: Decodable, Equatable, Identifiable, Sendable {
    public let id: UInt64
    public let title: String
    public let subtitle: String
    /// Indent level (inside groups).
    public let depth: UInt32
    /// `nil`: the row can't be hidden.
    public let visible: Bool?
    public let selected: Bool

    public init(id: UInt64, title: String, subtitle: String = "", depth: UInt32 = 0, visible: Bool? = nil, selected: Bool = false) {
        (self.id, self.title, self.subtitle, self.depth, self.visible, self.selected) = (id, title, subtitle, depth, visible, selected)
    }
}

/// One primitive (`ui::Node`). A type this kit doesn't know decodes as `.unknown`.
public indirect enum CraftNode: Decodable, Equatable, Sendable {
    case section(id: String, title: String, collapsed: Bool, children: [CraftNode])
    case number(id: String, label: String, value: Double, min: Double, max: Double, step: Double?, unit: Unit, enabled: Bool)
    case toggle(id: String, label: String, value: Bool, enabled: Bool)
    case choice(id: String, label: String, value: String, options: [CraftChoiceOption], enabled: Bool)
    case itemList(id: String, rows: [CraftRow], reorderable: Bool)
    case unknown(type: String)

    /// What a number measures; the view formats it. A unit this kit doesn't know shows as `.none`.
    public enum Unit: String, Decodable, Sendable {
        case none, percent, pixels, degrees

        public init(from decoder: any Decoder) throws {
            self = try Unit(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .none
        }
    }

    private enum Key: String, CodingKey {
        case type, id, title, collapsed, children, label, value, min, max, step, unit, enabled, options, rows, reorderable
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "section":
            self = try .section(
                id: c.decode(String.self, forKey: .id), title: c.decode(String.self, forKey: .title),
                collapsed: c.decode(Bool.self, forKey: .collapsed), children: c.decode([CraftNode].self, forKey: .children))
        case "number":
            self = try .number(
                id: c.decode(String.self, forKey: .id), label: c.decode(String.self, forKey: .label),
                value: c.decode(Double.self, forKey: .value), min: c.decode(Double.self, forKey: .min),
                max: c.decode(Double.self, forKey: .max), step: c.decodeIfPresent(Double.self, forKey: .step),
                unit: c.decode(Unit.self, forKey: .unit), enabled: c.decode(Bool.self, forKey: .enabled))
        case "toggle":
            self = try .toggle(
                id: c.decode(String.self, forKey: .id), label: c.decode(String.self, forKey: .label),
                value: c.decode(Bool.self, forKey: .value), enabled: c.decode(Bool.self, forKey: .enabled))
        case "choice":
            self = try .choice(
                id: c.decode(String.self, forKey: .id), label: c.decode(String.self, forKey: .label),
                value: c.decode(String.self, forKey: .value), options: c.decode([CraftChoiceOption].self, forKey: .options),
                enabled: c.decode(Bool.self, forKey: .enabled))
        case "item_list":
            self = try .itemList(
                id: c.decode(String.self, forKey: .id), rows: c.decode([CraftRow].self, forKey: .rows),
                reorderable: c.decode(Bool.self, forKey: .reorderable))
        default:
            self = .unknown(type: type)
        }
    }

    /// The node's id, for diffing (`unknown` nodes use their type).
    public var id: String {
        switch self {
        case let .section(id, _, _, _), let .number(id, _, _, _, _, _, _, _), let .toggle(id, _, _, _),
             let .choice(id, _, _, _, _), let .itemList(id, _, _):
            id
        case let .unknown(type):
            "unknown-\(type)"
        }
    }
}
