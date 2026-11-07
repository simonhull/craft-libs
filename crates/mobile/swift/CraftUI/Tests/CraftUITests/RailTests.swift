import Foundation
import Testing
@testable import CraftUI

@Suite struct RailTests {
    @Test func theCataloguesPaletteDecodes() throws {
        let entry = try #require(try NodeDecodingTests.catalogue().primitives.first { $0.name == "tool_palette" })
        guard case let .toolPalette(palette) = entry.example else { Issue.record("not a palette: \(entry.example)"); return }
        #expect(palette == .preview)
        #expect(palette.optionsRoute == .panel("brush"))
    }

    @Test func aRailPanelDecodes() throws {
        let json = #"{"panels":[{"id":"tools","title":"Tools","icon":"hammer","role":"rail"}],"open":{}}"#
        #expect(try JSONDecoder().decode(CraftPanels.self, from: Data(json.utf8)).panels.map(\.role) == [.rail])
    }

    /// A palette whose selected tool isn't among its tools still decodes (Rust validates); a slot
    /// shows its first tool then.
    @Test func aSlotShowsTheSelectedToolElseItsFirst() throws {
        let slot = try #require(CraftToolPalette.preview.slots[safe: 1])
        #expect(slot.shown(selected: "pencil")?.id == "pencil")
        #expect(slot.shown(selected: "move")?.id == "brush")
    }

    @Test func optionsAreThePanelElseTheFallbackCommand() {
        let palette = CraftToolPalette.preview
        #expect(palette.optionsRoute == .panel("brush"))
        #expect(CraftToolPalette(id: "p", slots: palette.slots, selected: "move", fallbackOptions: "window.toggle.optionsBar").optionsRoute == .command("window.toggle.optionsBar"))
        #expect(palette.withoutOptions.optionsRoute == nil)
        #expect(palette.selecting("pencil").selected == "pencil")
    }

    @Test func anIconIsItsSymbolElseItsLetterElseTheLabelsFirstLetter() {
        let none: (String) -> Bool = { _ in false }
        let all: (String) -> Bool = { _ in true }
        #expect(CraftToolIcon(symbol: "paintbrush.pointed", letter: "B").shown(label: "Brush", exists: all) == .symbol("paintbrush.pointed"))
        #expect(CraftToolIcon(symbol: "no.such.symbol", letter: "B").shown(label: "Brush", exists: none) == .letter("B"))
        #expect(CraftToolIcon(symbol: "no.such.symbol").shown(label: "smudge", exists: none) == .letter("S"))
        #expect(CraftToolIcon().shown(label: "", exists: none) == .letter("?"))
    }

    @Test func theSystemSymbolCheckIsReal() {
        #expect(CraftToolIcon.symbolExists("paintbrush.pointed"))
        #expect(!CraftToolIcon.symbolExists("craft.no.such.symbol"))
    }

    /// A tap selects; a second tap on the same tool within the interval opens its options, the
    /// selected one included; a lone tap on the selected tool does nothing.
    @Test func tapsSelectAndADoubleTapOpensOptions() {
        var taps = CraftRailTaps()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        #expect(taps.tap("pencil", selected: "brush", at: t0) == .select)
        #expect(taps.tap("pencil", selected: "brush", at: t0 + 0.2) == .options, "the app hasn't described the pick yet")
        #expect(taps.tap("pencil", selected: "pencil", at: t0 + 0.3) == .nothing, "a third tap starts over")
        #expect(taps.tap("pencil", selected: "pencil", at: t0 + 2) == .nothing)
        #expect(taps.tap("pencil", selected: "pencil", at: t0 + 2.3) == .options)
        #expect(taps.tap("brush", selected: "pencil", at: t0 + 2.4) == .select)
        #expect(taps.tap("move", selected: "brush", at: t0 + 2.5) == .select, "another tool isn't a double-tap")
        #expect(taps.tap("move", selected: "move", at: t0 + 3) == .nothing, "too late")
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
