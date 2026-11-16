package dev.craft.gallery

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import dev.craft.kit.ui.ChromeMessage
import dev.craft.kit.ui.Edit
import dev.craft.kit.ui.EditValue
import dev.craft.kit.ui.LiveValue
import dev.craft.kit.ui.LiveValues
import dev.craft.kit.ui.MenuBar
import dev.craft.kit.ui.Node
import dev.craft.kit.ui.Panel
import dev.craft.kit.ui.PanelRole
import dev.craft.kit.ui.Phase
import dev.craft.kit.ui.Position
import dev.craft.kit.ui.Row
import dev.craft.kit.ui.SelectMode
import dev.craft.kit.ui.Status
import dev.craft.kit.ui.Tone
import dev.craft.kit.ui.ToolPalette
import dev.craft.kit.ui.Transport
import dev.craft.kit.ui.TransportAction
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * The catalogue's examples, played by the Gallery as an app would: each edit is applied to the
 * Gallery's own copy (so the controls respond) and logged as the JSON the app would receive.
 */
@Stable
class GalleryStore(catalogue: String, private val scope: CoroutineScope) {
    /** One primitive from the catalogue. */
    data class Entry(val name: String, val about: String, val example: Node)

    /** One piece of chrome from the catalogue (the menu bar, the status). */
    data class Chrome(val name: String, val about: String)

    var entries: List<Entry> by mutableStateOf(emptyList())
        private set
    var chrome: List<Chrome> by mutableStateOf(emptyList())
        private set

    /** The catalogue's menus, as the app would set them. */
    var menus: MenuBar by mutableStateOf(MenuBar())
        private set

    /** The catalogue's status, as the app would set it; the status page changes it. */
    var status: Status by mutableStateOf(Status())

    /** Why the catalogue didn't load, if it didn't. */
    var problem: String? by mutableStateOf(null)
        private set

    /** The messages sent, newest first. */
    val log = mutableStateListOf<String>()

    /** How many times the panels were described: every edit describes them again, as an app does. */
    var descriptions: Long by mutableLongStateOf(0)
        private set

    /** The transport's playhead while it plays, as the app sends it (wire kind 17): the panels aren't described again each frame. */
    val live = LiveValues()

    /** Each drag in progress, by gesture: its control and the value it started from, which a cancel puts back. */
    private val drags = HashMap<Long, Pair<String, EditValue>>()
    private var playback: Job? = null

    init {
        runCatching {
            val json = Json.parseToJsonElement(catalogue).jsonObject
            entries = json.getValue("primitives").jsonArray.map { it.jsonObject }.map { Entry(it.text("name"), it.text("about"), Node.decode(it.getValue("example"))) }
            val pieces = json.getValue("chrome").jsonArray.map { it.jsonObject }
            chrome = pieces.map { Chrome(it.text("name"), it.text("about")) }
            pieces.firstOrNull { it.text("name") == "menu_bar" }?.let { menus = MenuBar.parse(it.getValue("example").toString()) }
            pieces.firstOrNull { it.text("name") == "status" }?.let { status = Status.parse(it.getValue("example").toString()) }
        }.onFailure { problem = "Couldn't read the catalogue: ${it.message}" }
    }

    private fun JsonObject.text(key: String) = getValue(key).jsonPrimitive.content

    /** One primitive's example as a panel of its own, with its disabled look where that differs. */
    fun panel(entry: Entry, role: PanelRole) = Panel(entry.name, entry.name, role, listOf(entry.example) + disabled(entry.example))

    /** Every example in one panel, as an app's inspector would hold them. */
    fun everything(role: PanelRole) = Panel(EVERYTHING, "Everything", role, entries.flatMap { listOf(it.example) + disabled(it.example) })

    /**
     * A disabled copy of a number at its maximum, as an app shows a locked layer's opacity at 100 %:
     * its track must still read full, not empty.
     */
    private fun disabled(example: Node): List<Node> = when (example) {
        is Node.Number -> listOf(example.copy(id = "${example.id}.disabled", label = "${example.label} (disabled)", value = example.range.endInclusive, enabled = false))
        else -> emptyList()
    }

