import Synchronization

/// Gesture numbers, unique for the whole process. Apps coalesce undo on panel, control and gesture,
/// so a number must never be reused, even when a panel's views are torn down and built again.
enum GestureID {
    private static let counter = Atomic<UInt64>(1)

    /// A number no other gesture in this process has had.
    static func next() -> UInt64 {
        counter.wrappingAdd(1, ordering: .relaxed).oldValue
    }
}

/// One number control's drag. While it runs, the control shows the finger's value, not the app's
/// (which may lag a frame or reject a value). After it ends, the control shows the value it sent
/// last (the committed one, or the one a cancel put back) until the app next describes the panel,
/// whatever that description says: the app's value then wins, so a clamped or refused value shows
/// the app's truth, without a frame of the value from before the drag in between.
struct GestureHold: Equatable, Sendable {
    /// One edit's worth of a drag: its gesture, phase and value.
    struct Step: Equatable, Sendable {
        let gesture: UInt64
        let phase: CraftEdit.Phase
        let value: Double
    }

    private struct Drag: Equatable, Sendable {
        let gesture: UInt64
        let from: Double
        var now: Double
    }

    private var drag: Drag?
    /// The value the ended drag sent last, shown until the app's next description.
    private var settling: Double?

    /// Whether a drag is running.
    var isDragging: Bool { drag != nil }

    /// A drag starts from the app's `value`, with a new gesture number.
    mutating func begin(from value: Double) -> Step {
        let gesture = GestureID.next()
        drag = Drag(gesture: gesture, from: value, now: value)
        settling = nil
        return Step(gesture: gesture, phase: .begin, value: value)
    }

    /// The finger moved; `nil` if no drag is running.
    mutating func change(to value: Double) -> Step? {
        guard var current = drag else { return nil }
        current.now = value
        drag = current
        return Step(gesture: current.gesture, phase: .change, value: value)
    }

    /// The drag ended: its last value; `nil` if none was running.
    mutating func commit() -> Step? {
        guard let current = drag.take() else { return nil }
        settling = current.now
        return Step(gesture: current.gesture, phase: .commit, value: current.now)
    }

    /// The drag was abandoned (or its view went away): the value from before it; `nil` if none was running.
    mutating func cancel() -> Step? {
        guard let current = drag.take() else { return nil }
        settling = current.from
        return Step(gesture: current.gesture, phase: .cancel, value: current.from)
    }

    /// The app described the panel again (any description, changed or not): an ended drag's value
    /// gives way to the app's.
    mutating func described() {
        settling = nil
    }

    /// What the control shows: the finger's value mid-drag, then the value the drag ended on until
    /// the app describes the panel again, the app's otherwise.
    func shown(app: Double) -> Double {
        drag?.now ?? settling ?? app
    }
}
