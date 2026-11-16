package dev.craft.kit.ui

import androidx.compose.material3.FloatingToolbarColors
import androidx.compose.material3.FloatingToolbarDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MinimumInteractiveLeftAlignmentLine
import androidx.compose.material3.MinimumInteractiveTopAlignmentLine
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.dp

/**
 * The floating toolbars' colours over the canvas (the rail, the transport bar): the standard
 * toolbar's, a container step higher, so they stand off a dark image as well as a bright one.
 */
@Composable
internal fun floatingChromeColors(): FloatingToolbarColors =
    FloatingToolbarDefaults.standardFloatingToolbarColors(toolbarContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh)

/** A floating toolbar's shadow over the canvas: the standard toolbar has none, and loses its edge on a busy image. */
internal val FLOATING_ELEVATION = 3.dp

/**
 * Says the content's touch targets already reach its edges. A floating toolbar balances its
 * padding by its content's [MinimumInteractiveTopAlignmentLine]; in a column of tools that line
 * comes from the lowest Material button (the rail's options button), as far down as it is, and
 * the toolbar would pad itself that much wider. The rail's slots are full touch targets, so the
 * true inset is zero.
 */
internal fun Modifier.touchTargetsAtEdges(): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    layout(placeable.width, placeable.height, mapOf(MinimumInteractiveTopAlignmentLine to 0, MinimumInteractiveLeftAlignmentLine to 0)) {
        placeable.place(0, 0)
    }
}
