package dev.craft.kit.ui

import android.os.SystemClock
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalFloatingToolbar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.first

/**
 * The rail: the app's tools in a vertical floating toolbar at the canvas's leading edge (or a row, in
 * a panel). Tap a tool to select it (a `choice` edit, `commit`); long-press a slot with more tools
 * (marked with a dot) for its flyout; double-tap the selected tool, or the options button, for its
 * options: [onOptionsPanel] is told to show its Tool panel, which [optionsContent] draws in a popover
 * beside the button under the title [optionsTitle] gives it, or the fallback [command] is sent.
 *
 * The selected tool is a rounded square in primary container with a filled icon; the others are
 * circles. The tools scroll when they don't fit; the options button stays.
 */
@Composable
fun CraftRail(
    palette: ToolPalette,
    panel: String,
    send: (Edit) -> Unit,
    command: (String) -> Unit,
    optionsPanel: String?,
    onOptionsPanel: (String?) -> Unit,
    modifier: Modifier = Modifier,
    horizontal: Boolean = false,
    optionsTitle: (String) -> String? = { null },
    optionsContent: @Composable (String) -> Unit = {},
) {
    val taps = remember { RailTaps() }
    // A tool double-tapped before the app described it selected: its options open once it has.
    var pendingOptions by remember { mutableStateOf<String?>(null) }
    val open = { route: RailOptions ->
        when (route) {
            is RailOptions.Panel -> onOptionsPanel(if (optionsPanel == route.id) null else route.id)
            is RailOptions.Command -> command(route.id)
        }
    }
    LaunchedEffect(palette) {
        val tool = pendingOptions ?: return@LaunchedEffect
        if (palette.selected != tool) return@LaunchedEffect
        pendingOptions = null
        palette.optionsRoute?.let(open)
    }
    val tap = { tool: String ->
        pendingOptions = null
        when (taps.tap(tool, palette.selected, SystemClock.uptimeMillis())) {
            RailTaps.Outcome.Select -> send(Edit.commit(panel, palette.id, EditValue.Choice(tool)))
            RailTaps.Outcome.Options -> palette.optionsNow(tool)?.let(open) ?: run { if (tool != palette.selected) pendingOptions = tool }
            RailTaps.Outcome.Nothing -> Unit
        }
    }

    val scroll = rememberScrollState()
    val slotPx = with(LocalDensity.current) { (SLOT + SPACING).toPx() }
    // A tool picked by its shortcut scrolls into view.
    LaunchedEffect(palette.selected) {
        val index = palette.slotIndex(palette.selected) ?: return@LaunchedEffect
        val viewport = snapshotFlow { scroll.viewportSize }.first { it > 0 }
        railScrollTarget(index, slotPx, scroll.value, viewport)?.let { scroll.animateScrollTo(it) }
    }

    val tools = @Composable {
        palette.slots.forEach { slot ->
            slot.shown(palette.selected)?.let { tool -> RailSlot(slot, tool, palette.selected, tap) }
        }
    }
    val options = @Composable {
        palette.optionsRoute?.let { route ->
            Box {
                CraftTooltip("Tool Options", position = TipSide.End) {
                    IconButton(onClick = { open(route) }, modifier = Modifier.size(SLOT)) {
                        Icon(Symbols.Tune, contentDescription = "Tool Options")
                    }
                }
                optionsPanel?.let { id -> CraftPopover(PopoverSide.End, onDismiss = { onOptionsPanel(null) }, title = optionsTitle(id)) { optionsContent(id) } }
            }
        }
    }

    if (horizontal) {
        Row(modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(SPACING)) { tools() }
        return
    }
    // The options button stays in the toolbar's own column, after the tools that scroll, so it
    // never scrolls away: a trailing slot would be squeezed out by a rail of many tools.
    VerticalFloatingToolbar(
        expanded = true,
        modifier = modifier,
        colors = floatingChromeColors(),
        expandedShadowElevation = FLOATING_ELEVATION,
    ) {
        Column(Modifier.weight(1f, fill = false).touchTargetsAtEdges(), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(
                Modifier.weight(1f, fill = false).verticalScroll(scroll),
                verticalArrangement = Arrangement.spacedBy(SPACING),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) { tools() }
            if (palette.optionsRoute != null) {
                HorizontalDivider(Modifier.width(32.dp).padding(vertical = 6.dp))
                options()
            }
        }
    }
}

