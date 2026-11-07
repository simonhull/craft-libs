import Testing
@testable import CraftUI

@Suite struct GestureHoldTests {
    @Test func aDragShowsItsOwnValueUntilCommitThenTheApps() throws {
        var hold = GestureHold()
        let begin = hold.begin(from: 0.8)
        #expect(begin.phase == .begin && begin.value == 0.8)
        let changed = hold.change(to: 0.4)
        let change = try #require(changed)
        #expect(change.gesture == begin.gesture && change.phase == .change)
        #expect(hold.shown(app: 0.8) == 0.4, "the app hasn't caught up: show the finger's value")
        let committed = hold.commit()
        let commit = try #require(committed)
        #expect(commit.value == 0.4 && commit.phase == .commit && commit.gesture == begin.gesture)
        #expect(hold.shown(app: 0.8) == 0.4, "committed, the app not yet described: still the finger's value")
        hold.described()
        #expect(hold.shown(app: 0.41) == 0.41, "described since: the app's value wins")
    }

    /// The app clamps the committed value, or refuses it: its next description is the truth.
    @Test func theNextDescriptionAfterACommitWinsWhateverItSays() {
        var hold = GestureHold()
        _ = hold.begin(from: 0.8)
        _ = hold.change(to: 1.2)
        _ = hold.commit()
        hold.described()
        #expect(hold.shown(app: 1.0) == 1.0, "clamped")
        _ = hold.begin(from: 0.8)
        _ = hold.change(to: 0.3)
        _ = hold.commit()
        #expect(hold.shown(app: 0.8) == 0.3)
        hold.described()
        #expect(hold.shown(app: 0.8) == 0.8, "refused: back to the app's value")
    }

    @Test func aNewDragReplacesTheSettlingValue() {
        var hold = GestureHold()
        _ = hold.begin(from: 0.8)
        _ = hold.change(to: 0.3)
        _ = hold.commit()
        _ = hold.begin(from: 0.5)
        #expect(hold.shown(app: 0.5) == 0.5)
        _ = hold.cancel()
        hold.described()
        #expect(hold.shown(app: 0.6) == 0.6)
    }

    @Test func aDescriptionWithoutADragChangesNothing() {
        var hold = GestureHold()
        hold.described()
        #expect(hold.shown(app: 0.7) == 0.7)
    }

    @Test func cancelSendsTheValueFromBeforeTheDrag() throws {
        var hold = GestureHold()
        let begin = hold.begin(from: 10)
        _ = hold.change(to: 50)
        let cancelled = hold.cancel()
        let cancel = try #require(cancelled)
        #expect(cancel.value == 10 && cancel.phase == .cancel && cancel.gesture == begin.gesture)
        #expect(!hold.isDragging && hold.shown(app: 50) == 10, "the value put back, before the app says so")
        hold.described()
        #expect(hold.shown(app: 12) == 12)
    }

    /// What a number view does when it goes away mid-drag (`onDisappear`): cancel once, then nothing.
    @Test func aDragOrphanedByItsViewCancelsOnce() {
        var hold = GestureHold()
        _ = hold.begin(from: 3)
        _ = hold.change(to: 7)
        #expect(hold.cancel()?.value == 3)
        #expect(hold.cancel() == nil, "a second disappearance sends nothing")
    }

    @Test func withoutADragThereIsNothingToChangeOrEnd() {
        var hold = GestureHold()
        #expect(hold.change(to: 1) == nil)
        #expect(hold.commit() == nil)
        #expect(hold.cancel() == nil)
        #expect(!hold.isDragging)
    }

    @Test func gesturesGetNewIds() {
        var hold = GestureHold()
        let a = hold.begin(from: 0).gesture
        _ = hold.commit()
        #expect(hold.begin(from: 0).gesture != a)
        #expect(GestureID.next() != GestureID.next())
    }

    /// Views are rebuilt (a popover reopens, a panel is re-described): their fresh holds must never
    /// reuse a gesture number, or the app would merge two drags into one undo step.
    @Test func freshHoldsNeverShareAnId() {
        var first = GestureHold()
        var second = GestureHold()
        #expect(first.begin(from: 0).gesture != second.begin(from: 0).gesture)
        let oneShots = (0..<1000).map { _ in GestureID.next() }
        #expect(Set(oneShots).count == oneShots.count)
    }
}
