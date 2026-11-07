import Foundation

/// One change from a native panel (craft-mobile's `ui::Edit`), sent as `{"action":"edit", …}`.
public struct CraftEdit: Encodable, Equatable, Sendable {
    /// Where a gesture is: a drag sends `begin`, `change`s, then `commit` or `cancel`; a tap or pick sends `commit` alone.
    public enum Phase: String, Encodable, Sendable { case begin, change, commit, cancel }

    /// Above or below a target row.
    public enum Position: String, Encodable, Sendable { case above, below }

    /// The value an edit carries, by the kind of control.
    public enum Value: Equatable, Sendable {
        case number(Double), toggle(Bool), choice(String)
        case select(row: UInt64), setVisible(row: UInt64, visible: Bool), rename(row: UInt64, name: String)
        case move(row: UInt64, target: UInt64, position: Position)
    }

    public let panel: String
    public let control: String
    public let phase: Phase
    /// Shared by every edit of one drag; new for every gesture.
    public let gesture: UInt64
    public let value: Value

    public init(panel: String, control: String, phase: Phase, gesture: UInt64, value: Value) {
        (self.panel, self.control, self.phase, self.gesture, self.value) = (panel, control, phase, gesture, value)
    }

    private enum Key: String, CodingKey { case action, panel, control, phase, gesture, value }
    private enum ValueKey: String, CodingKey { case kind, value }
    private enum RowKey: String, CodingKey { case row, visible, name, target, position }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode("edit", forKey: .action)
        try c.encode(panel, forKey: .panel)
        try c.encode(control, forKey: .control)
        try c.encode(phase, forKey: .phase)
        try c.encode(gesture, forKey: .gesture)
        var v = c.nestedContainer(keyedBy: ValueKey.self, forKey: .value)
        switch value {
        case let .number(x):
            try v.encode("number", forKey: .kind)
            try v.encode(x, forKey: .value)
        case let .toggle(x):
            try v.encode("toggle", forKey: .kind)
            try v.encode(x, forKey: .value)
        case let .choice(x):
            try v.encode("choice", forKey: .kind)
            try v.encode(x, forKey: .value)
        case let .select(row):
            try v.encode("select", forKey: .kind)
            var r = v.nestedContainer(keyedBy: RowKey.self, forKey: .value)
            try r.encode(row, forKey: .row)
        case let .setVisible(row, visible):
            try v.encode("set_visible", forKey: .kind)
            var r = v.nestedContainer(keyedBy: RowKey.self, forKey: .value)
            try r.encode(row, forKey: .row)
            try r.encode(visible, forKey: .visible)
        case let .rename(row, name):
            try v.encode("rename", forKey: .kind)
            var r = v.nestedContainer(keyedBy: RowKey.self, forKey: .value)
            try r.encode(row, forKey: .row)
            try r.encode(name, forKey: .name)
        case let .move(row, target, position):
            try v.encode("move", forKey: .kind)
            var r = v.nestedContainer(keyedBy: RowKey.self, forKey: .value)
            try r.encode(row, forKey: .row)
            try r.encode(target, forKey: .target)
            try r.encode(position, forKey: .position)
        }
    }
}
