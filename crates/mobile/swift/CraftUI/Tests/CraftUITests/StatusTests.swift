import Foundation
import Testing
@testable import CraftUI

@Suite struct StatusTests {
    @Test func theCataloguesStatusDecodes() throws {
        let url = try #require(Bundle.module.url(forResource: "ui", withExtension: "json", subdirectory: "Fixtures"))
        struct Catalogue: Decodable { let chrome: [Entry] }
        struct Entry: Decodable {
            let name: String
            let status: CraftStatus?
            enum Key: String, CodingKey { case name, example }
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: Key.self)
                name = try c.decode(String.self, forKey: .name)
                status = name == "status" ? try c.decode(CraftStatus.self, forKey: .example) : nil
            }
        }
        let catalogue = try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url))
        #expect(catalogue.chrome.first { $0.name == "status" }?.status == .preview)
    }

    /// Nothing to say decodes as nothing; a part this kit can't read is left out; an unknown tone is info.
    @Test func decodingIsLenient() throws {
        func decode(_ json: String) throws -> CraftStatus { try JSONDecoder().decode(CraftStatus.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"message":null,"progress":null}"#) == CraftStatus())
        #expect(try decode(#"{"message":{"text":"Hi","tone":"cheerful"},"progress":null}"#).message == .init(text: "Hi", tone: .info))
        let broken = try decode(#"{"message":{"tone":"error"},"progress":{"label":"Exporting","fraction":null,"cancel":null}}"#)
        #expect(broken.message == nil)
        #expect(broken.progress == .init(label: "Exporting"))
    }

    @Test func aDismissedMessageStaysDismissedAndANewOneShows() {
        let saved = CraftStatus.Message(text: "Saved")
        let failed = CraftStatus.Message(text: "Couldn't save", tone: .error)
        #expect(CraftStatusView.shown(saved, dismissed: nil) == saved)
        #expect(CraftStatusView.shown(saved, dismissed: CraftStatusView.identity(saved)) == nil)
        #expect(CraftStatusView.shown(failed, dismissed: CraftStatusView.identity(saved)) == failed)
        #expect(CraftStatusView.shown(nil, dismissed: nil) == nil)
    }

    /// Two saves say "Saved" twice: a new id is a new message, which shows even after the first was
    /// dismissed; older apps send no id.
    @Test func aNewIdShowsTheSameTextAgain() throws {
        let first = CraftStatus.Message(text: "Saved", id: 1)
        let second = CraftStatus.Message(text: "Saved", id: 2)
        #expect(CraftStatusView.shown(second, dismissed: CraftStatusView.identity(first)) == second)
        let old = try JSONDecoder().decode(CraftStatus.Message.self, from: Data(#"{"text":"Saved","tone":"info"}"#.utf8))
        #expect(old == CraftStatus.Message(text: "Saved"))
    }

    /// A countdown ("retrying in 3 s", "in 2 s") keeps its id: it is one toast whose text changes in
    /// place, and once dismissed it stays dismissed while it counts. A new id is a new toast.
    @Test func aCountdownIsOneToastAndANewMessageAnother() {
        let three = CraftStatus.Message(text: "Scratch disk low, retrying in 3 s", tone: .error, id: 5)
        let two = CraftStatus.Message(text: "Scratch disk low, retrying in 2 s", tone: .error, id: 5)
        #expect(CraftStatusView.identity(three) == CraftStatusView.identity(two), "updated in place")
        #expect(CraftStatusView.shown(two, dismissed: CraftStatusView.identity(three)) == nil, "dismissed, it stays so while it counts")
        let saved = CraftStatus.Message(text: "Saved a.psd", id: 6)
        #expect(CraftStatusView.identity(saved) != CraftStatusView.identity(two), "a new toast")
        #expect(CraftStatusView.shown(saved, dismissed: CraftStatusView.identity(two)) == saved)
    }

    /// Without an id, a message is its text and tone: a change of either is a new toast.
    @Test func anUnnumberedMessageIsItsText() {
        let a = CraftStatus.Message(text: "Retrying in 3 s")
        let b = CraftStatus.Message(text: "Retrying in 2 s")
        #expect(CraftStatusView.identity(a) != CraftStatusView.identity(b))
        #expect(CraftStatusView.identity(a) != CraftStatusView.identity(CraftStatus.Message(text: "Retrying in 3 s", tone: .error)))
        #expect(CraftStatusView.identity(a) == CraftStatusView.identity(CraftStatus.Message(text: "Retrying in 3 s")))
    }

    /// VoiceOver hears a new toast, an error as one; not a countdown's next second.
    @Test func aNewToastIsAnnouncedAndNewTextForItIsNot() {
        let tick = CraftStatus.Message(text: "Retrying in 9 s", tone: .error, id: 4)
        #expect(CraftStatusView.announcement(tick, replacing: nil) == "Error: Retrying in 9 s")
        let next = CraftStatus.Message(text: "Retrying in 8 s", tone: .error, id: 4)
        #expect(CraftStatusView.announcement(next, replacing: CraftStatusView.identity(tick)) == nil)
        let saved = CraftStatus.Message(text: "Saved a.psd")
        #expect(CraftStatusView.announcement(saved, replacing: CraftStatusView.identity(tick)) == "Saved a.psd")
    }

    @Test func anErrorStaysLonger() {
        #expect(CraftStatusView.duration(.error) > CraftStatusView.duration(.info))
    }
}
