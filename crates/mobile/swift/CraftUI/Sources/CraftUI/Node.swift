import Foundation

/// A panel the app offers (craft-mobile's `ui::PanelInfo`).
public struct CraftPanelInfo: Decodable, Equatable, Identifiable, Sendable {
    /// Where a panel shows: `inspector` slides in beside the canvas, `tool` is a popover, `rail` is
    /// the vertical rail at the canvas's leading edge (its tool palette), `transport` a floating bar
    /// above the bottom toolbar (its transport).
    public enum Role: String, Decodable, Sendable { case inspector, tool, rail, transport }

    public let id: String
    public let title: String
    /// An SF Symbol name.
    public let icon: String
    public let role: Role

    public init(id: String, title: String, icon: String, role: Role) {
        (self.id, self.title, self.icon, self.role) = (id, title, icon, role)
    }

    /// What VoiceOver calls the panel's toolbar button: its title, else its icon's name in words
    /// (`square.3.layers.3d`: "square 3 layers 3d"), else its id. Never empty.
    public var accessibilityName: String {
        let title = title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { return title }
        let icon = icon.split(separator: ".").joined(separator: " ")
        return icon.isEmpty ? id : icon
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
}

/// One option of a `choice` node.
public struct CraftChoiceOption: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        (self.id, self.label) = (id, label)
    }
}

/// Something the user can do in an item list (`ui::ItemAction`), to one row or to the list itself.
/// - A row's (Close a document, Delete a layer) shows in the row's context menu, and as a swipe
///   action too when `destructive`; chosen, it sends an `action` edit with the row and its `id`.
/// - The list's own (New Layer, New Group) is an icon button in the list's footer, named by its
///   `label` for VoiceOver and as its tooltip; chosen, it sends a `list_action` edit with its `id`.
public struct CraftItemAction: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    /// An SF Symbol name, or `nil` for none.
    public let icon: String?
    /// It destroys something: tinted red, and a row's is a trailing swipe action.
    public let destructive: Bool

    public init(id: String, label: String, icon: String? = nil, destructive: Bool = false) {
        (self.id, self.label, self.icon, self.destructive) = (id, label, icon, destructive)
    }

    private enum Key: String, CodingKey { case id, label, icon, destructive }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self = try CraftItemAction(
            id: c.decode(String.self, forKey: .id), label: c.decode(String.self, forKey: .label),
            icon: c.decodeIfPresent(String.self, forKey: .icon), destructive: c.decodeIfPresent(Bool.self, forKey: .destructive) ?? false)
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
    /// What the user can do to the row, in menu order; none when the app leaves them out. One that
    /// doesn't decode is skipped.
    public let actions: [CraftItemAction]
    /// Whether Rename… is offered.
    public let rename: Rename

    /// Whether the user can rename a row (`ui::Rename`). Left out, or a value this kit doesn't
    /// know, it can.
    public enum Rename: String, Decodable, Sendable {
        case allowed, no

        public init(from decoder: any Decoder) throws {
            self = try Rename(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .allowed
        }
    }

    public init(
        id: UInt64, title: String, subtitle: String = "", depth: UInt32 = 0, visible: Bool? = nil, selected: Bool = false,
        actions: [CraftItemAction] = [], rename: Rename = .allowed
    ) {
        (self.id, self.title, self.subtitle, self.depth, self.visible, self.selected, self.actions, self.rename) =
            (id, title, subtitle, depth, visible, selected, actions, rename)
    }

    private enum Key: String, CodingKey { case id, title, subtitle, depth, visible, selected, actions, rename }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self = try CraftRow(
            id: c.decode(UInt64.self, forKey: .id), title: c.decode(String.self, forKey: .title),
            subtitle: c.decode(String.self, forKey: .subtitle), depth: c.decode(UInt32.self, forKey: .depth),
            visible: c.decodeIfPresent(Bool.self, forKey: .visible), selected: c.decode(Bool.self, forKey: .selected),
            actions: (c.decodeIfPresent([Skippable<CraftItemAction>].self, forKey: .actions) ?? []).compactMap(\.value),
            rename: c.decodeIfPresent(Rename.self, forKey: .rename) ?? .allowed)
    }
}

/// One primitive (`ui::Node`). In a list of nodes, a type this kit doesn't know becomes `.unknown`
/// and a known one that doesn't decode `.malformed`: one bad node never takes the panel down with it.
public indirect enum CraftNode: Decodable, Equatable, Sendable {
    /// A titled group. `collapsed` is only how it starts: after it first appears, collapsing is the
    /// user's, until the panel's views are built again (the panel closed and reopened).
    case section(id: String, title: String, collapsed: Bool, children: [CraftNode])
    case number(id: String, label: String, value: Double, min: Double, max: Double, step: Double?, unit: Unit, enabled: Bool, scale: Scale = .linear)
    case toggle(id: String, label: String, value: Bool, enabled: Bool)
    case choice(id: String, label: String, value: String, options: [CraftChoiceOption], enabled: Bool)
    /// `actions` are the list's own (its footer's buttons), not a row's.
    case itemList(id: String, rows: [CraftRow], reorderable: Bool, actions: [CraftItemAction] = [])
    case toolPalette(CraftToolPalette)
    case transport(CraftTransport)
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

    /// How a number's slider spreads its range: `log` by ratio (`min·(max/min)^t`), for a wide range
    /// such as a brush size. Missing, or one this kit doesn't know, is `.linear`.
    public enum Scale: String, Decodable, Sendable {
        case linear, log

        public init(from decoder: any Decoder) throws {
            self = try Scale(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .linear
        }
    }

    private enum Key: String, CodingKey {
        case type, id, title, collapsed, children, label, value, min, max, step, unit, enabled, scale, options, rows, reorderable, actions
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
                unit: c.decode(Unit.self, forKey: .unit), enabled: c.decode(Bool.self, forKey: .enabled),
                scale: c.decodeIfPresent(Scale.self, forKey: .scale) ?? .linear)
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
                reorderable: c.decode(Bool.self, forKey: .reorderable),
                // Left out (an older app) or not a list: none. One action that doesn't decode is skipped.
                actions: ((try? c.decodeIfPresent([Skippable<CraftItemAction>].self, forKey: .actions)) ?? []).compactMap(\.value))
        case "tool_palette":
            self = try .toolPalette(CraftToolPalette(from: decoder))
        case "transport":
            self = try .transport(CraftTransport(from: decoder))
        default:
            self = .unknown(type: type)
        }
    }

    /// The `type`s this kit draws.
    static let knownTypes: Set = ["section", "number", "toggle", "choice", "item_list", "tool_palette", "transport"]

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
        case let .section(id, _, _, _), let .number(id, _, _, _, _, _, _, _, _), let .toggle(id, _, _, _),
             let .choice(id, _, _, _, _), let .itemList(id, _, _, _):
            id
        case let .toolPalette(palette):
            palette.id
        case let .transport(transport):
            transport.id
        case let .unknown(type):
            "unknown-\(type)"
        case let .malformed(type):
            "malformed-\(type)"
        }
    }
}
