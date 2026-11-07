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

    @Test func numbersFormatByUnit() {
        #expect(CraftNumberView.format(0.8, .percent) == "80 %")
        #expect(CraftNumberView.format(0.8, .percent, withUnit: false) == "80")
        #expect(CraftNumberView.format(24, .pixels) == "24 px")
        #expect(CraftNumberView.format(45.4, .degrees) == "45°")
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
}
