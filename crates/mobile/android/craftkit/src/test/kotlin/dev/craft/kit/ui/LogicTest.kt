package dev.craft.kit.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class GestureHoldTest {
    @Test
    fun aDragShowsItsOwnValueUntilCommitThenTheApps() {
        val hold = GestureHold()
        val begin = hold.begin(0.8)
        assertEquals(GestureHold.Step(begin.gesture, Phase.Begin, 0.8), begin)
        assertEquals(GestureHold.Step(begin.gesture, Phase.Change, 0.4), hold.change(0.4))
        assertEquals("the app hasn't caught up: the finger's value", 0.4, hold.shown(0.8), 0.0)
        assertEquals(GestureHold.Step(begin.gesture, Phase.Commit, 0.4), hold.commit())
        assertEquals("committed, not yet described: still the finger's value", 0.4, hold.shown(0.8), 0.0)
        hold.described()
        assertEquals("described since: the app's value wins, clamped or refused", 0.41, hold.shown(0.41), 0.0)
    }

    @Test
    fun cancelSendsTheValueFromBeforeTheDragAndShowsIt() {
        val hold = GestureHold()
        val begin = hold.begin(10.0)
        hold.change(50.0)
        assertEquals(GestureHold.Step(begin.gesture, Phase.Cancel, 10.0), hold.cancel())
        assertEquals(10.0, hold.shown(50.0), 0.0)
        assertFalse(hold.isDragging)
    }

    @Test
    fun withoutADragNothingIsSentAndTheAppsValueShows() {
        val hold = GestureHold()
        assertNull(hold.change(1.0))
        assertNull(hold.commit())
        assertNull(hold.cancel())
        hold.described()
        assertEquals(0.7, hold.shown(0.7), 0.0)
    }

    /** A slider's moves, as its one callback reports them: begin once, a change per new value, then commit. */
    @Test
    fun aSliderDragIsBeginChangesAndCommitUnderOneGesture() {
        val hold = GestureHold()
        val first = hold.slide(30.0, app = 24.0)
        assertEquals(listOf(Phase.Begin, Phase.Change), first.map { it.phase })
        assertEquals(listOf(24.0, 30.0), first.map { it.value })
        val gesture = first.first().gesture
        assertEquals("the same snapped value again: nothing", emptyList<GestureHold.Step>(), hold.slide(30.0, app = 24.0))
        assertEquals(listOf(GestureHold.Step(gesture, Phase.Change, 40.0)), hold.slide(40.0, app = 24.0))
        assertEquals(GestureHold.Step(gesture, Phase.Commit, 40.0), hold.commit())
        assertNull("finished twice (a key step reports it again): nothing more", hold.commit())
        val next = hold.slide(41.0, app = 40.0)
        assertNotEquals("the next drag is another undo step", gesture, next.first().gesture)
    }

    /** A tap on the value already shown starts and ends a drag that changes nothing. */
    @Test
    fun aSliderTapOnTheShownValueSendsBeginAndCommitOnly() {
        val hold = GestureHold()
        val steps = hold.slide(24.0, app = 24.0)
        assertEquals(listOf(Phase.Begin), steps.map { it.phase })
        assertEquals(GestureHold.Step(steps.single().gesture, Phase.Commit, 24.0), hold.commit())
    }

    /** One drag is one gesture (one undo step); every drag gets a number no other gesture had. */
    @Test
    fun eachDragHasItsOwnGesture() {
        val hold = GestureHold()
        val first = hold.begin(0.0).gesture
        assertEquals(first, hold.change(0.5)?.gesture)
        assertEquals(first, hold.commit()?.gesture)
        val second = hold.begin(0.5).gesture
        assertNotEquals(first, second)
        assertNotEquals(second, Edit.commit("p", "c", EditValue.Toggle(true)).gesture)
    }
}

class ScrubTest {
    @Test
    fun aScrubSendsBeginChangesOnNewFramesAndCommit() {
        val scrub = Scrub()
        val begin = scrub.begin(frame = 4, app = 11)
        assertEquals(Phase.Begin, begin.phase)
        assertNull("the same frame again sends nothing", scrub.move(4))
        assertEquals(Scrub.Step(begin.gesture, Phase.Change, 5), scrub.move(5))
        assertEquals(5L, scrub.shown(app = 11))
        assertEquals(Scrub.Step(begin.gesture, Phase.Commit, 6), scrub.commit(6))
        assertEquals("until the app says", 6L, scrub.shown(app = 11))
        scrub.settled()
        assertEquals(7L, scrub.shown(app = 7))
    }

