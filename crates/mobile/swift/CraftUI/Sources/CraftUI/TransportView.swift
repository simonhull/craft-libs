import SwiftUI

extension EnvironmentValues {
    /// The transports' live positions (wire kind 17), which transport views show in place of the
    /// described ones; `nil` for none. The shell sets it for everything it shows.
    @Entry public var craftLiveValues: CraftLiveValues? = nil
}

/// A transport bar: to start, step back, play or pause, step forward and to end; a scrubber with the
/// work area shaded; and the time, in monospaced digits.
///
/// - The buttons send `transport` edits (`commit`).
/// - The scrubber sends `seek` edits: a touch seeks at once (`begin`), moving to another frame sends
///   `change`, lifting the finger `commit`s; a cancelled drag sends `cancel`. Mid-drag it shows the
///   finger's frame, not the app's. A light tick marks crossing an edge of the work area. VoiceOver
///   adjusts it a frame at a time (each one `commit`).
/// - The playhead shows the live position (``SwiftUICore/EnvironmentValues/craftLiveValues``) when
///   one arrived since the last description, so a playing transport redraws this view alone.
///
/// Laid out in a row when it fits, else the buttons and time above the scrubber.
public struct CraftTransportView: View {
    /// How it's drawn: `bar`, a floating Liquid Glass capsule (the shell's); `inline`, plain, in a
    /// panel's row.
    public enum Style: Sendable { case bar, inline }

    let transport: CraftTransport
    let panel: String
    let descriptions: UInt64
    let style: Style
    let send: @MainActor (CraftEdit) -> Void
    @State private var scrub = CraftScrub()
    /// Counts crossings of the work area's edges while scrubbing; each one is a haptic tick.
    @State private var edgeTicks = 0
    @Environment(\.craftLiveValues) private var live

    /// - Parameters:
    ///   - transport: as the app described it.
    ///   - panel: the id of the panel it's in, which its edits name.
    ///   - descriptions: how many descriptions the app has sent, changed or not (as
    ///     ``CraftPanelView``'s): a scrub shows the frame it ended on until the next one.
    ///   - send: delivers edits to the app; called only for the user's own gestures.
    public init(
        transport: CraftTransport, panel: String, descriptions: UInt64 = 0, style: Style = .bar,
        send: @escaping @MainActor (CraftEdit) -> Void
    ) {
        (self.transport, self.panel, self.descriptions, self.style, self.send) = (transport, panel, descriptions, style, send)
    }

    /// Where the app says the playhead is: the live position if one came since the description.
    private var appPosition: UInt64 {
        min(live?.position(panel: panel, control: transport.id) ?? transport.position, transport.duration - 1)
    }

    public var body: some View {
        let shown = scrub.shown(app: appPosition)
        Group {
            switch style {
            case .bar:
                content(shown)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: 720)
                    .glassEffect(.regular, in: .capsule)
                    // A bar: past this, its controls' labels show in the large content viewer.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            case .inline:
                content(shown)
            }
        }
        .disabled(!transport.enabled)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: edgeTicks)
        .onChange(of: descriptions) { scrub.settled() }
        .onChange(of: appPosition) { scrub.settled() }
        // Re-described without this transport, or closed, mid-scrub: put the playhead back.
        .onDisappear { if let step = scrub.cancel() { emit(step) } }
    }

    private func content(_ shown: UInt64) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                buttons
                track(shown).frame(minWidth: 180)
                time(shown).padding(.trailing, 8)
            }
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    buttons
                    Spacer(minLength: 8)
                    time(shown)
                }
                track(shown)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            button(.toStart, "Go to Start", "backward.end.fill")
            button(.stepBack, "Step Back", "backward.frame.fill")
            // One button whose symbol morphs between Play and Pause.
            transport.playing ? button(.pause, "Pause", "pause.fill") : button(.play, "Play", "play.fill")
            button(.stepForward, "Step Forward", "forward.frame.fill")
            button(.toEnd, "Go to End", "forward.end.fill")
        }
        .animation(.snappy(duration: 0.2), value: transport.playing)
    }

    private func button(_ action: CraftTransportAction, _ label: String, _ symbol: String) -> some View {
        Button {
            send(CraftEdit(panel: panel, control: transport.id, phase: .commit, gesture: GestureID.next(), value: .transport(action)))
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
        .help(label)
    }

    private func time(_ shown: UInt64) -> some View {
        // Sized for the widest time, so the bar doesn't shift as the digits change.
        Text(transport.widestLabel)
            .hidden()
            .overlay(alignment: .trailing) { Text(transport.label(at: shown)) }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(transport.enabled ? .primary : .secondary)
            .lineLimit(1)
            .fixedSize()
            // The scrubber says the time.
            .accessibilityHidden(true)
    }

    private func track(_ shown: UInt64) -> some View {
        CraftTransportTrack(
            shown: shown, duration: transport.duration, range: transport.range, scrubbing: scrub.isScrubbing,
            began: { frame in
                emit(scrub.begin(at: frame, from: appPosition))
            },
            moved: { frame in
                let old = scrub.current
                guard let step = scrub.move(to: frame) else { return }
                if let old, CraftScrub.crossesEdge(from: old, to: frame, range: transport.range) { edgeTicks &+= 1 }
                emit(step)
            },
            ended: { frame in if let step = scrub.commit(at: frame) { emit(step) } },
            cancelled: { if let step = scrub.cancel() { emit(step) } }
        )
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityValue(transport.spokenLabel(at: shown))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where shown + 1 < transport.duration: seek(shown + 1)
            case .decrement where shown > 0: seek(shown - 1)
            default: break
            }
        }
    }

    /// One complete seek (VoiceOver's adjust).
    private func seek(_ frame: UInt64) {
        send(CraftEdit(panel: panel, control: transport.id, phase: .commit, gesture: GestureID.next(), value: .seek(frame: frame)))
    }

    private func emit(_ step: CraftScrub.Step) {
        send(CraftEdit(panel: panel, control: transport.id, phase: step.phase, gesture: step.gesture, value: .seek(frame: step.frame)))
    }
}

