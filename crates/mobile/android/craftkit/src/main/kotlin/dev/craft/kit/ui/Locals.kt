package dev.craft.kit.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * How many descriptions of the panels the app has sent, changed or not ([CraftUi.descriptions]): a
 * number control shows the value its drag ended on until the next one. A reader, not the count, so
 * only the controls that call it (those holding a drag) redraw for a new description.
 */
val LocalCraftDescriptions = staticCompositionLocalOf<() -> Long> { { 0L } }

/** The transports' live positions ([CraftUi.live]); only transport playheads read them. `null` for none. */
val LocalCraftLiveValues = staticCompositionLocalOf<LiveValues?> { null }

/** Provides [ui]'s descriptions and live positions to the panels drawn in [content]. */
@Composable
fun ProvideCraftUi(ui: CraftUi, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalCraftDescriptions provides ui::descriptions, LocalCraftLiveValues provides ui.live, content = content)
}
