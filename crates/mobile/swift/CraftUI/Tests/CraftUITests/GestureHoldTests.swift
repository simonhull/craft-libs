import Testing
@testable import CraftUI

@Suite struct GestureHoldTests {
    @Test func aDragShowsItsOwnValueUntilCommitThenTheApps() throws {
        var hold = GestureHold()
        let begin = hold.begin(control: "opacity", from: 0.8)
        #expect(begin.phase == .begin && begin.value == 0.8)
        let changed = hold.change(control: "opacity", to: 0.4)
        let change = try #require(changed)
        #expect(change.gesture == begin.gesture && change.phase == .change)
        #expect(hold.shown(control: "opacity", app: 0.8) == 0.4, "the app hasn't caught up: show the finger's value")
        let committed = hold.commit(control: "opacity")
        let commit = try #require(committed)
        #expect(commit.value == 0.4 && commit.phase == .commit && commit.gesture == begin.gesture)
        #expect(hold.shown(control: "opacity", app: 0.41) == 0.41, "after commit the app's value wins")
    }

    @Test func cancelSendsTheValueFromBeforeTheDrag() throws {
        var hold = GestureHold()
        _ = hold.begin(control: "size", from: 10)
        _ = hold.change(control: "size", to: 50)
        let cancelled = hold.cancel(control: "size")
        let cancel = try #require(cancelled)
        #expect(cancel.value == 10 && cancel.phase == .cancel)
        #expect(hold.shown(control: "size", app: 12) == 12)
    }

    @Test func withoutADragThereIsNothingToChangeOrEnd() {
        var hold = GestureHold()
        #expect(hold.change(control: "x", to: 1) == nil)
        #expect(hold.commit(control: "x") == nil)
        #expect(hold.cancel(control: "x") == nil)
        #expect(!hold.dragging(control: "x"))
    }

    @Test func dragsOnDifferentControlsAreIndependent() {
        var hold = GestureHold()
        let a = hold.begin(control: "a", from: 0)
        let b = hold.begin(control: "b", from: 0)
        #expect(a.gesture != b.gesture)
        _ = hold.change(control: "a", to: 1)
        #expect(hold.shown(control: "b", app: 5) == 0)
        let committed = hold.commit(control: "a")
        #expect(committed?.value == 1)
        #expect(hold.dragging(control: "b"))
    }

    @Test func gesturesGetNewIds() {
        var hold = GestureHold()
        let a = hold.begin(control: "x", from: 0).gesture
        _ = hold.commit(control: "x")
        #expect(hold.begin(control: "x", from: 0).gesture != a)
        #expect(hold.oneShot() != hold.oneShot())
    }
}
