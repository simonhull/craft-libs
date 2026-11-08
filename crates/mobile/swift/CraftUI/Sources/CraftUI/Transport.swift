import Foundation
import Observation

/// How a transport shows a time (craft-mobile's `ui::TimeFormat`). Display only: positions and
/// edits are always frames. Left out, or one this kit doesn't know, is `.frames`.
public enum CraftTimeFormat: String, Decodable, Sendable {
    /// The frame counted from 1, of the duration: "12 / 30".
    case frames
    /// Hours, minutes, seconds and frames at the transport's rate: "00:00:00:11".
    case timecode

    public init(from decoder: any Decoder) throws {
        self = try CraftTimeFormat(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .frames
    }
}

/// What a transport button asks for (craft-mobile's `ui::TransportAction`), sent as a `transport`
/// edit. What Stop does beyond pausing, and whether stepping pauses, are the app's rules.
public enum CraftTransportAction: String, CaseIterable, Encodable, Sendable {
    case play, pause, stop
    case stepBack = "step_back"
    case stepForward = "step_forward"
    case toStart = "to_start"
    case toEnd = "to_end"
}

/// A transport bar (craft-mobile's `ui::Transport`): a playhead over a span of frames, played at a
/// rate, with an optional work area.
///
/// Always valid: at least one frame, the position on one of them, a finite rate above zero, and a
/// work area that is inside the frames and not empty (or none). Decoding is lenient where it can
/// be: a position past the end shows the last frame, a work area past the end is cut to it, and one
/// that is empty or doesn't decode is none; no frames or a bad rate don't decode (the node is
/// malformed).
public struct CraftTransport: Decodable, Equatable, Sendable {
    public let id: String
    /// The playhead's frame, counted from 0: below ``duration``.
    public private(set) var position: UInt64
    /// How many frames there are: at least 1.
    public let duration: UInt64
    /// Frames per second: finite and above zero, not necessarily whole (29.97).
    public let rate: Double
    public let format: CraftTimeFormat
    /// Playing: the play button shows Pause.
    public private(set) var playing: Bool
    /// The work area (the loop region), start inclusive, end exclusive; `nil` for none.
    public let range: Range<UInt64>?
    public let enabled: Bool

    /// A transport, its values kept valid as above; `nil` without frames or with a rate that isn't
    /// a finite number above zero.
    public init?(
        id: String, position: UInt64, duration: UInt64, rate: Double, format: CraftTimeFormat = .frames, playing: Bool = false,
        range: Range<UInt64>? = nil, enabled: Bool = true
    ) {
        guard duration > 0, rate.isFinite, rate > 0 else { return nil }
        self.id = id
        self.position = min(position, duration - 1)
        self.duration = duration
        self.rate = rate
        self.format = format
        self.playing = playing
        self.range = range.map { $0.clamped(to: 0..<duration) }.flatMap { $0.isEmpty ? nil : $0 }
        self.enabled = enabled
    }

    /// The same transport with another position (kept on a frame) or playing state, as the app
    /// describes it next.
    public func with(position: UInt64? = nil, playing: Bool? = nil) -> CraftTransport {
        var copy = self
        copy.position = min(position ?? self.position, duration - 1)
        copy.playing = playing ?? self.playing
        return copy
    }

    private enum Key: String, CodingKey { case id, position, duration, rate, format, playing, range, enabled }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let bounds = (try? c.decodeIfPresent([UInt64].self, forKey: .range)) ?? nil
        let range = bounds.flatMap { $0.count == 2 && $0[0] < $0[1] ? $0[0]..<$0[1] : nil }
        guard let transport = try CraftTransport(
            id: c.decode(String.self, forKey: .id), position: c.decode(UInt64.self, forKey: .position),
            duration: c.decode(UInt64.self, forKey: .duration), rate: c.decode(Double.self, forKey: .rate),
            format: (try? c.decodeIfPresent(CraftTimeFormat.self, forKey: .format)) ?? .frames,
            playing: c.decode(Bool.self, forKey: .playing), range: range,
            enabled: c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true)
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "a transport needs frames and a rate above zero"))
        }
        self = transport
    }
}

// MARK: Showing a time

extension CraftTransport {
    /// What the time label shows for `frame` (counted from 0), in the transport's format.
    public func label(at frame: UInt64) -> String {
        Self.label(frame: frame, duration: duration, rate: rate, format: format)
    }

    /// The widest label the transport can show (the last frame's, in monospaced digits), to keep
    /// the label's width steady while it plays.
    var widestLabel: String { label(at: duration - 1) }

    /// Where the app says the playhead is: the live position of this transport in `panel`, if one
    /// arrived since the description, else the described one; on a frame either way.
    @MainActor
    func appPosition(panel: String, live: CraftLiveValues?) -> UInt64 {
        min(live?.position(panel: panel, control: id) ?? position, duration - 1)
    }

