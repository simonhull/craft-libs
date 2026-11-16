package dev.craft.kit.ui

import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

class PopoverBoundsTest {
    @Test
    fun aRoomyWindowGetsThePopoversOwnSize() {
        assertEquals(DpSize(340.dp, 640.dp), popoverBounds(1024.dp, 800.dp))
    }

    /** A desktop window narrower or shorter than the popover: it fits inside the 12dp margins. */
    @Test
    fun aSmallWindowShrinksIt() {
        assertEquals(DpSize(276.dp, 476.dp), popoverBounds(300.dp, 500.dp))
    }

    @Test
    fun aWindowSmallerThanItsMarginsLeavesNothingNegative() {
        assertEquals(DpSize(0.dp, 0.dp), popoverBounds(20.dp, 10.dp))
    }
}
