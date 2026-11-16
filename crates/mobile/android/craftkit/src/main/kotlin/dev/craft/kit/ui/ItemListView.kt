package dev.craft.kit.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.AnchoredDraggableState
import androidx.compose.foundation.gestures.DraggableAnchors
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.anchoredDraggable
import androidx.compose.foundation.gestures.animateTo
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.isCtrlPressed
import androidx.compose.ui.input.pointer.isMetaPressed
import androidx.compose.ui.input.pointer.isShiftPressed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Rows of items such as layers: tap to select, the eye to hide, swipe for Hide and the row's
 * destructive actions, long-press for Rename (unless the row says it can't be) and the row's own
 * actions, drag the handle to reorder (when [Node.ItemList.reorderable]). Select (in the header)
 * picks several rows, a tap adding or removing each, until Done; with a keyboard, Ctrl-tap does the
 * same and Shift-tap selects a range. The list's own actions are buttons in its footer: the first
 * with its label (New Layer), the rest as icons.
 *
 * Every edit is one `commit` in a gesture of its own.
 */
@Composable
internal fun CraftItemList(node: Node.ItemList, panel: String, send: (Edit) -> Unit, modifier: Modifier = Modifier) {
    var multiSelecting by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<Row?>(null) }
    val one = { value: EditValue -> send(Edit.commit(panel, node.id, value)) }
    val reorder = remember { Reorder() }

    Column(modifier.fillMaxWidth()) {
        if (node.rows.size > 1) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = { multiSelecting = !multiSelecting }) {
                    Text(if (multiSelecting) "Done" else "Select", fontWeight = if (multiSelecting) FontWeight.SemiBold else FontWeight.Normal)
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            node.rows.forEachIndexed { index, row ->
                key(row.id) {
                    val shift by animateFloatAsState(reorder.shift(index), label = "reorder")
                    val dragging = reorder.from == index
                    SwipeRow(
                        row = row,
                        one = one,
                        modifier = Modifier
                            .zIndex(if (dragging) 1f else 0f)
                            .graphicsLayer { translationY = if (dragging) reorder.offset else shift }
                            .onSizeChanged { reorder.heights[index] = it.height.toFloat() },
                    ) {
                        RowContent(
                            row = row,
                            multiSelecting = multiSelecting,
                            reorderable = node.reorderable,
                            dragging = dragging,
                            one = one,
                            startRenaming = { renaming = row },
                            select = { mode -> one(EditValue.Select(row.id, mode)) },
                            handle = Modifier.pointerInput(row.id, index, node.rows) {
                                detectDragGestures(
                                    onDragStart = { reorder.start(index) },
                                    onDrag = { change, amount ->
                                        change.consume()
                                        reorder.drag(amount.y, node.rows.size)
                                    },
                                    onDragEnd = { reorder.end()?.let { to -> ItemLists.moveEdit(node.rows, index, to)?.let(one) } },
                                    onDragCancel = { reorder.cancel() },
                                )
                            },
                        )
                    }
                }
            }
        }
        if (node.actions.isNotEmpty()) {
            Footer(node.actions) { action -> one(EditValue.ListAction(action.id)) }
        }
    }

    renaming?.let { row ->
        RenameDialog(row, onDismiss = { renaming = null }) { name ->
            renaming = null
            if (name.isNotEmpty() && name != row.title) one(EditValue.Rename(row.id, name))
        }
    }
}

/** A row being dragged by its handle: where it started, how far it moved, and the row heights it moves past. */
private class Reorder {
    var from by mutableIntStateOf(-1)
        private set
    var offset by mutableFloatStateOf(0f)
        private set
    private var to by mutableIntStateOf(-1)
    val heights = mutableStateMapOf<Int, Float>()

    fun start(index: Int) {
        from = index
        to = index
        offset = 0f
    }

    fun drag(dy: Float, count: Int) {
        if (from < 0) return
        offset += dy
        val height = heights[from]?.takeIf { it > 0 } ?: return
        to = (from + (offset / height).roundToInt()).coerceIn(0, count - 1)
    }

    /** The drop: the index in the list before the move where the row lands; `null` without a drag. */
    fun end(): Int? {
        val (start, target) = from to to
        cancel()
        if (start < 0) return null
        return if (target > start) target + 1 else target
    }

    fun cancel() {
        from = -1
        to = -1
        offset = 0f
    }