    @Test
    fun aCancelledScrubPutsThePlayheadBackAndShowsTheAppsFrame() {
        val scrub = Scrub()
        val begin = scrub.begin(frame = 20, app = 11)
        assertEquals(Scrub.Step(begin.gesture, Phase.Cancel, 11), scrub.cancel())
        assertEquals(12L, scrub.shown(app = 12))
        assertNull(scrub.cancel())
    }

    @Test
    fun xMapsToAFrameOnTheTrack() {
        assertEquals(0L, Scrub.frameAt(0.0, 300.0, 30))
        assertEquals(0L, Scrub.frameAt(9.9, 300.0, 30))
        assertEquals(1L, Scrub.frameAt(10.0, 300.0, 30))
        assertEquals(15L, Scrub.frameAt(155.0, 300.0, 30))
        assertEquals(29L, Scrub.frameAt(300.0, 300.0, 30))
        assertEquals(0L, Scrub.frameAt(-40.0, 300.0, 30))
        assertEquals(29L, Scrub.frameAt(9000.0, 300.0, 30))
        assertEquals(0L, Scrub.frameAt(Double.NaN, 300.0, 30))
        assertEquals(0L, Scrub.frameAt(50.0, 0.0, 30))
        assertEquals(Long.MAX_VALUE - 1, Scrub.frameAt(Double.POSITIVE_INFINITY, 300.0, Long.MAX_VALUE))
        assertEquals(5.0, Scrub.xOfFrame(0, 300.0, 30), 1e-9)
        assertEquals(300.0, Scrub.xOfEdge(30, 300.0, 30), 1e-9)
    }

    @Test
    fun crossingTheWorkAreasEdges() {
        val range = 10L until 20
        assertTrue(Scrub.crossesEdge(9, 10, range))
        assertTrue(Scrub.crossesEdge(19, 20, range))
        assertFalse(Scrub.crossesEdge(11, 18, range))
        assertFalse(Scrub.crossesEdge(9, 10, null))
    }
}

class TransportTest {
    @Test
    fun framesCountFromOneOfTheDuration() {
        assertEquals("12 / 30", Transport.label(11, 30, 24.0, TimeFormat.Frames))
        val t = Transport.of("t", 0, 120, 24.0)!!
        assertEquals("120 / 120", t.widestLabel)
        assertEquals("Frame 5 of 120", t.spokenLabel(4))
    }

    @Test
    fun timecode() {
        assertEquals("00:00:00:11", Transport.timecode(11, 24.0))
        assertEquals("01:01:01:05", Transport.timecode(24L * 3600 + 24 * 61 + 5, 24.0))
        assertEquals("00:01:00:00", Transport.timecode(25L * 60, 25.0))
        assertEquals("25:00:00:00", Transport.timecode(24L * 3600 * 25, 24.0))
        for (rate in listOf(29.97, 30000.0 / 1001)) {
            assertEquals("00:01:00;02", Transport.timecode(1800, rate))
            assertEquals("00:10:00;00", Transport.timecode(17982, rate))
            assertEquals("01:00:00;00", Transport.timecode(107_892, rate))
        }
        assertEquals("00:01:00;04", Transport.timecode(3600, 59.94))
        assertEquals("00:00:01:00", Transport.timecode(24, 23.976))
        assertEquals("00:00:01:00", Transport.timecode(24, 24.000_000_1))
        assertEquals("00:00:03:00", Transport.timecode(3, 0.5))
    }

    @Test
    fun theConstructorKeepsItValid() {
        assertNull(Transport.of("t", 0, 0, 24.0))
        assertNull(Transport.of("t", 0, 1, Double.NaN))
        assertNull(Transport.of("t", 0, 1, Double.POSITIVE_INFINITY))
        val t = Transport.of("t", 40, 30, 24.0, range = 25L until 90)!!
        assertEquals(29L, t.position)
        assertEquals(25L until 30, t.range)
        assertEquals(29L, t.with(position = 100).position)
        assertTrue(t.with(playing = true).playing)
    }

