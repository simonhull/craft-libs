package dev.craft.kit.ui

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import java.util.concurrent.atomic.AtomicLong

/** Where a gesture is: a drag sends `begin`, `change`s, then `commit` or `cancel`; a tap or pick sends `commit` alone. */
enum class Phase(override val wire: String) : WireName {
    Begin("begin"),
    Change("change"),
    Commit("commit"),
    Cancel("cancel"),
}

/** Above or below a target row. */
enum class Position(override val wire: String) : WireName {
    Above("above"),
    Below("below"),
}

/** How selecting a row changes the selection: alone, added or removed, or a range from the last row selected. */
enum class SelectMode(override val wire: String) : WireName {
    Replace("replace"),
    Toggle("toggle"),
    Range("range"),
}

/** The value an edit carries, by the kind of control (`ui::EditValue`). */
@Immutable
sealed interface EditValue {
    data class Number(val value: Double) : EditValue

    data class Toggle(val value: Boolean) : EditValue

    data class Choice(val value: String) : EditValue

    data class Select(val row: Long, val mode: SelectMode = SelectMode.Replace) : EditValue

    data class SetVisible(val row: Long, val visible: Boolean) : EditValue

    data class Rename(val row: Long, val name: String) : EditValue

    data class Move(val row: Long, val target: Long, val position: Position) : EditValue

    /** One of a row's actions was chosen. */
    data class Action(val row: Long, val action: String) : EditValue

    /** One of the list's own actions (in its footer) was chosen. */
    data class ListAction(val action: String) : EditValue

    /** A transport's scrubber moved the playhead to [frame] (counted from 0). */
    data class Seek(val frame: Long) : EditValue

    /** One of a transport's buttons (always `commit`). */
    data class Transport(val action: TransportAction) : EditValue
}

/** One change from a native panel (`ui::Edit`), sent as `{"action":"edit", …}`. Only for the user's own gestures. */
@Immutable
data class Edit(val panel: String, val control: String, val phase: Phase, val gesture: Long, val value: EditValue) {
    /** The JSON craft-mobile's `Control::parse` reads. */
    fun toJsonObject(): JsonObject = buildJsonObject {
        put("action", "edit")
        put("panel", panel)
        put("control", control)
        put("phase", phase.wire)
        put("gesture", gesture)
        putJsonObject("value") { putValue(value) }
    }

    fun toJson(): String = toJsonObject().toString()

    private fun JsonObjectBuilder.putValue(value: EditValue) {
        fun plain(kind: String, primitive: JsonPrimitive) {
            put("kind", kind)
            put("value", primitive)
        }
        fun fields(kind: String, fields: JsonObjectBuilder.() -> Unit) {
            put("kind", kind)
            putJsonObject("value", fields)
        }
        when (value) {
            is EditValue.Number -> plain("number", JsonPrimitive(value.value))
            is EditValue.Toggle -> plain("toggle", JsonPrimitive(value.value))
            is EditValue.Choice -> plain("choice", JsonPrimitive(value.value))
            is EditValue.Transport -> plain("transport", JsonPrimitive(value.action.wire))
            is EditValue.Select -> fields("select") {
                put("row", value.row)
                put("mode", value.mode.wire)
            }
            is EditValue.SetVisible -> fields("set_visible") {
                put("row", value.row)
                put("visible", value.visible)
            }
            is EditValue.Rename -> fields("rename") {
                put("row", value.row)
                put("name", value.name)
            }
            is EditValue.Move -> fields("move") {
                put("row", value.row)
                put("target", value.target)
                put("position", value.position.wire)
            }
            is EditValue.Action -> fields("action") {
                put("row", value.row)
                put("action", value.action)
            }
            is EditValue.ListAction -> fields("list_action") { put("action", value.action) }
            is EditValue.Seek -> fields("seek") { put("frame", value.frame) }
        }
    }

    companion object {
        /** A complete edit of its own: one `commit`, in a new gesture (a tap, a pick, a typed value). */
        fun commit(panel: String, control: String, value: EditValue): Edit = Edit(panel, control, Phase.Commit, GestureIds.next(), value)
    }
}

/**
 * Gesture numbers, unique for the whole process. Apps coalesce undo on panel, control and gesture, so
 * a number must never be reused, even when a panel's views are torn down and built again.
 */
object GestureIds {
    private val counter = AtomicLong(1)

    /** A number no other gesture in this process has had. */
    fun next(): Long = counter.getAndIncrement()
}

/**
 * One number control's drag. While it runs, the control shows the finger's value, not the app's
 * (which may lag a frame or reject a value). After it ends, the control shows the value it sent last
 * (the committed one, or the one a cancel put back) until the app next describes the panel, whatever
 * that description says: the app's value then wins, so a clamped or refused value shows the app's
 * truth, without a frame of the value from before the drag in between.
 */
@Stable
class GestureHold {
    /** One edit's worth of a drag. */
    data class Step(val gesture: Long, val phase: Phase, val value: Double)

    private class Drag(val gesture: Long, val from: Double, val now: Double)

    private var drag by mutableStateOf<Drag?>(null)
    private var settling by mutableStateOf<Double?>(null)

    val isDragging: Boolean get() = drag != null

    /** A drag starts from the app's [value], with a new gesture number. */
    fun begin(value: Double): Step {
        val gesture = GestureIds.next()
        drag = Drag(gesture, value, value)
        settling = null
        return Step(gesture, Phase.Begin, value)
    }

    /** The finger moved; `null` if no drag is running. */
    fun change(value: Double): Step? {
        val running = drag ?: return null
        drag = Drag(running.gesture, running.from, value)
        return Step(running.gesture, Phase.Change, value)
    }

    /** The drag ended: its last value; `null` if none was running. */
    fun commit(): Step? {
        val running = drag ?: return null
        drag = null
        settling = running.now
        return Step(running.gesture, Phase.Commit, running.now)
    }

    /** The drag was abandoned (or its view went away): the value from before it; `null` if none was running. */
    fun cancel(): Step? {
        val running = drag ?: return null
        drag = null
        settling = running.from
        return Step(running.gesture, Phase.Cancel, running.from)
    }

    /** The app described the panel again (any description, changed or not): an ended drag's value gives way to the app's. */
    fun described() {
        if (settling != null) settling = null
    }

    /** What the control shows: the finger's value mid-drag, then the value the drag ended on until the next description, the app's otherwise. */
    fun shown(app: Double): Double = drag?.now ?: settling ?: app
}
