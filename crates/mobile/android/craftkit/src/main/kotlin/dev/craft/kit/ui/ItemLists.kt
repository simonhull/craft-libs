package dev.craft.kit.ui

/** An item list's rules, apart from its views. */
object ItemLists {
    /** The row's actions offered as a swipe: the destructive ones, in the app's order. */
    fun swipeActions(row: Row): List<ItemAction> = row.actions.filter { it.destructive }

    /**
     * How a tap changes the selection: with Ctrl (or Meta) held the row is added or removed (and that
     * wins over Shift, as on the desktop), with Shift a range is selected; a plain tap selects the
     * row alone, or adds or removes it while picking several.
     */
    fun selectMode(multiSelecting: Boolean, command: Boolean = false, shift: Boolean = false): SelectMode = when {
        command -> SelectMode.Toggle
        shift -> SelectMode.Range
        multiSelecting -> SelectMode.Toggle
        else -> SelectMode.Replace
    }

    /**
     * The move for dragging the row at [from] so it lands before the row now at [destination] (the
     * index in the list before the move; `rows.size` is past the end). The list is flat, a row's
     * `depth` its nesting, so:
     * - A row's subtree (the rows after it that are deeper) moves with it in the app, so a drop
     *   between its own descendants, or just below the last of them, is refused: a group can't go
     *   inside itself.
     * - Past the last row is the bottom of the top level: below the last top-level row.
     * - Anywhere else is above the row the drop lands before.
     *
     * `null` when the drop is refused or leaves the row where it was.
     */
    fun moveEdit(rows: List<Row>, from: Int, destination: Int): EditValue.Move? {
        val row = rows.getOrNull(from) ?: return null
        if (destination == from || destination == from + 1 || destination < 0 || destination > rows.size) return null
        val subtreeEnd = (from + 1 until rows.size).firstOrNull { rows[it].depth <= row.depth } ?: rows.size
        if (destination in (from + 1)..subtreeEnd) return null
        rows.getOrNull(destination)?.let { return EditValue.Move(row.id, it.id, Position.Above) }
        val minDepth = rows.minOf { it.depth }
        val last = rows.lastOrNull { it.depth == minDepth }?.takeIf { it.id != row.id } ?: return null
        return EditValue.Move(row.id, last.id, Position.Below)
    }
}
