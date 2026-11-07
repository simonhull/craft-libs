/// In-flight drags on number controls. While one runs, the control shows the finger's value,
/// not the app's (which may lag a frame or reject a value); after it ends, the app's value wins.
/// It also numbers gestures, so every edit of one drag shares a number and no two gestures do.
public struct GestureHold: Sendable {
    /// One edit's worth of a drag: its gesture, phase and value.
    public struct Step: Equatable, Sendable {
        public let gesture: UInt64
        public let phase: CraftEdit.Phase
        public let value: Double
    }

    private struct Drag: Sendable {
        let gesture: UInt64
        let from: Double
        var now: Double
    }

    private var drags: [String: Drag] = [:]
    private var next: UInt64 = 1

    public init() {}

    /// A drag on `control` starts from the app's `value`.
    public mutating func begin(control: String, from value: Double) -> Step {
        let gesture = oneShot()
        drags[control] = Drag(gesture: gesture, from: value, now: value)
        return Step(gesture: gesture, phase: .begin, value: value)
    }

    /// The finger moved; `nil` if no drag is running on `control`.
    public mutating func change(control: String, to value: Double) -> Step? {
        guard var drag = drags[control] else { return nil }
        drag.now = value
        drags[control] = drag
        return Step(gesture: drag.gesture, phase: .change, value: value)
    }

    /// The drag ended: its last value; `nil` if none was running.
    public mutating func commit(control: String) -> Step? {
        guard let drag = drags.removeValue(forKey: control) else { return nil }
        return Step(gesture: drag.gesture, phase: .commit, value: drag.now)
    }

    /// The drag was abandoned: the value from before it; `nil` if none was running.
    public mutating func cancel(control: String) -> Step? {
        guard let drag = drags.removeValue(forKey: control) else { return nil }
        return Step(gesture: drag.gesture, phase: .cancel, value: drag.from)
    }

    /// Whether a drag is running on `control`.
    public func dragging(control: String) -> Bool {
        drags[control] != nil
    }

    /// What a control shows: the finger's value mid-drag, the app's otherwise.
    public func shown(control: String, app: Double) -> Double {
        drags[control]?.now ?? app
    }

    /// A gesture number for a one-shot edit (tap, pick).
    public mutating func oneShot() -> UInt64 {
        defer { next &+= 1 }
        return next
    }
}