    /** A live position shows until the next description, which carries the positions itself. */
    @Test
    fun livePositionsShowUntilTheNextDescription() {
        val ui = CraftUi {}
        val t = Transport.of("transport", 3, 30, 24.0)!!
        assertEquals(3L, t.appPosition("timeline", ui.live))
        ui.receive(CraftUi.Request.Live(listOf(LiveValue("timeline", "transport", 12), LiveValue("other", "transport", 1))))
        assertEquals(12L, t.appPosition("timeline", ui.live))
        ui.receive(CraftUi.Request.Described(Panels()))
        assertEquals(3L, t.appPosition("timeline", ui.live))
        assertEquals(1L, ui.descriptions)
    }
}

class RailTest {
    private val palette = ToolPalette(
        "palette",
        listOf(
            ToolSlot(listOf(Tool("move", "Move", ToolIcon("arrow.up.and.down.and.arrow.left.and.right", "V"), "V"))),
            ToolSlot(listOf(Tool("brush", "Brush", ToolIcon("paintbrush.pointed", "B"), "B"), Tool("pencil", "Pencil", ToolIcon("pencil", "N"), "N"))),
        ),
        selected = "brush",
        options = "brush",
    )

    @Test
    fun aSlotShowsTheSelectedToolElseItsFirst() {
        assertEquals("pencil", palette.slots[1].shown("pencil")?.id)
        assertEquals("brush", palette.slots[1].shown("move")?.id)
        assertEquals(1, palette.slotIndex("pencil"))
        assertNull(palette.slotIndex("lasso"))
    }

    @Test
    fun optionsAreThePanelElseTheFallbackCommand() {
        assertEquals(RailOptions.Panel("brush"), palette.optionsRoute)
        assertEquals(RailOptions.Command("x"), palette.copy(options = null, fallbackOptions = "x").optionsRoute)
        assertNull(palette.withoutOptions.optionsRoute)
        assertNull("a tool the app hasn't selected yet waits", palette.optionsNow("pencil"))
        assertEquals(RailOptions.Panel("pencil"), palette.selecting("pencil").copy(options = "pencil").optionsNow("pencil"))
    }

    @Test
    fun aDoubleTapOpensOptionsAndATapOnTheSelectedToolSelectsNothing() {
        val taps = RailTaps()
        assertEquals(RailTaps.Outcome.Nothing, taps.tap("brush", "brush", 0))
        assertEquals(RailTaps.Outcome.Options, taps.tap("brush", "brush", 200))
        assertEquals(RailTaps.Outcome.Select, taps.tap("pencil", "brush", 1_000))
        assertEquals("too slow for a double-tap", RailTaps.Outcome.Select, taps.tap("pencil", "brush", 2_000))
    }

    @Test
    fun anIconIsItsSymbolElseItsLetterElseTheLabels() {
        assertEquals(ToolIcon.Shown.Symbol("pencil"), ToolIcon("pencil", "N").shown("Pencil"))
        assertEquals(ToolIcon.Shown.Letter("N"), ToolIcon("no.such.symbol", "N").shown("Pencil"))
        assertEquals(ToolIcon.Shown.Letter("S"), ToolIcon(null, null).shown("smudge"))
        assertEquals(ToolIcon.Shown.Letter("?"), ToolIcon(null, "").shown(""))
    }
}

class NumberMathTest {
    @Test
    fun aSliderTicksAtItsEndsAndThroughFewStepsOnly() {
        val percent = 0.0..100.0
        assertEquals(NumberMath.Tick.Edge, NumberMath.tick(99.0, 100.0, step = 1.0, range = percent))
        assertEquals(NumberMath.Tick.Edge, NumberMath.tick(3.0, 0.0, step = null, range = percent))
        assertEquals("100 steps are too many to feel one by one", NumberMath.Tick.None, NumberMath.tick(40.0, 41.0, step = 1.0, range = percent))
        assertEquals(NumberMath.Tick.Detent, NumberMath.tick(40.0, 50.0, step = 10.0, range = percent))
        assertEquals("continuous: only the ends", NumberMath.Tick.None, NumberMath.tick(40.0, 41.5, step = null, range = percent))
        assertEquals("no move, no tick", NumberMath.Tick.None, NumberMath.tick(100.0, 100.0, step = 1.0, range = percent))
    }

    private val log = 1.0..5000.0

