package dev.craft.kit.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties

/** Which side of its anchor a popover opens on. */
enum class PopoverSide {
    /** Below the anchor, its trailing edge in line with the anchor's (a top bar's button). */
    Below,

    /** Beside the anchor, toward the screen's middle, its bottom in line with the anchor's (the rail's options button). */
    End,
}

/**
 * A tool panel's popover: a card anchored to the composable it's placed in (its trigger), as tall as
 * what it holds up to what fits, kept on screen. Its header shows [title] and a Close button, as the
 * inspector's side sheet does; that button, a tap outside, or Back calls [onDismiss].
 */
@Composable
fun CraftPopover(side: PopoverSide, onDismiss: () -> Unit, title: String? = null, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val provider = remember(side, density) { PopoverPosition(side, density) }
    Popup(popupPositionProvider = provider, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            tonalElevation = 2.dp,
            shadowElevation = 8.dp,
            modifier = Modifier.width(POPOVER_WIDTH).heightIn(min = 120.dp, max = 640.dp),
        ) {
            Column {
                PanelHeader(title, close = onDismiss)
                Box(Modifier.weight(1f, fill = false)) { content() }
            }
        }
    }
}

/**
 * A sheet's or popover's header: its [title] (none when `null`), and a Close button, with its
 * tooltip, where there's [close] (a modal bottom sheet has none: a swipe or a tap outside closes it).
 */
@Composable
internal fun PanelHeader(title: String?, close: (() -> Unit)?, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().padding(start = 24.dp, end = 8.dp, top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title.orEmpty(), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
        close?.let {
            CraftTooltip("Close") {
                IconButton(onClick = it) { Icon(Symbols.Close, contentDescription = if (title.isNullOrEmpty()) "Close" else "Close $title") }
            }
        }
    }
}

/** A tool popover's width, as an iPad popover's ideal width. */
internal val POPOVER_WIDTH = 340.dp

private class PopoverPosition(private val side: PopoverSide, density: Density) : PopupPositionProvider {
    private val gap = with(density) { 8.dp.roundToPx() }
    private val margin = with(density) { 12.dp.roundToPx() }

    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val maxX = (windowSize.width - popupContentSize.width - margin).coerceAtLeast(margin)
        val maxY = (windowSize.height - popupContentSize.height - margin).coerceAtLeast(margin)
        val ltr = layoutDirection == LayoutDirection.Ltr
        return when (side) {
            PopoverSide.Below -> IntOffset(
                x = (if (ltr) anchorBounds.right - popupContentSize.width else anchorBounds.left).coerceIn(margin, maxX),
                y = (anchorBounds.bottom + gap).coerceIn(margin, maxY),
            )
            PopoverSide.End -> IntOffset(
                x = (if (ltr) anchorBounds.right + gap else anchorBounds.left - gap - popupContentSize.width).coerceIn(margin, maxX),
                y = (anchorBounds.bottom - popupContentSize.height).coerceIn(margin, maxY),
            )
        }
    }
}