    /** How far the row at [index] steps aside for the dragged one. */
    fun shift(index: Int): Float {
        if (from < 0 || index == from) return 0f
        val height = heights[from] ?: return 0f
        return when {
            index in (from + 1)..to -> -height
            index in to until from -> height
            else -> 0f
        }
    }
}

private enum class Swipe { Closed, Open }

/**
 * A row that swipes toward the start to reveal Hide (or Show) and its destructive actions, each a
 * tap away: a swipe alone never deletes anything.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SwipeRow(row: Row, one: (EditValue) -> Unit, modifier: Modifier, content: @Composable () -> Unit) {
    val destructive = ItemLists.swipeActions(row)
    val buttons = (if (row.visible != null) 1 else 0) + destructive.size
    if (buttons == 0) {
        Box(modifier) { content() }
        return
    }
    val reveal = with(LocalDensity.current) { (SWIPE_BUTTON * buttons).toPx() }
    val state = remember(reveal) {
        AnchoredDraggableState(Swipe.Closed, DraggableAnchors {
            Swipe.Closed at 0f
            Swipe.Open at -reveal
        })
    }
    val scope = rememberCoroutineScope()
    val close = { scope.launch { state.animateTo(Swipe.Closed) } }
    val colors = MaterialTheme.colorScheme
    Box(modifier.fillMaxWidth()) {
        // Behind the row only while it's swiped: its rounded corners mustn't show the buttons at rest.
        if (state.offset.let { !it.isNaN() && it < -1f }) Row(Modifier.matchParentSize().padding(start = 48.dp), horizontalArrangement = Arrangement.End) {
            row.visible?.let { visible ->
                SwipeButton(if (visible) "Hide" else "Show", colors.secondaryContainer, colors.onSecondaryContainer) {
                    close()
                    one(EditValue.SetVisible(row.id, !visible))
                }
            }
            destructive.forEach { action ->
                SwipeButton(action.label, colors.errorContainer, colors.onErrorContainer) {
                    close()
                    one(EditValue.Action(row.id, action.id))
                }
            }
        }
        Box(
            Modifier
                .offset { IntOffset(state.offset.takeIf { !it.isNaN() }?.roundToInt() ?: 0, 0) }
                .anchoredDraggable(state, Orientation.Horizontal),
        ) { content() }
    }
}

private val SWIPE_BUTTON = 84.dp

@Composable
private fun SwipeButton(label: String, container: Color, content: Color, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        color = container,
        contentColor = content,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.width(SWIPE_BUTTON - 4.dp).fillMaxHeight().padding(start = 4.dp),
    ) {
        Box(contentAlignment = Alignment.Center) { Text(label, style = MaterialTheme.typography.labelLarge) }
    }
}

/** One row: selected rows in secondary container with rounder corners; long-press for its menu. */
@OptIn(ExperimentalFoundationApi::class, ExperimentalComposeUiApi::class)
@Composable
private fun RowContent(
    row: Row,
    multiSelecting: Boolean,
    reorderable: Boolean,
    dragging: Boolean,
    one: (EditValue) -> Unit,
    startRenaming: () -> Unit,
    select: (SelectMode) -> Unit,
    handle: Modifier,
) {
    val colors = MaterialTheme.colorScheme
    var menu by remember { mutableStateOf(false) }
    val window = LocalWindowInfo.current
    val content = if (row.selected) colors.onSecondaryContainer else colors.onSurface
    val corner by animateDpAsState(if (row.selected) 20.dp else 12.dp, label = "corner")
    Box {
        Surface(
            shape = RoundedCornerShape(corner),
            color = when {
                dragging -> colors.surfaceContainerHighest
                row.selected -> colors.secondaryContainer
                else -> colors.surfaceContainerLow
            },
            contentColor = content,
            shadowElevation = if (dragging) 6.dp else 0.dp,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .combinedClickable(
                    role = Role.Button,
                    onLongClickLabel = "Row actions",
                    onLongClick = { menu = true },
                ) {
                    val keys = window.keyboardModifiers
                    select(ItemLists.selectMode(multiSelecting, command = keys.isCtrlPressed || keys.isMetaPressed, shift = keys.isShiftPressed))
                }
                .semantics {
                    contentDescription = if (row.subtitle.isEmpty()) row.title else "${row.title}, ${row.subtitle}"
                    selected = row.selected
                    if (row.visible == false) stateDescription = "Hidden"
                    customActions = buildList {
                        row.visible?.let { visible -> add(CustomAccessibilityAction(if (visible) "Hide" else "Show") { one(EditValue.SetVisible(row.id, !visible)); true }) }
                        if (row.rename == Rename.Allowed) add(CustomAccessibilityAction("Rename") { startRenaming(); true })
                        row.actions.forEach { action -> add(CustomAccessibilityAction(action.label) { one(EditValue.Action(row.id, action.id)); true }) }
                    }
                },
        ) {
            Row(Modifier.padding(start = 4.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                if (multiSelecting) {
                    Icon(
                        if (row.selected) Icons.Filled.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (row.selected) colors.primary else colors.onSurfaceVariant,
                        modifier = Modifier.padding(start = 8.dp, end = 4.dp),
                    )
                }
                val visible = row.visible
                if (visible != null) {
                    IconButton(onClick = { one(EditValue.SetVisible(row.id, !visible)) }) {
                        Icon(
                            if (visible) Icons.Outlined.Visibility else Icons.Outlined.VisibilityOff,
                            contentDescription = if (visible) "Hide ${row.title}" else "Show ${row.title}",
                            tint = if (visible) content else colors.onSurfaceVariant.copy(alpha = 0.6f),
                        )
                    }
                } else {
                    Spacer(Modifier.width(12.dp))
                }
                Column(Modifier.weight(1f).padding(start = 16.dp * row.depth, top = 8.dp, bottom = 8.dp)) {
                    Text(
                        row.title,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = if (row.selected) FontWeight.Medium else FontWeight.Normal,
                        color = if (row.visible == false) content.copy(alpha = 0.5f) else content,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (row.subtitle.isNotEmpty()) {
                        Text(row.subtitle, style = MaterialTheme.typography.labelMedium, color = colors.onSurfaceVariant, maxLines = 1)
                    }
                }
                if (reorderable) {
                    Box(handle.size(48.dp), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.DragHandle, contentDescription = "Reorder ${row.title}", tint = colors.onSurfaceVariant)
                    }
                }
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, shape = RoundedCornerShape(16.dp)) {
            if (row.rename == Rename.Allowed) {
                DropdownMenuItem(
                    text = { Text("Rename…") },
                    leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                    onClick = {
                        menu = false
                        startRenaming()
                    },
                )
                if (row.actions.isNotEmpty()) HorizontalDivider()
            }
            row.actions.forEach { action ->
                val tint = if (action.destructive) colors.error else colors.onSurface
                DropdownMenuItem(
                    text = { Text(action.label, color = tint) },
                    leadingIcon = action.icon?.let(CraftIcons::icon)?.let { icon -> { Icon(icon, contentDescription = null, tint = tint) } },
                    onClick = {
                        menu = false
                        one(EditValue.Action(row.id, action.id))
                    },
                )
            }
        }
    }
}

/** The list's own actions: the first a filled tonal button with its label, the rest icon buttons named by theirs. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Footer(actions: List<ItemAction>, act: (ItemAction) -> Unit) {
    val colors = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        actions.forEachIndexed { index, action ->
            val icon = action.icon?.let(CraftIcons::icon)
            val tint = if (action.destructive) colors.error else Color.Unspecified
            if (index == 0 || icon == null) {
                FilledTonalButton(onClick = { act(action) }) {
                    if (icon != null) {
                        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                    }
                    Text(action.label, color = tint)
                }
            } else {
                TooltipBox(
                    positionProvider = TooltipDefaults.rememberTooltipPositionProvider(TooltipAnchorPosition.Above),
                    tooltip = { PlainTooltip { Text(action.label) } },
                    state = rememberTooltipState(),
                ) {
                    FilledTonalIconButton(onClick = { act(action) }) {
                        Icon(icon, contentDescription = action.label, tint = if (action.destructive) colors.error else LocalContentColor.current)
                    }
                }
            }
        }
    }
}

@Composable
private fun RenameDialog(row: Row, onDismiss: () -> Unit, onRename: (String) -> Unit) {
    var name by remember { mutableStateOf(row.title) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rename") },
        text = { OutlinedTextField(value = name, onValueChange = { name = it }, singleLine = true, label = { Text("Name") }) },
        confirmButton = { TextButton(onClick = { onRename(name.trim()) }) { Text("Rename") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
