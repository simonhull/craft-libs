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

    private enum Key: String, CodingKey { case id, title, role, nodes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self = try CraftPanel(
            id: c.decode(String.self, forKey: .id), title: c.decode(String.self, forKey: .title),
            role: c.decode(CraftPanelInfo.Role.self, forKey: .role), nodes: CraftNode.decodeEach(c, forKey: .nodes))
    }
}

/// Everything the app sent: its panels, and the open ones described (wire kind 13). A panel this
/// kit can't show (a role it doesn't know, or an entry that doesn't decode) is left out, in `panels`
/// and in `open` alike; the others still show.
public struct CraftPanels: Decodable, Equatable, Sendable {
    public var panels: [CraftPanelInfo]
    public var open: [String: CraftPanel]

    public init(panels: [CraftPanelInfo] = [], open: [String: CraftPanel] = [:]) {
        (self.panels, self.open) = (panels, open)
    }

    private enum Key: String, CodingKey { case panels, open }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        panels = try c.decode([Skippable<CraftPanelInfo>].self, forKey: .panels).compactMap(\.value)
        open = try c.decode([String: Skippable<CraftPanel>].self, forKey: .open).compactMapValues(\.value)
    }

    /// One entry of a list, `nil` if it doesn't decode, so the list moves past it.
    private struct Skippable<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: any Decoder) {
            value = try? T(from: decoder)
        }
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

/// One primitive (`ui::Node`). In a list of nodes, a type this kit doesn't know becomes `.unknown`
/// and a known one that doesn't decode `.malformed`: one bad node never takes the panel down with it.
public indirect enum CraftNode: Decodable, Equatable, Sendable {
    /// A titled group. `collapsed` is only how it starts: after it first appears, collapsing is the
    /// user's, until the panel's views are built again (the panel closed and reopened).
    case section(id: String, title: String, collapsed: Bool, children: [CraftNode])
    case number(id: String, label: String, value: Double, min: Double, max: Double, step: Double?, unit: Unit, enabled: Bool)
    case toggle(id: String, label: String, value: Bool, enabled: Bool)
    case choice(id: String, label: String, value: String, options: [CraftChoiceOption], enabled: Bool)
    case itemList(id: String, rows: [CraftRow], reorderable: Bool)
    /// A type this kit doesn't know (the app is newer).
    case unknown(type: String)
    /// A known type that didn't decode (the app sent it wrong).
    case malformed(type: String)

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
                collapsed: c.decode(Bool.self, forKey: .collapsed), children: Self.decodeEach(c, forKey: .children))
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

    /// The `type`s this kit draws.
    static let knownTypes: Set = ["section", "number", "toggle", "choice", "item_list"]

    /// A list of nodes, each decoded on its own: one that fails becomes `.malformed` (a known type)
    /// or `.unknown` (with its `type`, empty if it has none) instead of failing the list.
    static func decodeEach<K: CodingKey>(_ c: KeyedDecodingContainer<K>, forKey key: K) throws -> [CraftNode] {
        try c.decode([Lenient].self, forKey: key).map(\.node)
    }

    /// Decodes one element of a list whatever it holds, so the list moves past it.
    private struct Lenient: Decodable {
        let node: CraftNode

        private struct Probe: Decodable { let type: String? }

        init(from decoder: any Decoder) {
            if let node = try? CraftNode(from: decoder) {
                self.node = node
            } else {
                let type = ((try? Probe(from: decoder))?.type) ?? ""
                node = CraftNode.knownTypes.contains(type) ? .malformed(type: type) : .unknown(type: type)
            }
        }
    }

    /// The node's id, for diffing (`unknown` and `malformed` nodes use their type).
    public var id: String {
        switch self {
        case let .section(id, _, _, _), let .number(id, _, _, _, _, _, _, _), let .toggle(id, _, _, _),
             let .choice(id, _, _, _, _), let .itemList(id, _, _):
            id
        case let .unknown(type):
            "unknown-\(type)"
        case let .malformed(type):
            "malformed-\(type)"
        }
    }
}