    /** The first tool palette among the examples, for the Gallery's rail. */
    val palette: ToolPalette? get() = entries.firstNotNullOfOrNull { it.example as? ToolPalette }

    /** The first transport among the examples, for the Gallery's transport bar. */
    val transport: Transport? get() = entries.firstNotNullOfOrNull { it.example as? Transport }

    /** A stand-in for the app's Tool panel [id], which the rail opens for a tool's options: the catalogue's number. */
    fun optionsPanel(id: String) = Panel(id, id.replaceFirstChar(Char::uppercase), PanelRole.Tool, entries.filter { it.name == "number" }.map { it.example })

    /** Log [edit] as the app would receive it, then apply it as the app would and describe the panels again. */
    fun send(edit: Edit) {
        logLine(edit.toJson())
        // An edit describes the panels again: the playhead's live position goes into them.
        foldLivePositions()
        when (edit.phase) {
            Phase.Begin -> entries.firstNotNullOfOrNull { it.example.value(edit.control) }?.let { drags[edit.gesture] = edit.control to it }
            Phase.Change, Phase.Commit -> {
                apply(edit.value, edit.control)
                if (edit.phase == Phase.Commit) drags.remove(edit.gesture)
            }
            Phase.Cancel -> drags.remove(edit.gesture)?.let { (control, from) -> apply(from, control) }
        }
        descriptions += 1
        playIfPlaying()
    }

    /** Log a chrome message (a menu command, Cancel) as the app would receive it. */
    fun command(id: String) = logLine(ChromeMessage.Command(id).toJson())

    fun logLine(line: String) {
        log.add(0, line)
        while (log.size > 50) log.removeAt(log.lastIndex)
    }

    fun clearLog() = log.clear()

    private fun apply(value: EditValue, control: String) {
        entries = entries.map { it.copy(example = it.example.applying(value, control)) }
    }

    private fun foldLivePositions() {
        val t = transport ?: return
        val position = PANELS_WITH_TRANSPORT.firstNotNullOfOrNull { live.position(it, t.id) } ?: return
        apply(EditValue.Seek(position), t.id)
        live.described()
    }

    /**
     * Plays the transport while it says it's playing, as PhotoCraft does: the frame follows the clock,
     * looping over the whole duration, and only a changed frame is sent, as a live position.
     */
    private fun playIfPlaying() {
        playback?.cancel()
        playback = null
        val t = transport?.takeIf { it.playing } ?: return
        val start = System.nanoTime()
        playback = scope.launch {
            var shown = t.position
            while (isActive) {
                delay((1000 / t.rate).toLong().coerceAtLeast(8))
                val elapsed = (System.nanoTime() - start) / 1e9
                val frame = (t.position + (elapsed * t.rate).toLong()) % t.duration
                if (frame != shown) {
                    shown = frame
                    live.apply(PANELS_WITH_TRANSPORT.map { LiveValue(it, t.id, frame) })
                }
            }
        }
    }

    // The status page's buttons, as an app would set its status.
    private var messageId = 100L
    private var countdown: Job? = null

    fun say(text: String, tone: Tone) {
        status = status.copy(message = Status.Message(text, tone, ++messageId))
    }

    fun startJob() {
        status = status.copy(progress = Status.Progress("Exporting great-wave.png", null, "job.cancel"))
        scope.launch {
            delay(1_500)
            for (step in 1..20) {
                if (status.progress == null) return@launch
                status = status.copy(progress = Status.Progress("Exporting great-wave.png", step / 20.0, "job.cancel"))
                delay(200)
            }
            status = status.copy(progress = null)
        }
    }

    fun cancelJob() {
        command("job.cancel")
        status = status.copy(progress = null)
    }

    /** "Retrying in N s", each second under one id, as PhotoCraft says it while its scratch disk is low. */
    fun countDown() {
        countdown?.cancel()
        val id = ++messageId
        countdown = scope.launch {
            for (left in 5 downTo 1) {
                status = status.copy(message = Status.Message("Scratch disk is full. Retrying in $left s", Tone.Error, id))
                delay(1_000)
            }
            status = status.copy(message = Status.Message("Scratch disk has room again", Tone.Info, ++messageId))
        }
    }

