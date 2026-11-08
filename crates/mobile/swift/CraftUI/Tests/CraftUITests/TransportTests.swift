import Foundation
import Observation
import Synchronization
import Testing
@testable import CraftUI

@Suite struct TransportDecodingTests {
    static func node(_ json: String) throws -> CraftNode {
        try JSONDecoder().decode(CraftNode.self, from: Data(json.utf8))
    }

    static func transport(_ fields: String) throws -> CraftTransport? {
        guard case let .transport(t) = try node(#"{"type":"transport","id":"transport",\#(fields)}"#) else { return nil }
        return t
    }

    @Test func theCataloguesTransportDecodes() throws {
        let entry = try #require(try NodeDecodingTests.catalogue().primitives.first { $0.name == "transport" })
        #expect(entry.example == .transport(try #require(CraftTransport(id: "transport", position: 11, duration: 30, rate: 24, range: 0..<24))))
    }

    @Test func everyFieldDecodes() throws {
        let t = try #require(try Self.transport(#""position":3,"duration":100,"rate":29.97,"format":"timecode","playing":true,"range":[10,20],"enabled":false"#))
        #expect(t.position == 3 && t.duration == 100 && t.rate == 29.97)
        #expect(t.format == .timecode && t.playing && t.range == 10..<20 && !t.enabled)
        #expect(CraftNode.transport(t).id == "transport")
    }

    /// What Rust may leave out (format, range), a newer format, and values a strict decoder would
    /// refuse but that can still be shown.
    @Test func decodingIsLenient() throws {
        let bare = try #require(try Self.transport(#""position":0,"duration":30,"rate":24,"playing":false"#))
        #expect(bare.format == .frames && bare.range == nil && bare.enabled, "format, range and enabled left out")
        #expect(try Self.transport(#""position":0,"duration":30,"rate":24,"playing":false,"format":"bars_beats","enabled":true"#)?.format == .frames)
        #expect(try Self.transport(#""position":0,"duration":30,"rate":24,"playing":false,"range":null,"enabled":true"#)?.range == nil)
        #expect(try Self.transport(#""position":0,"duration":30,"rate":24,"playing":false,"range":[5,5],"enabled":true"#)?.range == nil, "empty")
        #expect(try Self.transport(#""position":0,"duration":30,"rate":24,"playing":false,"range":[9,3],"enabled":true"#)?.range == nil, "backwards")
        #expect(try Self.transport(#""position":0,"duration":30,"rate":24,"playing":false,"range":[1],"enabled":true"#)?.range == nil, "not a pair")
        #expect(try Self.transport(#""position":0,"duration":30,"rate":24,"playing":false,"range":"all","enabled":true"#)?.range == nil, "not a list")
        #expect(try Self.transport(#""position":0,"duration":30,"rate":24,"playing":false,"range":[20,40],"enabled":true"#)?.range == 20..<30, "cut to the frames")
        #expect(try Self.transport(#""position":0,"duration":30,"rate":24,"playing":false,"range":[30,40],"enabled":true"#)?.range == nil, "wholly past them")
        #expect(try Self.transport(#""position":99,"duration":30,"rate":24,"playing":false,"enabled":true"#)?.position == 29, "past the end: the last frame")
    }

    /// Without frames, a usable rate, or a required field, it can't be shown: a placeholder, and the
    /// rest of the panel still shows.
    @Test func whatCantBeShownIsMalformed() throws {
        let json = #"""
        {"id":"timeline","title":"Timeline","role":"transport","nodes":[
          {"type":"transport","id":"a","position":0,"duration":0,"rate":24,"playing":false,"enabled":true},
          {"type":"transport","id":"b","position":0,"duration":30,"rate":0,"playing":false,"enabled":true},
          {"type":"transport","id":"c","position":0,"duration":30,"rate":-24,"playing":false,"enabled":true},
          {"type":"transport","id":"d","position":0,"duration":30,"playing":false,"enabled":true},
          {"type":"transport","id":"e","position":-1,"duration":30,"rate":24,"playing":false,"enabled":true},
          {"type":"transport","id":"ok","position":0,"duration":30,"rate":24,"playing":false,"enabled":true}]}
        """#
        let panel = try JSONDecoder().decode(CraftPanel.self, from: Data(json.utf8))
        #expect(panel.role == .transport)
        #expect(panel.nodes.dropLast().allSatisfy { $0 == .malformed(type: "transport") })
        #expect(panel.nodes.last?.id == "ok")
    }

    @Test func theTransportRoleDecodes() throws {
        let json = #"{"panels":[{"id":"timeline","title":"Timeline","icon":"play","role":"transport"}],"open":{}}"#
        let panels = try JSONDecoder().decode(CraftPanels.self, from: Data(json.utf8))
        #expect(panels.panels == [CraftPanelInfo(id: "timeline", title: "Timeline", icon: "play", role: .transport)])
    }

    @Test func theConstructorKeepsItValid() throws {
        #expect(CraftTransport(id: "t", position: 0, duration: 0, rate: 24) == nil)
        #expect(CraftTransport(id: "t", position: 0, duration: 1, rate: .nan) == nil)
        #expect(CraftTransport(id: "t", position: 0, duration: 1, rate: .infinity) == nil)
        let t = try #require(CraftTransport(id: "t", position: 40, duration: 30, rate: 24, range: 25..<90))
        #expect(t.position == 29 && t.range == 25..<30)
        #expect(t.with(position: 100).position == 29)
        #expect(t.with(playing: true).playing && t.with(playing: true).position == 29)
    }
}

@Suite struct TransportEditTests {
    static func encoded(_ value: CraftEdit.Value, phase: CraftEdit.Phase = .commit) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(CraftEdit(panel: "timeline", control: "transport", phase: phase, gesture: 4, value: value)))
    }

    static func expected(_ phase: String, _ value: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(#"{"action":"edit","panel":"timeline","control":"transport","phase":"\#(phase)","gesture":4,"value":\#(value)}"#.utf8))
    }

    @Test func aSeekEncodesAsRustReadsIt() throws {
        for (phase, name) in [(CraftEdit.Phase.begin, "begin"), (.change, "change"), (.commit, "commit"), (.cancel, "cancel")] {
            #expect(try Self.encoded(.seek(frame: 12), phase: phase) == Self.expected(name, #"{"kind":"seek","value":{"frame":12}}"#))
        }
    }

    @Test func eachTransportActionEncodesByName() throws {
        let names: [CraftTransportAction: String] = [
            .play: "play", .pause: "pause", .stop: "stop", .stepBack: "step_back", .stepForward: "step_forward", .toStart: "to_start", .toEnd: "to_end",
        ]
        #expect(names.count == CraftTransportAction.allCases.count)
        for (action, name) in names {
            #expect(try Self.encoded(.transport(action)) == Self.expected("commit", #"{"kind":"transport","value":"\#(name)"}"#))
        }
    }

    @Test func theButtonsSymbolsExist() {
        for symbol in ["backward.end.fill", "backward.frame.fill", "play.fill", "pause.fill", "forward.frame.fill", "forward.end.fill"] {
            #expect(CraftToolIcon.symbolExists(symbol), "\(symbol)")
        }
    }
}

@Suite struct TimeLabelTests {
    @Test func framesCountFromOneOfTheDuration() throws {
        #expect(CraftTransport.label(frame: 11, duration: 30, rate: 24, format: .frames) == "12 / 30")
        #expect(CraftTransport.label(frame: 0, duration: 1, rate: 24, format: .frames) == "1 / 1")
        let t = try #require(CraftTransport(id: "t", position: 0, duration: 120, rate: 24))
        #expect(t.label(at: 119) == "120 / 120")
        #expect(t.widestLabel == "120 / 120")
        #expect(t.spokenLabel(at: 4) == "Frame 5 of 120")
    }

    @Test func timecodeAtWholeRates() {
        #expect(CraftTransport.timecode(frame: 0, rate: 24) == "00:00:00:00")
        #expect(CraftTransport.timecode(frame: 11, rate: 24) == "00:00:00:11")
        #expect(CraftTransport.timecode(frame: 24, rate: 24) == "00:00:01:00")
        #expect(CraftTransport.timecode(frame: 24 * 3600 + 24 * 61 + 5, rate: 24) == "01:01:01:05")
        #expect(CraftTransport.timecode(frame: 24, rate: 25) == "00:00:00:24")
        #expect(CraftTransport.timecode(frame: 25 * 60, rate: 25) == "00:01:00:00")
        #expect(CraftTransport.timecode(frame: 29, rate: 30) == "00:00:00:29")
        #expect(CraftTransport.timecode(frame: 30 * 600, rate: 30) == "00:10:00:00")
        #expect(CraftTransport.timecode(frame: 24 * 3600 * 25, rate: 24) == "25:00:00:00", "hours don't wrap")
        #expect(CraftTransport.label(frame: 11, duration: 30, rate: 24, format: .timecode) == "00:00:00:11")
    }

    /// 29.97 drops frame numbers 0 and 1 each minute, except every tenth minute.
    @Test func dropFrameAt2997() {
        for rate in [29.97, 30000.0 / 1001] {
            #expect(CraftTransport.timecode(frame: 0, rate: rate) == "00:00:00;00")
            #expect(CraftTransport.timecode(frame: 1799, rate: rate) == "00:00:59;29")
            #expect(CraftTransport.timecode(frame: 1800, rate: rate) == "00:01:00;02", "00 and 01 dropped")
            #expect(CraftTransport.timecode(frame: 3597, rate: rate) == "00:01:59;29")
            #expect(CraftTransport.timecode(frame: 3598, rate: rate) == "00:02:00;02")
            #expect(CraftTransport.timecode(frame: 17981, rate: rate) == "00:09:59;29")
            #expect(CraftTransport.timecode(frame: 17982, rate: rate) == "00:10:00;00", "every tenth minute keeps them")
            #expect(CraftTransport.timecode(frame: 17984, rate: rate) == "00:10:00;02")
            #expect(CraftTransport.timecode(frame: 107_892, rate: rate) == "01:00:00;00", "an hour of 29.97 is 107 892 frames")
        }
    }

    @Test func dropFrameAt5994() {
        #expect(CraftTransport.timecode(frame: 3599, rate: 59.94) == "00:00:59;59")
        #expect(CraftTransport.timecode(frame: 3600, rate: 59.94) == "00:01:00;04")
        #expect(CraftTransport.timecode(frame: 35964, rate: 59.94) == "00:10:00;00")
    }

    /// Other fractional rates are non-drop at the rate rounded up.
    @Test func otherRatesAreNonDropAtTheNominalRate() {
        #expect(CraftTransport.dropFrames(rate: 23.976) == nil)
        #expect(CraftTransport.timecode(frame: 24, rate: 23.976) == "00:00:01:00")
        #expect(CraftTransport.timecode(frame: 23, rate: 23.976) == "00:00:00:23")
        #expect(CraftTransport.timecode(frame: 24, rate: 24.000_000_1) == "00:00:01:00", "a hair over 24 is 24")
        #expect(CraftTransport.timecode(frame: 3, rate: 0.5) == "00:00:03:00", "below 1 fps: a frame a second")
        #expect(CraftTransport.timecode(frame: 0, rate: 30) == "00:00:00:00", "30 is non-drop")
    }
}

@Suite struct ScrubTests {
    @Test func xMapsToAFrameOnTheTrack() {
        // 30 frames over 300 points: 10 points a frame.
        #expect(CraftScrub.frame(atX: 0, width: 300, duration: 30) == 0)
        #expect(CraftScrub.frame(atX: 9.9, width: 300, duration: 30) == 0)
        #expect(CraftScrub.frame(atX: 10, width: 300, duration: 30) == 1)
        #expect(CraftScrub.frame(atX: 155, width: 300, duration: 30) == 15)
        #expect(CraftScrub.frame(atX: 299.9, width: 300, duration: 30) == 29)
        #expect(CraftScrub.frame(atX: 300, width: 300, duration: 30) == 29, "the end: the last frame")
        #expect(CraftScrub.frame(atX: -40, width: 300, duration: 30) == 0, "past the start")
        #expect(CraftScrub.frame(atX: 9000, width: 300, duration: 30) == 29, "past the end")
        #expect(CraftScrub.frame(atX: .nan, width: 300, duration: 30) == 0)
        #expect(CraftScrub.frame(atX: 50, width: 0, duration: 30) == 0)
        #expect(CraftScrub.frame(atX: 50, width: 300, duration: 1) == 0)
        #expect(CraftScrub.frame(atX: .infinity, width: 300, duration: .max) == UInt64.max - 1)
    }

    @Test func framesSitInTheMiddleOfTheirCells() {
        #expect(CraftScrub.x(ofFrame: 0, width: 300, duration: 30) == 5)
        #expect(CraftScrub.x(ofFrame: 29, width: 300, duration: 30) == 295)
        #expect(CraftScrub.x(ofFrame: 99, width: 300, duration: 30) == 295, "kept on the track")
        #expect(CraftScrub.x(ofEdge: 24, width: 300, duration: 30) == 240)
        #expect(CraftScrub.x(ofEdge: 30, width: 300, duration: 30) == 300)
        for frame in UInt64(0)..<30 {
            #expect(CraftScrub.frame(atX: CraftScrub.x(ofFrame: frame, width: 300, duration: 30), width: 300, duration: 30) == frame)
        }
    }

    /// A drag: begin where the finger lands, change only when the frame does, commit at release.
    @Test func aDragSendsChangesOnlyOnANewFrame() throws {
        var scrub = CraftScrub()
        let begin = scrub.begin(at: 4, from: 11)
        #expect(begin.phase == .begin && begin.frame == 4)
        #expect(scrub.move(to: 4) == nil, "same frame: nothing")
        let moved = scrub.move(to: 5)
        let change = try #require(moved)
        #expect(change == CraftScrub.Step(gesture: begin.gesture, phase: .change, frame: 5))
        #expect(scrub.move(to: 5) == nil)
        #expect(scrub.shown(app: 11) == 5, "the finger's frame, not the app's")
        let committed = scrub.commit(at: 6)
        let commit = try #require(committed)
        #expect(commit == CraftScrub.Step(gesture: begin.gesture, phase: .commit, frame: 6))
        #expect(!scrub.isScrubbing && scrub.move(to: 7) == nil && scrub.commit(at: 7) == nil)
        #expect(scrub.shown(app: 5) == 6, "the frame it ended on until the app says")
        scrub.settled()
        #expect(scrub.shown(app: 5) == 5, "then the app's")
    }

    /// The view's rule: once a drag ends, anything new from the app (a description, changed or not,
    /// or another position) settles it; the same word again doesn't.
    @Test func whatTheAppSaysSettlesAnEndedDrag() throws {
        let before = CraftScrub.Word(descriptions: 4, position: 11)
        var scrub = CraftScrub()
        _ = scrub.begin(at: 2, from: 11)
        #expect(!scrub.settles(after: before, now: .init(descriptions: 4, position: 2)), "mid-drag the finger's frame shows: nothing to settle")
        _ = scrub.commit(at: 6)
        #expect(!scrub.settles(after: before, now: before), "nothing new")
        #expect(scrub.settles(after: before, now: .init(descriptions: 5, position: 11)), "a description, the position unchanged (a refused seek)")
        #expect(scrub.settles(after: before, now: .init(descriptions: 4, position: 6)), "a live position")
        scrub.settled()
        #expect(!scrub.settles(after: before, now: .init(descriptions: 5, position: 6)), "already settled")
    }

    /// A tap is a begin and a commit, each its own gesture number from the next tap's.
    @Test func aTapSeeks() throws {
        var scrub = CraftScrub()
        let begin = scrub.begin(at: 20, from: 0)
        let committed = scrub.commit(at: 20)
        let commit = try #require(committed)
        #expect([begin.phase, commit.phase] == [.begin, .commit] && commit.frame == 20 && commit.gesture == begin.gesture)
        #expect(scrub.begin(at: 1, from: 20).gesture != begin.gesture)
    }

    @Test func aCancelledDragPutsThePlayheadBack() throws {
        var scrub = CraftScrub()
        let begin = scrub.begin(at: 2, from: 11)
        _ = scrub.move(to: 3)
        let cancelled = scrub.cancel()
        let cancel = try #require(cancelled)
        #expect(cancel == CraftScrub.Step(gesture: begin.gesture, phase: .cancel, frame: 11))
        #expect(scrub.cancel() == nil)
        #expect(scrub.shown(app: 3) == 3, "the app's frame: it puts the playhead back, or doesn't, and says where")
        #expect(scrub.shown(app: 11) == 11)
    }

    @Test func crossingTheWorkAreasEdges() {
        let range: Range<UInt64> = 10..<20
        #expect(CraftScrub.crossesEdge(from: 9, to: 10, range: range), "in at the start")
        #expect(CraftScrub.crossesEdge(from: 10, to: 9, range: range), "out at the start")
        #expect(CraftScrub.crossesEdge(from: 19, to: 20, range: range), "out at the end")
        #expect(CraftScrub.crossesEdge(from: 25, to: 15, range: range))
        #expect(CraftScrub.crossesEdge(from: 0, to: 29, range: range), "across it")
        #expect(!CraftScrub.crossesEdge(from: 11, to: 18, range: range), "inside")
        #expect(!CraftScrub.crossesEdge(from: 2, to: 8, range: range), "outside")
        #expect(!CraftScrub.crossesEdge(from: 2, to: 18, range: nil), "no work area")
    }
}

@MainActor @Suite struct LiveValueTests {
    @Test func kind17SetsPositionsUntilTheNextDescription() throws {
        let live = CraftLiveValues()
        try live.apply(json: Data(#"[{"panel":"timeline","control":"transport","position":12}]"#.utf8))
        #expect(live.position(panel: "timeline", control: "transport") == 12)
        #expect(live.position(panel: "other", control: "transport") == nil)
        try live.apply(json: Data(#"[{"panel":"timeline","control":"nested","position":3}]"#.utf8))
        #expect(live.position(panel: "timeline", control: "transport") == 12, "only those that changed are sent: the rest stay")
        #expect(live.position(panel: "timeline", control: "nested") == 3)
        live.described()
        #expect(live.positions.isEmpty, "a description carries the positions itself")
    }

    @Test func aBadEntryIsSkippedAndABadListChangesNothing() throws {
        let live = CraftLiveValues()
        try live.apply(json: Data(#"[{"panel":"timeline","position":1},{"panel":"timeline","control":"transport","position":7}]"#.utf8))
        #expect(live.positions == [.init(panel: "timeline", control: "transport"): 7])
        #expect(throws: DecodingError.self) { try live.apply(json: Data(#"{"panel":"timeline"}"#.utf8)) }
        #expect(live.positions == [.init(panel: "timeline", control: "transport"): 7])
    }

    /// Where the transport view puts the app's playhead: the live position for this transport, if
    /// one came since the description, kept on a frame.
    @Test func theAppsPlayheadIsTheLivePositionElseTheDescribedOne() throws {
        let transport = try #require(CraftTransport(id: "transport", position: 4, duration: 30, rate: 24))
        let live = CraftLiveValues()
        #expect(transport.appPosition(panel: "timeline", live: nil) == 4, "no live values in the environment")
        #expect(transport.appPosition(panel: "timeline", live: live) == 4, "none yet")
        live.apply([CraftLiveValue(panel: "other", control: "transport", position: 9), CraftLiveValue(panel: "timeline", control: "nested", position: 8)])
        #expect(transport.appPosition(panel: "timeline", live: live) == 4, "another transport's")
        live.apply([CraftLiveValue(panel: "timeline", control: "transport", position: 12)])
        #expect(transport.appPosition(panel: "timeline", live: live) == 12)
        live.apply([CraftLiveValue(panel: "timeline", control: "transport", position: 99)])
        #expect(transport.appPosition(panel: "timeline", live: live) == 29, "past the end: the last frame")
        live.described()
        #expect(transport.appPosition(panel: "timeline", live: live) == 4, "described again")
    }

    /// Observers (the transport views) hear of a position only when one changed.
    @Test func observersHearOnlyOfChanges() {
        let live = CraftLiveValues()
        live.apply([CraftLiveValue(panel: "p", control: "t", position: 1)])
        func notifies(_ change: () -> Void) -> Bool {
            let heard = Heard()
            withObservationTracking { _ = live.positions } onChange: { heard.value.withLock { $0 = true } }
            change()
            return heard.value.withLock { $0 }
        }
        #expect(!notifies { live.apply([CraftLiveValue(panel: "p", control: "t", position: 1)]) }, "the same position")
        #expect(notifies { live.apply([CraftLiveValue(panel: "p", control: "t", position: 2)]) })
        #expect(notifies { live.described() })
        #expect(!notifies { live.described() }, "already none")
    }
}

/// Whether an observer was told of a change (it may be told on any thread).
private final class Heard: Sendable {
    let value = Mutex(false)
}
