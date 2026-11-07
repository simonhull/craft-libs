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
        #expect(CraftStatusView.shown(saved, dismissed: saved) == nil)
        #expect(CraftStatusView.shown(failed, dismissed: saved) == failed)
        #expect(CraftStatusView.shown(nil, dismissed: nil) == nil)
    }

    @Test func anErrorStaysLonger() {
        #expect(CraftStatusView.duration(.error) > CraftStatusView.duration(.info))
    }
}
