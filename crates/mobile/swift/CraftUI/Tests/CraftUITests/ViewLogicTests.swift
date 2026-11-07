import Foundation
import Testing
@testable import CraftUI

@Suite struct ViewLogicTests {
    @Test func numbersSnapToMultiplesOfTheStepWithinTheRange() {
        #expect(CraftNumberView.snap(23.4, step: 5, in: 1...500) == 25)
        #expect(CraftNumberView.snap(0.2, step: 5, in: 1...500) == 1, "snapped below min, clamped")
        #expect(CraftNumberView.snap(0.37, step: nil, in: 0...1) == 0.37)
        #expect(CraftNumberView.snap(7, step: 0, in: 0...10) == 7, "a non-positive step is ignored")
        #expect(CraftNumberView.snap(1.5, step: nil, in: 0...1) == 1)
    }

    static let posix = Locale(identifier: "en_US_POSIX")

    @Test func numbersFormatByUnit() {
        #expect(CraftNumberView.format(0.8, .percent, locale: Self.posix) == "80 %")
        #expect(CraftNumberView.format(0.8, .percent, withUnit: false, locale: Self.posix) == "80")
        #expect(CraftNumberView.format(24, .pixels, locale: Self.posix) == "24 px")
        #expect(CraftNumberView.format(45.4, .degrees, locale: Self.posix) == "45°")
        #expect(CraftNumberView.format(1234.5, .none, locale: Locale(identifier: "de_DE")) == "1234,5", "never grouped: it fills the typing field")
    }

    @Test func aTypedValueRoundTrips() {
        let shown = CraftNumberView.format(1234, .pixels, withUnit: false, locale: Self.posix)
        #expect(shown == "1234")
        #expect(CraftNumberView.parse(shown, unit: .pixels, locale: Self.posix) == 1234)
        #expect(CraftNumberView.parse("80", unit: .percent, locale: Self.posix) == 0.8)
    }

    @Test func typedValuesFollowTheUsersLocale() {
        #expect(CraftNumberView.parse("1,234", unit: .none, locale: Locale(identifier: "en_US")) == 1234, "a grouping comma, not a decimal one")
        #expect(CraftNumberView.parse("1.234,5", unit: .none, locale: Locale(identifier: "de_DE")) == 1234.5)
        #expect(CraftNumberView.parse("12.5", unit: .none, locale: Self.posix) == 12.5)
    }

    static let de = Locale(identifier: "de_DE")
    static let en = Locale(identifier: "en_US")

    @Test func typedValuesParseStrictlyInTheUsersLocale() {
        #expect(CraftNumberView.parse("1,5", unit: .none, locale: Self.de) == 1.5)
        #expect(CraftNumberView.parse("1.234,5", unit: .none, locale: Self.de) == 1234.5)
        #expect(CraftNumberView.parse("1,234", unit: .none, locale: Self.en) == 1234)
        #expect(CraftNumberView.parse("−3,5", unit: .none, locale: Locale(identifier: "sv_SE")) == -3.5, "the locale's own minus sign")
    }

    @Test func aPlainDecimalPointStillWorksWhereTheLocaleGroupsWithIt() {
        #expect(CraftNumberView.parse("1.5", unit: .none, locale: Self.de) == 1.5)
        #expect(CraftNumberView.parse("0.25", unit: .none, locale: Self.de) == 0.25, "not 25")
    }

    @Test func anythingElseIsRejected() {
        #expect(CraftNumberView.parse("0,5", unit: .none, locale: Self.en) == nil, "not 5, not 0.5: ambiguous")
        #expect(CraftNumberView.parse("50abc", unit: .none, locale: Self.en) == nil)
        #expect(CraftNumberView.parse("1,5", unit: .none, locale: Self.en) == nil, "not 1")
    }

    @Test func typedUnitsAreIgnored() {
        #expect(CraftNumberView.parse("80 %", unit: .percent, locale: Self.posix) == 0.8)
        #expect(CraftNumberView.parse("24px", unit: .pixels, locale: Self.posix) == 24)
        #expect(CraftNumberView.parse(" 45° ", unit: .degrees, locale: Self.posix) == 45)
        #expect(CraftNumberView.parse("big", unit: .none, locale: Self.posix) == nil)
        #expect(CraftNumberView.parse(" ", unit: .none, locale: Self.posix) == nil)
    }

    static let rows = [CraftRow(id: 30, title: "A"), CraftRow(id: 20, title: "B"), CraftRow(id: 10, title: "C")]

    @Test func aDropBecomesAboveOrBelowARow() {
        #expect(CraftItemListView.moveEdit(Self.rows, from: [2], to: 0) == .move(row: 10, target: 30, position: .above))
        #expect(CraftItemListView.moveEdit(Self.rows, from: [0], to: 2) == .move(row: 30, target: 10, position: .above))
        #expect(CraftItemListView.moveEdit(Self.rows, from: [0], to: 3) == .move(row: 30, target: 10, position: .below))
    }

    @Test func aDropWhereTheRowWasSendsNothing() {
        #expect(CraftItemListView.moveEdit(Self.rows, from: [1], to: 1) == nil)
        #expect(CraftItemListView.moveEdit(Self.rows, from: [1], to: 2) == nil)
        #expect(CraftItemListView.moveEdit(Self.rows, from: [2], to: 3) == nil)
        #expect(CraftItemListView.moveEdit(Self.rows, from: [7], to: 0) == nil)
    }

    @Test func nodesWithTheSameIdStillGetTheirOwnViews() {
        let nodes: [CraftNode] = [
            .toggle(id: "a", label: "A", value: true, enabled: true), .unknown(type: "hologram"),
            .toggle(id: "a", label: "A again", value: false, enabled: true), .unknown(type: "hologram"), .malformed(type: "number"),
        ]
        let keys = CraftNodeView.keyed(nodes).map(\.key)
        #expect(keys == ["a", "unknown-hologram", "a#1", "unknown-hologram#1", "malformed-number"])
        #expect(Set(keys).count == nodes.count)
    }
}