    companion object {
        /** The id of the panel that shows every example at once. */
        const val EVERYTHING = "everything"

        /** The panel the floating transport bar names in its edits, as an app's transport panel would. */
        const val TIMELINE = "timeline"

        /** The panel the rail names in its edits, as an app's rail panel would. */
        const val TOOLS = "tools"

        /** The panels a transport is in: its own page's, Everything, and the floating bar's. */
        private val PANELS_WITH_TRANSPORT = listOf("transport", EVERYTHING, TIMELINE)
    }
}

/** The value of the control [control] (inside sections too), as an edit would carry it. */
fun Node.value(control: String): EditValue? = when (this) {
    is Node.Section -> children.firstNotNullOfOrNull { it.value(control) }
    is Node.Number -> EditValue.Number(value).takeIf { id == control }
    is Node.Toggle -> EditValue.Toggle(value).takeIf { id == control }
    is Node.Choice -> EditValue.Choice(value).takeIf { id == control }
    is ToolPalette -> EditValue.Choice(selected).takeIf { id == control }
    is Transport -> EditValue.Seek(position).takeIf { id == control }
    else -> null
}

/** The node with an edit's value applied to [control] (inside sections too), as an app would describe it next. */
fun Node.applying(value: EditValue, control: String): Node = when {
    this is Node.Section -> copy(children = children.map { it.applying(value, control) })
    id != control -> this
    this is Node.Number && value is EditValue.Number -> copy(value = value.value.coerceIn(range))
    this is Node.Toggle && value is EditValue.Toggle -> copy(value = value.value)
    this is Node.Choice && value is EditValue.Choice && options.any { it.id == value.value } -> copy(value = value.value)
    this is ToolPalette && value is EditValue.Choice && slots.any { slot -> slot.tools.any { it.id == value.value } } -> selecting(value.value)
    // A scrub pauses, as in PhotoCraft.
    this is Transport && value is EditValue.Seek -> with(position = value.frame, playing = false)
    this is Transport && value is EditValue.Transport -> applying(value.action)
    this is Node.ItemList -> copy(rows = rows.applying(value, reorderable))
    else -> this
}

/** The rows after a list edit. An action means what the app says it does; the Gallery only logs it. */
fun List<Row>.applying(value: EditValue, reorderable: Boolean): List<Row> = when (value) {
    is EditValue.Select -> when (value.mode) {
        SelectMode.Replace -> map { it.copy(selected = it.id == value.row) }
        SelectMode.Toggle -> map { if (it.id == value.row) it.copy(selected = !it.selected) else it }
        SelectMode.Range -> {
            // From the first row selected (the Gallery keeps no anchor) to this one.
            val to = indexOfFirst { it.id == value.row }
            if (to < 0) {
                this
            } else {
                val from = indexOfFirst { it.selected }.takeIf { it >= 0 } ?: to
                mapIndexed { i, row -> row.copy(selected = i in minOf(from, to)..maxOf(from, to)) }
            }
        }
    }
    is EditValue.SetVisible -> map { if (it.id == value.row && it.visible != null) it.copy(visible = value.visible) else it }
    is EditValue.Rename -> map { if (it.id == value.row) it.copy(title = value.name) else it }
    is EditValue.Move -> {
        val moving = firstOrNull { it.id == value.row }
        val rest = filter { it.id != value.row }
        val at = rest.indexOfFirst { it.id == value.target }
        if (!reorderable || moving == null || value.row == value.target || at < 0) {
            this
        } else {
            rest.toMutableList().apply { add(if (value.position == Position.Above) at else at + 1, moving) }
        }
    }
    else -> this
}

/** A button's action, as PhotoCraft plays its timeline: Stop pauses, and rewinds if already paused; stepping and jumping pause. */
fun Transport.applying(action: TransportAction): Transport = when (action) {
    TransportAction.Play -> with(playing = true)
    TransportAction.Pause -> with(playing = false)
    TransportAction.Stop -> if (playing) with(playing = false) else with(position = 0)
    TransportAction.StepBack -> with(position = (position - 1).coerceAtLeast(0), playing = false)
    TransportAction.StepForward -> with(position = position + 1, playing = false)
    TransportAction.ToStart -> with(position = 0, playing = false)
    TransportAction.ToEnd -> with(position = duration - 1, playing = false)
}