    @Test
    fun aLogScaleSpreadsTheRangeByRatio() {
        assertEquals(0.0, NumberMath.position(1.0, log, Scale.Log), 1e-12)
        assertEquals(1.0, NumberMath.position(5000.0, log, Scale.Log), 1e-12)
        assertEquals(0.5, NumberMath.position(kotlin.math.sqrt(5000.0), log, Scale.Log), 1e-12)
        for (t in listOf(0.0, 0.25, 0.5, 0.9, 1.0)) {
            assertEquals(t, NumberMath.position(NumberMath.valueAt(t, log, Scale.Log), log, Scale.Log), 1e-9)
        }
        assertEquals("a log scale needs min above zero: linear", 0.5, NumberMath.position(0.0, -1.0..1.0, Scale.Log), 1e-12)
        assertEquals(0.0, NumberMath.position(3.0, 2.0..2.0, Scale.Linear), 0.0)
        assertEquals(1.0, NumberMath.valueAt(Double.NaN, log, Scale.Log), 0.0)
    }

    @Test
    fun aStepSnapsAndTheRangeHolds() {
        assertEquals(120.0, NumberMath.snap(119.6, 1.0, log), 0.0)
        assertEquals(5000.0, NumberMath.snap(9000.0, 1.0, log), 0.0)
        assertEquals(0.25, NumberMath.snap(0.3, 0.25, 0.0..1.0), 0.0)
        assertEquals(0.33, NumberMath.snap(0.33, null, 0.0..1.0), 0.0)
    }

    @Test
    fun valuesShowAndParseInTheLocale() {
        val us = Locale.US
        val de = Locale.GERMANY
        assertEquals("80 %", NumberMath.format(0.8, NumberUnit.Percent, locale = us))
        assertEquals("24 px", NumberMath.format(24.0, NumberUnit.Pixels, locale = us))
        assertEquals("1234,5 px", NumberMath.format(1234.5, NumberUnit.Pixels, locale = de))
        assertEquals("45°", NumberMath.format(45.0, NumberUnit.Degrees, locale = us))
        assertEquals("0.33", NumberMath.format(1.0 / 3, NumberUnit.None, locale = us))
        assertEquals("0", NumberMath.format(-0.0, NumberUnit.None, locale = us))
        assertEquals(0.5, NumberMath.parse("50 %", NumberUnit.Percent, us)!!, 1e-12)
        assertEquals(1234.5, NumberMath.parse("1234,5", NumberUnit.Pixels, de)!!, 0.0)
        assertEquals("a plain number reads anywhere", 1234.5, NumberMath.parse("1234.5", NumberUnit.Pixels, de)!!, 0.0)
        assertNull(NumberMath.parse("50abc", NumberUnit.None, us))
        assertNull("a comma only groups here", NumberMath.parse("0,5", NumberUnit.None, us))
        assertNull(NumberMath.parse(" ", NumberUnit.None, us))
    }
}

class ItemListTest {
    private fun rows(vararg depths: Int) = depths.mapIndexed { i, depth -> Row(id = (i + 1).toLong(), title = "$i", depth = depth) }

    @Test
    fun aDropLandsAboveTheRowItFallsBefore() {
        val flat = rows(0, 0, 0)
        assertEquals(EditValue.Move(3, 1, Position.Above), ItemLists.moveEdit(flat, from = 2, destination = 0))
        assertEquals(EditValue.Move(1, 3, Position.Above), ItemLists.moveEdit(flat, from = 0, destination = 2))
        assertEquals("past the end: below the last top-level row", EditValue.Move(1, 3, Position.Below), ItemLists.moveEdit(flat, from = 0, destination = 3))
        assertNull("where it was", ItemLists.moveEdit(flat, from = 1, destination = 1))
        assertNull("where it was", ItemLists.moveEdit(flat, from = 1, destination = 2))
        assertNull(ItemLists.moveEdit(flat, from = 7, destination = 0))
    }

    @Test
    fun aGroupCantGoInsideItself() {
        // A group (0) holding 1 and 2, then a top-level row 3.
        val nested = rows(0, 1, 1, 0)
        assertNull(ItemLists.moveEdit(nested, from = 0, destination = 2))
        assertNull(ItemLists.moveEdit(nested, from = 0, destination = 3))
        assertEquals(EditValue.Move(1, 4, Position.Below), ItemLists.moveEdit(nested, from = 0, destination = 4))
        val endsInAGroup = listOf(Row(4, "row"), Row(1, "group"), Row(2, "child", depth = 1))
        assertEquals("past the end: below the group, not inside it", EditValue.Move(4, 1, Position.Below), ItemLists.moveEdit(endsInAGroup, 0, 3))
    }