    /// What VoiceOver says for `frame`: "Frame 12 of 30", or the timecode.
    func spokenLabel(at frame: UInt64) -> String {
        switch format {
        case .frames: "Frame \(frame + 1) of \(duration)"
        case .timecode: label(at: frame)
        }
    }

    /// `frame` (counted from 0) as the label shows it:
    /// - `frames`: counted from 1, of the duration: "12 / 30";
    /// - `timecode`: ``timecode(frame:rate:)``.
    nonisolated static func label(frame: UInt64, duration: UInt64, rate: Double, format: CraftTimeFormat) -> String {
        switch format {
        case .frames: "\(frame + 1) / \(duration)"
        case .timecode: timecode(frame: frame, rate: rate)
        }
    }

    /// `frame` (counted from 0) as SMPTE timecode, `HH:MM:SS:FF`.
    ///
    /// At 29.97 and 59.94 (30000/1001 and 60000/1001 fps) it is drop-frame, `HH:MM:SS;FF`: frame
    /// numbers 0 and 1 (0 to 3 at 59.94) are skipped at the start of each minute except every tenth,
    /// so the timecode keeps to the clock. Every other rate counts whole frames at its nominal rate,
    /// the rate rounded up (23.976 counts 24 frames a second, non-drop, as editors do), so the
    /// timecode of a fractional rate other than those two drifts slowly from the clock. Hours don't
    /// wrap at 24.
    nonisolated static func timecode(frame: UInt64, rate: Double) -> String {
        let drop = dropFrames(rate: rate)
        let nominal: UInt64
        var counted = frame
        if let drop {
            nominal = drop * 15
            let perMinute = nominal * 60 - drop
            let perTenMinutes = perMinute * 10 + drop
            let (tens, rest) = frame.quotientAndRemainder(dividingBy: perTenMinutes)
            counted += drop * 9 * tens
            if rest >= drop { counted += drop * ((rest - drop) / perMinute) }
        } else {
            // Rounded up, as 23.976 counts 24; a hair over a whole rate (24.0000001) is still that rate.
            nominal = UInt64(max(1, min(rate, 1_000_000) - 1e-6).rounded(.up))
        }
        let (seconds, frames) = counted.quotientAndRemainder(dividingBy: nominal)
        func two(_ n: UInt64) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(two(seconds / 3600)):\(two(seconds / 60 % 60)):\(two(seconds % 60))\(drop == nil ? ":" : ";")\(two(frames))"
    }

    /// The frame numbers drop-frame timecode skips each minute at `rate`: 2 at 29.97, 4 at 59.94,
    /// `nil` at any other rate (non-drop).
    nonisolated static func dropFrames(rate: Double) -> UInt64? {
        if abs(rate - 30000 / 1001) < 0.005 { return 2 }
        if abs(rate - 60000 / 1001) < 0.005 { return 4 }
        return nil
    }
}

// MARK: Scrubbing

/// The scrubber's drag over a transport's frames, as edits: a touch seeks at once (`begin`), the
/// finger moving to another frame sends `change` (not every point it moves), and lifting it
/// `commit`s where it is; a cancelled drag sends `cancel` with the frame from before it.
///
/// While the drag runs, the scrubber shows the finger's frame, not the app's echoes. After it is
/// committed, it shows the frame it sent last until the app says where the playhead is (a
/// description, or a live position): the app's frame wins then, clamped or refused. After it is
/// cancelled, it shows the app's frame at once: the app puts the playhead back (or doesn't, a
/// dialog being up) and says where.
struct CraftScrub: Equatable, Sendable {
    /// One edit's worth of a drag.
    struct Step: Equatable, Sendable {
        let gesture: UInt64
        let phase: CraftEdit.Phase
        let frame: UInt64
    }

    /// What the app says about the playhead: how many descriptions it has sent (changed or not),
    /// and where it puts the playhead (``CraftTransport/appPosition(panel:live:)``).
    struct Word: Equatable, Sendable {
        let descriptions: UInt64
        let position: UInt64
    }

    private struct Drag: Equatable, Sendable {
        let gesture: UInt64
        let from: UInt64
        var now: UInt64
    }

    private var drag: Drag?
    private var settling: UInt64?

    /// Whether a drag is running.
    var isScrubbing: Bool { drag != nil }

    /// The frame the finger is on, mid-drag.
    var current: UInt64? { drag?.now }

    /// The finger came down on `frame` while the app's playhead was on `app`.
    mutating func begin(at frame: UInt64, from app: UInt64) -> Step {
        let gesture = GestureID.next()
        drag = Drag(gesture: gesture, from: app, now: frame)
        settling = nil
        return Step(gesture: gesture, phase: .begin, frame: frame)
    }

    /// The finger is over `frame`: a `change` if that's another frame; `nil` if it isn't, or no
    /// drag is running.
    mutating func move(to frame: UInt64) -> Step? {
        guard var current = drag, current.now != frame else { return nil }
        current.now = frame
        drag = current
        return Step(gesture: current.gesture, phase: .change, frame: frame)
    }

