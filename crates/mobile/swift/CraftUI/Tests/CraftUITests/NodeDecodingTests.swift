import Foundation
import Testing
@testable import CraftUI

/// Any JSON value, compared strictly (a bool is never a number), for checking encoders against the catalogue.
enum JSONValue: Decodable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = try .object(c.decode([String: JSONValue].self)) }
    }
}

@Suite struct NodeDecodingTests {
    struct Catalogue: Decodable { let version: Int; let primitives: [Entry] }
    struct Entry: Decodable { let name: String; let example: CraftNode; let edit: JSONValue? }

    static func catalogue() throws -> Catalogue {
        let url = try #require(Bundle.module.url(forResource: "ui", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url))
    }

    @Test func everyCatalogueExampleDecodes() throws {
        let catalogue = try Self.catalogue()
        #expect(catalogue.version == 1)
        #expect(catalogue.primitives.map(\.name) == ["number", "toggle", "choice", "section", "item_list"])
        for entry in catalogue.primitives {
            if case .unknown = entry.example { Issue.record("\(entry.name) decoded as unknown") }
        }
    }

    /// The catalogue's sample edits are what Rust parses; `CraftEdit` must encode the same JSON.
    @Test func editsEncodeAsTheCatalogueSays() throws {
        let expected: [String: CraftEdit] = [
            "number": CraftEdit(panel: "layers", control: "opacity", phase: .change, gesture: 7, value: .number(0.5)),
            "toggle": CraftEdit(panel: "layers", control: "visible", phase: .commit, gesture: 8, value: .toggle(false)),
            "choice": CraftEdit(panel: "layers", control: "blend", phase: .commit, gesture: 9, value: .choice("multiply")),
            "item_list": CraftEdit(panel: "layers", control: "layers", phase: .commit, gesture: 10, value: .move(row: 1, target: 2, position: .above)),
        ]
        var checked = 0
        for entry in try Self.catalogue().primitives {
            guard let sample = entry.edit, sample != .null else { continue }
            let edit = try #require(expected[entry.name], "no Swift edit for the catalogue's \(entry.name) sample")
            let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(edit))
            #expect(encoded == sample, "\(entry.name)")
            checked += 1
        }
        #expect(checked == expected.count)
    }

    @Test func theWireEnvelopeDecodes() throws {
        let json = #"""
        {"panels":[{"id":"layers","title":"Layers","icon":"square.3.layers.3d","role":"inspector"},
                   {"id":"brush","title":"Brush","icon":"paintbrush.pointed","role":"tool"}],
         "open":{"layers":{"id":"layers","title":"Layers","role":"inspector",
                 "nodes":[{"type":"toggle","id":"visible","label":"Visible","value":true,"enabled":true}]}}}
        """#
        let panels = try JSONDecoder().decode(CraftPanels.self, from: Data(json.utf8))
        #expect(panels.panels.map(\.role) == [.inspector, .tool])
        #expect(panels.open["layers"]?.nodes == [.toggle(id: "visible", label: "Visible", value: true, enabled: true)])
    }

    /// One bad node shows as a placeholder; the rest of the panel, and the other panels, still show.
    @Test func aMalformedNodeBecomesAPlaceholder() throws {
        let json = #"""
        {"id":"layers","title":"Layers","role":"inspector","nodes":[
          {"type":"toggle","id":"bad","label":"No value","enabled":true},
          {"type":"section","id":"s","title":"S","collapsed":false,"children":[
            {"type":"number","id":"n","label":"No range","value":1,"unit":"none","enabled":true}, 7]},
          {"type":"toggle","id":"ok","label":"Fine","value":true,"enabled":true}]}
        """#
        let panel = try JSONDecoder().decode(CraftPanel.self, from: Data(json.utf8))
        #expect(panel.nodes == [
            .malformed(type: "toggle"),
            .section(id: "s", title: "S", collapsed: false, children: [.malformed(type: "number"), .unknown(type: "")]),
            .toggle(id: "ok", label: "Fine", value: true, enabled: true),
        ])
    }

    /// A newer app's panel role, or a broken entry, drops only that panel: the others still show.
    @Test func theEnvelopeSkipsPanelsItCantShow() throws {
        let json = #"""
        {"panels":[{"id":"layers","title":"Layers","icon":"square.3.layers.3d","role":"inspector"},
                   {"id":"timeline","title":"Timeline","icon":"film","role":"drawer"},
                   {"id":"broken","title":"No icon","role":"tool"},
                   {"id":"brush","title":"Brush","icon":"paintbrush.pointed","role":"tool"}],
         "open":{"layers":{"id":"layers","title":"Layers","role":"inspector","nodes":[]},
                 "timeline":{"id":"timeline","title":"Timeline","role":"drawer","nodes":[]},
                 "brush":{"id":"brush","title":"Brush","role":"tool"}}}
        """#
        let panels = try JSONDecoder().decode(CraftPanels.self, from: Data(json.utf8))
        #expect(panels.panels.map(\.id) == ["layers", "brush"])
        #expect(Array(panels.open.keys) == ["layers"])
    }

    @Test func anUnknownNodeBecomesAPlaceholder() throws {
        let node = try JSONDecoder().decode(CraftNode.self, from: Data(#"{"type":"hologram","id":"x"}"#.utf8))
        #expect(node == .unknown(type: "hologram"))
    }

    @Test func rowEditsEncodeAsRustReadsThem() throws {
        let edits: [(CraftEdit.Value, String)] = [
            (.select(row: 2), #"{"kind":"select","value":{"row":2}}"#),
            (.setVisible(row: 2, visible: false), #"{"kind":"set_visible","value":{"row":2,"visible":false}}"#),
            (.rename(row: 4, name: "Sky"), #"{"kind":"rename","value":{"row":4,"name":"Sky"}}"#),
            (.move(row: 4, target: 9, position: .below), #"{"kind":"move","value":{"row":4,"target":9,"position":"below"}}"#),
        ]
        for (value, json) in edits {
            let edit = CraftEdit(panel: "layers", control: "rows", phase: .commit, gesture: 1, value: value)
            let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(edit))
            let expected = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"action":"edit","panel":"layers","control":"rows","phase":"commit","gesture":1,"value":\#(json)}"#.utf8))
            #expect(encoded == expected)
        }
    }
}