/// The scrubber's track: the frames side by side as equal cells, the work area shaded over them and
/// bracketed at its edges, and the playhead in the middle of its frame's cell. Reports the frame
/// under the finger; the transport view turns that into edits.
struct CraftTransportTrack: View {
    let shown: UInt64
    let duration: UInt64
    let range: Range<UInt64>?
    let scrubbing: Bool
    let began: (UInt64) -> Void
    let moved: (UInt64) -> Void
    let ended: (UInt64) -> Void
    let cancelled: () -> Void
    /// Set while a finger is down; SwiftUI resets it when the drag ends or is cancelled.
    @GestureState private var touching = false
    /// Whether this drag has begun (a `begin` went out); cleared when it ends.
    @State private var active = false

    /// An edge of the work area.
    private var bracket: some View {
        Capsule().fill(Color.accentColor).frame(width: 2, height: 14)
    }

    /// Room either side, so the playhead on the first or last frame stays whole.
    private static let inset: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 2 * Self.inset, 1)
            let x = { (frame: UInt64) in Self.inset + CraftScrub.x(ofFrame: frame, width: width, duration: duration) }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: width, height: 4)
                    .offset(x: Self.inset)
                if let range {
                    let start = CraftScrub.x(ofEdge: range.lowerBound, width: width, duration: duration)
                    let end = CraftScrub.x(ofEdge: range.upperBound, width: width, duration: duration)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: max(end - start, 4), height: 6)
                        .offset(x: Self.inset + start)
                    bracket.offset(x: Self.inset + start - 1)
                    bracket.offset(x: Self.inset + end - 1)
                }
                // White with a hairline and a shadow, as a system slider's thumb: it reads over the
                // glass, the shading and the canvas, light or dark.
                Capsule()
                    .fill(.white)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                    .frame(width: scrubbing ? 8 : 6, height: scrubbing ? 30 : 24)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: x(shown) - (scrubbing ? 4 : 3))
                    .animation(.snappy(duration: 0.15), value: scrubbing)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, touching, _ in touching = true }
                    .onChanged { drag in
                        let frame = CraftScrub.frame(atX: drag.location.x - Self.inset, width: width, duration: duration)
                        if active {
                            moved(frame)
                        } else {
                            active = true
                            began(frame)
                        }
                    }
                    .onEnded { drag in
                        guard active else { return }
                        active = false
                        ended(CraftScrub.frame(atX: drag.location.x - Self.inset, width: width, duration: duration))
                    }
            )
        }
        .frame(height: 44)
        // A drag that ended normally has cleared `active` by the time this runs; one SwiftUI
        // cancelled (another gesture took over, the view lost its window) hasn't.
        .onChange(of: touching) { _, touching in
            guard !touching, active else { return }
            active = false
            cancelled()
        }
    }
}

#if DEBUG
extension CraftTransport {
    /// The catalogue's example: frame 12 of 30 at 24 fps, the work area the first 24 frames.
    static let preview = CraftTransport(id: "transport", position: 11, duration: 30, rate: 24, range: 0..<24)
}

#Preview("Transport") {
    if let transport = CraftTransport.preview {
        VStack(spacing: 24) {
            CraftTransportView(transport: transport, panel: "timeline", send: { print($0) })
            CraftTransportView(transport: transport.with(playing: true), panel: "timeline", send: { print($0) })
            CraftTransportView(transport: transport, panel: "timeline", send: { print($0) }).frame(width: 320)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.5))
    }
}
#endif
