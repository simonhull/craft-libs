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
        #expect(catalogue.primitives.map(\.name) == ["number", "toggle", "choice", "section", "item_list", "tool_palette"])
        for entry in catalogue.primitives {
            if case .unknown = entry.example { Issue.record("\(entry.name) decoded as unknown") }
        }
    }

    /// The catalogue's sample edits are what Rust parses; `CraftEdit` must encode the same JSON.
    @Test func editsEncodeAsTheCatalogueSays() throws {
        let expected: [String: CraftEdit] = [
            "number": CraftEdit(panel: "brush", control: "size", phase: .change, gesture: 7, value: .number(120)),
            "toggle": CraftEdit(panel: "layers", control: "visible", phase: .commit, gesture: 8, value: .toggle(false)),
            "choice": CraftEdit(panel: "layers", control: "blend", phase: .commit, gesture: 9, value: .choice("multiply")),
            "item_list": CraftEdit(panel: "layers", control: "layers", phase: .commit, gesture: 10, value: .move(row: 1, target: 2, position: .above)),
            "tool_palette": CraftEdit(panel: "tools", control: "palette", phase: .commit, gesture: 11, value: .choice("pencil")),
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

    /// A number's `scale`: missing (as Rust leaves it for linear) or one this kit doesn't know is linear.
    @Test func aNumbersScaleDecodesAndDefaultsToLinear() throws {
        func scale(_ extra: String) throws -> CraftNode.Scale? {
            let json = #"{"type":"number","id":"n","label":"N","value":2,"min":1,"max":10,"step":null,"unit":"none","enabled":true\#(extra)}"#
            guard case let .number(_, _, _, _, _, _, _, _, scale) = try JSONDecoder().decode(CraftNode.self, from: Data(json.utf8)) else { return nil }
            return scale
        }
        #expect(try scale(#","scale":"log""#) == .log)
        #expect(try scale("") == .linear)
        #expect(try scale(#","scale":"linear""#) == .linear)
        #expect(try scale(#","scale":"spiral""#) == .linear)
        #expect(try scale(#","scale":null"#) == .linear)
    }

    @Test func theCataloguesNumberIsLogarithmic() throws {
        let number = try #require(try Self.catalogue().primitives.first { $0.name == "number" })
        guard case let .number(_, _, _, _, _, _, _, _, scale) = number.example else { Issue.record("not a number"); return }
        #expect(scale == .log)
    }

    @Test func anUnknownNodeBecomesAPlaceholder() throws {
        let node = try JSONDecoder().decode(CraftNode.self, from: Data(#"{"type":"hologram","id":"x"}"#.utf8))
        #expect(node == .unknown(type: "hologram"))
    }

    @Test func rowEditsEncodeAsRustReadsThem() throws {
        let edits: [(CraftEdit.Value, String)] = [
            (.select(row: 2), #"{"kind":"select","value":{"row":2,"mode":"replace"}}"#),
            (.select(row: 2, mode: .toggle), #"{"kind":"select","value":{"row":2,"mode":"toggle"}}"#),
            (.select(row: 2, mode: .range), #"{"kind":"select","value":{"row":2,"mode":"range"}}"#),
            (.setVisible(row: 2, visible: false), #"{"kind":"set_visible","value":{"row":2,"visible":false}}"#),
            (.rename(row: 4, name: "Sky"), #"{"kind":"rename","value":{"row":4,"name":"Sky"}}"#),
            (.move(row: 4, target: 9, position: .below), #"{"kind":"move","value":{"row":4,"target":9,"position":"below"}}"#),
            (.action(row: 4, action: "close"), #"{"kind":"action","value":{"row":4,"action":"close"}}"#),
        ]
        for (value, json) in edits {
            let edit = CraftEdit(panel: "layers", control: "rows", phase: .commit, gesture: 1, value: value)
            let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(edit))
            let expected = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"action":"edit","panel":"layers","control":"rows","phase":"commit","gesture":1,"value":\#(json)}"#.utf8))
            #expect(encoded == expected)
        }
    }

    /// The catalogue's layer rows carry a plain and a destructive action.
    @Test func theCataloguesRowsHaveActions() throws {
        let entry = try #require(try Self.catalogue().primitives.first { $0.name == "item_list" })
        guard case let .itemList(_, rows, _) = entry.example else {
            Issue.record("item_list didn't decode: \(entry.example)")
            return
        }
        let actions = try #require(rows.first?.actions)
        #expect(actions == [
            CraftRowAction(id: "duplicate", label: "Duplicate", icon: "plus.square.on.square"),
            CraftRowAction(id: "delete", label: "Delete", icon: "trash", destructive: true),
        ])
        #expect(actions.filter(\.destructive).map(\.id) == ["delete"], "the swipe actions")
    }

    /// A row from an older app has no actions; an action may leave out its icon and destructive; one
    /// that doesn't decode is skipped, the others kept.
    @Test func rowActionsAreOptionalAndLenient() throws {
        let old = try JSONDecoder().decode(CraftRow.self, from: Data(#"{"id":1,"title":"a","subtitle":"","depth":0,"visible":null,"selected":false}"#.utf8))
        #expect(old.actions.isEmpty)
        let json = #"{"id":1,"title":"a","subtitle":"","depth":0,"visible":null,"selected":false,"actions":[{"id":"close","label":"Close"},{"label":"no id"},{"id":"rm","label":"Remove","icon":"trash","destructive":true}]}"#
        let row = try JSONDecoder().decode(CraftRow.self, from: Data(json.utf8))
        #expect(row.actions == [CraftRowAction(id: "close", label: "Close"), CraftRowAction(id: "rm", label: "Remove", icon: "trash", destructive: true)])
    }
}