    /// The finger lifted over `frame`; `nil` if no drag was running.
    mutating func commit(at frame: UInt64) -> Step? {
        guard let current = drag.take() else { return nil }
        settling = frame
        return Step(gesture: current.gesture, phase: .commit, frame: frame)
    }

    /// The drag was abandoned (or its view went away): the frame from before it; `nil` if none was
    /// running. The app's frame shows from now on.
    mutating func cancel() -> Step? {
        guard let current = drag.take() else { return nil }
        settling = nil
        return Step(gesture: current.gesture, phase: .cancel, frame: current.from)
    }

    /// Whether the app saying `new`, having said `old`, settles a drag that ended: it said
    /// something new (a description, changed or not, or another position) while the frame the
    /// drag ended on shows. Asked before ``settled()``, so a view writes its state only when it
    /// changes, not with every live position.
    func settles(after old: Word, now new: Word) -> Bool {
        settling != nil && old != new
    }

    /// The app said where the playhead is: its frame shows from now on.
    mutating func settled() {
        settling = nil
    }

    /// The frame to show: the finger's mid-drag, then the one the drag ended on until the app next
    /// says, the app's otherwise.
    func shown(app: UInt64) -> UInt64 {
        drag?.now ?? settling ?? app
    }

    /// The frame under `x` on a track `width` wide holding `duration` frames side by side, each an
    /// equal cell: kept on the track, so a finger past either end is on the first or last frame.
    nonisolated static func frame(atX x: Double, width: Double, duration: UInt64) -> UInt64 {
        guard duration > 1, width > 0, !x.isNaN else { return 0 }
        let cell = (x / width * Double(duration)).rounded(.down)
        if cell <= 0 { return 0 }
        // Compared as doubles first, so the conversion below never sees a value past `UInt64`.
        return cell >= Double(duration - 1) ? duration - 1 : UInt64(cell)
    }

    /// Where a frame's cell starts on a track `width` wide holding `duration` frames (`frame ==
    /// duration` is the track's end).
    nonisolated static func x(ofEdge frame: UInt64, width: Double, duration: UInt64) -> Double {
        duration == 0 ? 0 : width * Double(min(frame, duration)) / Double(duration)
    }

    /// Where the playhead stands for `frame`: the middle of its cell.
    nonisolated static func x(ofFrame frame: UInt64, width: Double, duration: UInt64) -> Double {
        duration == 0 ? 0 : width * (Double(min(frame, duration - 1)) + 0.5) / Double(duration)
    }

    /// Whether moving the playhead from `old` to `new` crosses an edge of the work area `range`:
    /// into it or out of it, at either end.
    nonisolated static func crossesEdge(from old: UInt64, to new: UInt64, range: Range<UInt64>?) -> Bool {
        guard let range else { return false }
        return (old < range.lowerBound) != (new < range.lowerBound) || (old < range.upperBound) != (new < range.upperBound)
    }
}

// MARK: Live positions

/// One transport's position (an entry of wire kind 17).
public struct CraftLiveValue: Decodable, Equatable, Sendable {
    public let panel: String
    public let control: String
    /// The playhead's frame, counted from 0.
    public let position: UInt64

    public init(panel: String, control: String, position: UInt64) {
        (self.panel, self.control, self.position) = (panel, control, position)
    }
}

/// Transports' positions as the app moves them while playing (wire kind 17), without describing
/// their panels again. A position shows in place of the described one until the next description
/// (wire kind 13), which carries the positions itself.
///
/// Only transport views read it, so a playing transport redraws its own bar and nothing else. The
/// shell puts it in the environment (``SwiftUICore/EnvironmentValues/craftLiveValues``).
@MainActor
@Observable
public final class CraftLiveValues {
    /// A transport, by its panel and control ids.
    public struct Key: Hashable, Sendable {
        public let panel: String
        public let control: String

        public init(panel: String, control: String) {
            (self.panel, self.control) = (panel, control)
        }
    }

    /// The positions heard since the last description.
    public private(set) var positions: [Key: UInt64] = [:]

    public init() {}

    /// The live position of the transport `control` in `panel`, if one arrived since the last description.
    public func position(panel: String, control: String) -> UInt64? {
        positions[Key(panel: panel, control: control)]
    }

    /// Positions that changed (wire kind 17); assigned only if one did, so observers redraw only then.
    public func apply(_ values: some Sequence<CraftLiveValue>) {
        var next = positions
        for value in values { next[Key(panel: value.panel, control: value.control)] = value.position }
        if next != positions { positions = next }
    }

    /// Wire kind 17 as JSON: a list of positions. An entry that doesn't decode is skipped.
    ///
    /// - Throws: `DecodingError` when it isn't a list at all; nothing changes then.
    public func apply(json: Data) throws {
        apply(try JSONDecoder().decode([Skippable<CraftLiveValue>].self, from: json).compactMap(\.value))
    }

    /// The panels were described (wire kind 13): their positions are the truth again.
    public func described() {
        if !positions.isEmpty { positions = [:] }
    }
}
