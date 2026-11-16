package dev.craft.kit.ui

import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Text
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier

/**
 * Material 3's plain tooltip on [content] (an icon button): its [label], and its keyboard
 * [shortcut] where it has one, shown on hover with a mouse and on a long press by touch. A control
 * whose long press does something else ([longPressFree] `false`, a rail slot with a flyout) shows
 * it on hover only.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CraftTooltip(
    label: String,
    modifier: Modifier = Modifier,
    shortcut: String? = null,
    position: TipSide = TipSide.Below,
    longPressFree: Boolean = true,
    content: @Composable () -> Unit,
) {
    val state = rememberTooltipState()
    val hover = remember { MutableInteractionSource() }
    val hovered by hover.collectIsHoveredAsState()
    if (!longPressFree) {
        LaunchedEffect(hovered) { if (hovered) state.show() else state.dismiss() }
    }
    TooltipBox(
        positionProvider = TooltipDefaults.rememberTooltipPositionProvider(
            when (position) {
                TipSide.Below -> TooltipAnchorPosition.Below
                TipSide.Above -> TooltipAnchorPosition.Above
                TipSide.End -> TooltipAnchorPosition.End
            },
        ),
        tooltip = { PlainTooltip { Text(tooltipText(label, shortcut)) } },
        state = state,
        modifier = modifier,
        enableUserInput = longPressFree,
    ) {
        Box(if (longPressFree) Modifier else Modifier.hoverable(hover)) { content() }
    }
}

/** Which side of its control a tooltip shows on: below an app bar button, above the transport bar, beside the rail. */
internal enum class TipSide { Below, Above, End }

/** A tooltip's text: the label, then its shortcut after a gap, as a desktop menu lists them. */
internal fun tooltipText(label: String, shortcut: String?): String = if (shortcut.isNullOrEmpty()) label else "$label  $shortcut"
