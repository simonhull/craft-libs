import Foundation
import Testing
@testable import CraftUI

@Suite struct ChromeTests {
    private func json(_ message: CraftChromeMessage) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(message))
    }

    private func value(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Exactly what craft-mobile's `Control::parse` reads (its `control` tests use the same JSON).
    @Test func messagesEncodeAsRustReadsThem() throws {
        #expect(try json(.shell([.status, .panels, .rail, .menus, .rail])) == value(#"{"action":"shell","features":["panels","menus","rail","status"]}"#))
        #expect(try json(.shell([])) == value(#"{"action":"shell","features":[]}"#))
        #expect(try json(.command("edit.undo")) == value(#"{"action":"command","id":"edit.undo"}"#))
        #expect(try json(.shortcut("Cmd+Shift+Z")) == value(#"{"action":"shortcut","keys":"Cmd+Shift+Z"}"#))
    }
}
