package dev.craft.kit

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

/** Where the panels go as a desktop window is resized: the shell asks at every size. */
class ChromeLayoutTest {
    @Test
    fun aWideLandscapeWindowHasTheSideSheetAndPopovers() {
        assertEquals(ChromeLayout(sideSheet = true, compact = false), ChromeLayout.of(1024.dp, 600.dp))
        assertEquals(ChromeLayout(sideSheet = true, compact = false), ChromeLayout.of(600.dp, 599.dp))
    }

    /** Across 600dp the inspector moves to a bottom sheet and tools to bottom sheets. */
    @Test
    fun belowTheBreakpointEverythingIsABottomSheet() {
        assertEquals(ChromeLayout(sideSheet = false, compact = true), ChromeLayout.of(599.dp, 400.dp))
        assertEquals(ChromeLayout(sideSheet = false, compact = true), ChromeLayout.of(360.dp, 640.dp))
    }

    /** A tall window wide enough for popovers still has its inspector at the bottom, as portrait does. */
    @Test
    fun aTallWideWindowKeepsPopoversButNotTheSideSheet() {
        assertEquals(ChromeLayout(sideSheet = false, compact = false), ChromeLayout.of(800.dp, 1000.dp))
    }
}