private val SLOT = 48.dp
private val SPACING = 4.dp

/**
 * One slot: its shown tool, a rounded square while selected and a circle otherwise; a slot with more
 * tools opens its flyout on a long press (or a right-click), and says so with a dot.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RailSlot(slot: ToolSlot, tool: Tool, selected: String, tap: (String) -> Unit) {
    val isSelected = tool.id == selected
    val more = slot.tools.size > 1
    var flyout by remember { mutableStateOf(false) }
    val colors = MaterialTheme.colorScheme
    val corner by animateDpAsState(if (isSelected) 16.dp else SLOT / 2, MaterialTheme.motionScheme.fastSpatialSpec(), label = "corner")
    val container by animateColorAsState(if (isSelected) colors.primaryContainer else Color.Transparent, label = "container")
    val content = if (isSelected) colors.onPrimaryContainer else colors.onSurfaceVariant
    val shortcut = tool.shortcut?.let(Shortcut::parse)?.label
    Box {
        // Its name and shortcut on hover, or a long press where that doesn't open the flyout.
        CraftTooltip(tool.label, shortcut = shortcut, position = TipSide.End, longPressFree = !more) {
            Box(
                Modifier
                    .size(SLOT)
                    // The ripple keeps to the slot's shape.
                    .clip(RoundedCornerShape(corner))
                    .background(container)
                    .then(if (more) Modifier.onSecondaryClick { flyout = true } else Modifier)
                    .combinedClickable(
                        role = Role.Button,
                        onLongClickLabel = if (more) "More tools" else null,
                        onLongClick = if (more) ({ flyout = true }) else null,
                    ) { tap(tool.id) }
                    .semantics {
                        contentDescription = shortcut?.let { "${tool.label}, shortcut $it" } ?: tool.label
                        this.selected = isSelected
                        if (more) customActions = listOf(CustomAccessibilityAction("More tools") { flyout = true; true })
                    },
                contentAlignment = Alignment.Center,
            ) {
                ToolFace(tool, filled = isSelected, tint = content)
                if (more) {
                    Box(
                        Modifier
                            .align(Alignment.BottomEnd)
                            .padding(7.dp)
                            .size(4.dp)
                            .background(content.copy(alpha = 0.8f), CircleShape),
                    )
                }
            }
        }
        // Beside the rail, level with the slot.
        DropdownMenu(expanded = flyout, onDismissRequest = { flyout = false }, offset = DpOffset(SLOT + 12.dp, -SLOT), shape = RoundedCornerShape(16.dp)) {
            slot.tools.forEach { other ->
                DropdownMenuItem(
                    text = { Text(other.label) },
                    leadingIcon = { ToolFace(other, filled = other.id == selected, tint = LocalContentColor.current) },
                    trailingIcon = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            other.shortcut?.let(Shortcut::parse)?.let { Text(it.label, style = MaterialTheme.typography.labelMedium, color = colors.onSurfaceVariant) }
                            if (other.id == selected) {
                                Spacer(Modifier.width(8.dp))
                                Icon(Symbols.Check, contentDescription = "Selected", modifier = Modifier.size(18.dp))
                            }
                        }
                    },
                    onClick = {
                        flyout = false
                        tap(other.id)
                    },
                )
            }
        }
    }
}

/** A tool's icon, or its letter in the same place. */
@Composable
internal fun ToolFace(tool: Tool, filled: Boolean, tint: Color) {
    when (val shown = tool.icon.shown(tool.label)) {
        is ToolIcon.Shown.Symbol -> CraftIcons.icon(shown.name, filled)?.let { Icon(it, contentDescription = null, tint = tint) }
        is ToolIcon.Shown.Letter -> Text(
            shown.letter,
            color = tint,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Monospace,
            modifier = Modifier.height(24.dp),
        )
    }
}
