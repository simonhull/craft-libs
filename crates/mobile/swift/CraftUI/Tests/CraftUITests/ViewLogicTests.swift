import Foundation
import SwiftUI
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

    /// A log slider: position t in 0...1 is `min·(max/min)^t`, so the middle of 1...5000 is √5000.
    @Test func aLogSliderSpreadsTheRangeByRatio() {
        let range = 1.0...5000.0
        #expect(CraftNumberView.value(atPosition: 0, in: range, scale: .log) == 1)
        #expect(abs(CraftNumberView.value(atPosition: 1, in: range, scale: .log) - 5000) < 1e-9)
        #expect(abs(CraftNumberView.value(atPosition: 0.5, in: range, scale: .log) - 5000.0.squareRoot()) < 1e-9)
        #expect(CraftNumberView.position(of: 1, in: range, scale: .log) == 0)
        #expect(abs(CraftNumberView.position(of: 5000, in: range, scale: .log) - 1) < 1e-12)
        #expect(abs(CraftNumberView.position(of: 50, in: 1...10000, scale: .log) - log10(50) / 4) < 1e-12)
    }

    @Test func aLogPositionRoundTrips() {
        let range = 0.5...5000.0
        for value in [0.5, 1, 3.7, 24, 999, 5000] {
            let back = CraftNumberView.value(atPosition: CraftNumberView.position(of: value, in: range, scale: .log), in: range, scale: .log)
            #expect(abs(back - value) <= value * 1e-12, "\(value) came back as \(back)")
        }
    }

    @Test func aLogValueSnapsToTheStepAfterMapping() {
        let range = 1.0...5000.0
        let middle = CraftNumberView.value(atPosition: 0.5, in: range, scale: .log)
        #expect(CraftNumberView.snap(middle, step: 1, in: range) == 71, "√5000 ≈ 70.7")
        let low = CraftNumberView.value(atPosition: 0.1, in: range, scale: .log)
        #expect(CraftNumberView.snap(low, step: 1, in: range) == 2, "5000^0.1 ≈ 2.34")
    }

    /// Positions outside 0...1 stay at the ends; a range a log scale can't spread is linear.
    @Test func aLogSliderStaysInItsRange() {
        #expect(CraftNumberView.value(atPosition: -0.2, in: 1...100, scale: .log) == 1)
        #expect(abs(CraftNumberView.value(atPosition: 1.5, in: 1...100, scale: .log) - 100) < 1e-9)
        #expect(CraftNumberView.position(of: 0.5, in: 1...100, scale: .log) == 0, "below min")
        #expect(CraftNumberView.position(of: 4, in: 4...4, scale: .log) == 0, "an empty range")
        #expect(CraftNumberView.position(of: 5, in: 0...10, scale: .log) == 0.5, "min 0: linear")
        #expect(CraftNumberView.value(atPosition: 0.5, in: -10...10, scale: .log) == 0, "min below 0: linear")
    }

    @Test func aLinearSliderIsProportional() {
        #expect(CraftNumberView.position(of: 25, in: 0...100, scale: .linear) == 0.25)
        #expect(CraftNumberView.value(atPosition: 0.25, in: 0...100, scale: .linear) == 25)
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

    /// A, then group G with children c1 and c2.
    static let grouped = [
        CraftRow(id: 30, title: "A"), CraftRow(id: 20, title: "G"),
        CraftRow(id: 21, title: "c1", depth: 1), CraftRow(id: 22, title: "c2", depth: 1),
    ]

    @Test func aRowCantBeDroppedIntoItsOwnSubtree() {
        #expect(CraftItemListView.moveEdit(Self.grouped, from: [1], to: 3) == nil, "between its children")
        #expect(CraftItemListView.moveEdit(Self.grouped, from: [1], to: 4) == nil, "below its last child")
        #expect(CraftItemListView.moveEdit(Self.grouped, from: [1], to: 0) == .move(row: 20, target: 30, position: .above))
        let nested = [
            CraftRow(id: 40, title: "O"), CraftRow(id: 41, title: "G", depth: 1), CraftRow(id: 42, title: "c", depth: 2),
            CraftRow(id: 43, title: "X"),
        ]
        #expect(CraftItemListView.moveEdit(nested, from: [1], to: 3) == nil, "below its own child, still inside O")
        #expect(CraftItemListView.moveEdit(nested, from: [2], to: 1) == .move(row: 42, target: 41, position: .above), "a child out above its group")
    }

    /// Past the last row is the bottom of the top level: below the outermost group the list ends in,
    /// not inside it after its last child.
    @Test func aDropPastTheEndLandsBelowTheOutermostGroup() {
        #expect(CraftItemListView.moveEdit(Self.grouped, from: [0], to: 4) == .move(row: 30, target: 20, position: .below))
        #expect(CraftItemListView.moveEdit(Self.grouped, from: [2], to: 4) == .move(row: 21, target: 20, position: .below), "a child out of its group")
        let nested = [
            CraftRow(id: 40, title: "O"), CraftRow(id: 41, title: "G", depth: 1), CraftRow(id: 42, title: "c", depth: 2),
            CraftRow(id: 44, title: "d", depth: 1),
        ]
        #expect(CraftItemListView.moveEdit(nested, from: [2], to: 4) == .move(row: 42, target: 40, position: .below), "out of both groups")
        #expect(CraftItemListView.moveEdit(nested, from: [3], to: 4) == nil, "the last row dropped where it was stays in its group")
        #expect(CraftItemListView.moveEdit(nested, from: [0], to: 4) == nil, "the outermost group is already last")
    }

    /// A plain tap selects one row; in multi-select every tap adds or removes one; with a keyboard,
    /// Command-tap adds or removes and Shift-tap selects a range, as the desktop's Layers panel does.
    @Test func aTapSelectsByModeAndModifiers() {
        #expect(CraftItemListView.selectMode(multiSelecting: false, modifiers: []) == .replace)
        #expect(CraftItemListView.selectMode(multiSelecting: true, modifiers: []) == .toggle)
        #expect(CraftItemListView.selectMode(multiSelecting: false, modifiers: .command) == .toggle)
        #expect(CraftItemListView.selectMode(multiSelecting: false, modifiers: .shift) == .range)
        #expect(CraftItemListView.selectMode(multiSelecting: true, modifiers: .shift) == .range)
        #expect(CraftItemListView.selectMode(multiSelecting: false, modifiers: [.command, .shift]) == .toggle, "Command wins, as on the desktop")
        #expect(CraftItemListView.selectMode(multiSelecting: false, modifiers: .option) == .replace)
    }

    /// Only destructive actions are swipes, in the app's order; every action is in the context menu.
    @Test func destructiveRowActionsAreSwipes() {
        let close = CraftRowAction(id: "close", label: "Close", icon: "xmark", destructive: true)
        let dup = CraftRowAction(id: "duplicate", label: "Duplicate")
        let delete = CraftRowAction(id: "delete", label: "Delete", destructive: true)
        let row = CraftRow(id: 1, title: "a", actions: [close, dup, delete])
        #expect(CraftItemListView.swipeActions(row) == [close, delete])
        #expect(CraftItemListView.swipeActions(CraftRow(id: 2, title: "b")).isEmpty)
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