    @Test
    fun modifiersChooseHowATapSelects() {
        assertEquals(SelectMode.Replace, ItemLists.selectMode(multiSelecting = false))
        assertEquals(SelectMode.Toggle, ItemLists.selectMode(multiSelecting = true))
        assertEquals(SelectMode.Range, ItemLists.selectMode(multiSelecting = false, shift = true))
        assertEquals("Ctrl wins over Shift", SelectMode.Toggle, ItemLists.selectMode(multiSelecting = false, command = true, shift = true))
    }

    @Test
    fun onlyDestructiveActionsSwipe() {
        val row = Row(1, "a", actions = listOf(ItemAction("dup", "Duplicate"), ItemAction("rm", "Delete", destructive = true)))
        assertEquals(listOf("rm"), ItemLists.swipeActions(row).map { it.id })
    }
}

class StatusTest {
    @Test
    fun aDismissedMessageStaysDismissedAndANewOneShows() {
        val saved = Status.Message("Saved")
        val failed = Status.Message("Couldn't save", Tone.Error)
        assertEquals(saved, Status.shown(saved, dismissed = null))
        assertNull(Status.shown(saved, dismissed = saved.identity))
        assertEquals(failed, Status.shown(failed, dismissed = saved.identity))
        // Numbered: new text under the same id (a countdown) is the same message.
        val counting = Status.Message("Retrying in 3 s", id = 9)
        assertNull(Status.shown(counting.copy(text = "Retrying in 2 s"), dismissed = counting.identity))
        assertEquals(6_000L, failed.durationMillis)
    }
}

class CraftUiTest {
    @Test
    fun theShellSaysWhatItDrawsThenWhatIsOnScreen() {
        val sent = mutableListOf<String>()
        val ui = CraftUi { sent += it }
        ui.features = setOf(Feature.Rail, Feature.Panels)
        ui.showing(setOf("tools", "layers"))
        ui.started()
        assertEquals(
            listOf(
                """{"action":"open_panels","open":["layers","tools"]}""",
                """{"action":"shell","features":["panels","rail"]}""",
                """{"action":"open_panels","open":["layers","tools"]}""",
            ),
            sent,
        )
        assertFalse(ui.describedSinceShowing)
        ui.receive(CraftUi.Request.Described(Panels()))
        assertTrue(ui.describedSinceShowing)
    }

    /** What the app sends is shown, never answered: a description, the menus, the status or a live position sends nothing back. */
    @Test
    fun theAppsWordIsNeverEchoed() {
        val sent = mutableListOf<String>()
        val ui = CraftUi { sent += it }
        val panel = Panel("brush", "Brush", PanelRole.Tool, listOf(Node.Number("size", "Size", 24.0, 1.0, 5000.0, 1.0, NumberUnit.Pixels, true, Scale.Log)))
        ui.receive(CraftUi.Request.Described(Panels(listOf(PanelInfo("brush", "Brush", "paintbrush.pointed", PanelRole.Tool)), mapOf("brush" to panel))))
        ui.receive(CraftUi.Request.Menus(MenuBar(listOf(Menu("Edit", MenuRole.Edit, emptyList())))))
        ui.receive(CraftUi.Request.Said(Status(Status.Message("Saved"))))
        ui.receive(CraftUi.Request.Live(listOf(LiveValue("timeline", "transport", 3))))
        assertTrue(sent.isEmpty())
        // A refused edit is answered with the same description: the count still moves, for a released drag to settle.
        ui.receive(CraftUi.Request.Described(Panels(ui.panels, ui.open)))
        assertEquals(2L, ui.descriptions)
        assertTrue(sent.isEmpty())
    }

    @Test
    fun anOpenRequestIsOneShot() {
        val ui = CraftUi {}
        ui.receive(CraftUi.Request.Open("layers"))
        val first = ui.openRequest
        ui.openRequestHandled()
        assertNull(ui.openRequest)
        ui.receive(CraftUi.Request.Open("layers"))
        assertNotEquals("asking twice is two requests", first, ui.openRequest)
    }
}

class TooltipTextTest {
    @Test
    fun aTooltipNamesTheShortcutAfterTheLabelWhereThereIsOne() {
        assertEquals("Brush  B", tooltipText("Brush", "B"))
        assertEquals("Tool Options", tooltipText("Tool Options", null))
        assertEquals("Tool Options", tooltipText("Tool Options", ""))
    }
}
