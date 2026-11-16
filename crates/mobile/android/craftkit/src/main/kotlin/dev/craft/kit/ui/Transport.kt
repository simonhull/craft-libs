package dev.craft.kit.ui

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

/** How a transport shows a time (`ui::TimeFormat`). Display only: positions and edits are always frames. */
enum class TimeFormat(override val wire: String) : WireName {
    /** The frame counted from 1, of the duration: "12 / 30". */
    Frames("frames"),

    /** Hours, minutes, seconds and frames at the transport's rate: "00:00:00:11". */
    Timecode("timecode"),
}

/** What a transport button asks for (`ui::TransportAction`). What Stop does beyond pausing is the app's rule. */
enum class TransportAction(override val wire: String) : WireName {
    Play("play"),
    Pause("pause"),
    Stop("stop"),
    StepBack("step_back"),
    StepForward("step_forward"),
    ToStart("to_start"),
    ToEnd("to_end"),
}

/**
 * A transport bar (`ui::Transport`): a playhead over [duration] frames, played at [rate] frames per
 * second, with an optional work area [range] (start inclusive, end exclusive).
 *
 * Always valid ([of] makes one): at least one frame, the position on one of them, a finite rate above
 * zero, and a work area inside the frames and not empty, or none.
 */
@Immutable
class Transport private constructor(
    override val id: String,
    val position: Long,
    val duration: Long,
    val rate: Double,
    val format: TimeFormat,
    val playing: Boolean,
    val range: LongRange?,
    val enabled: Boolean,
) : Node {
    /** The same transport with another position (kept on a frame) or playing state, as the app describes it next. */
    fun with(position: Long = this.position, playing: Boolean = this.playing): Transport =
        Transport(id, position.coerceIn(0, duration - 1), duration, rate, format, playing, range, enabled)

    /** What the time label shows for [frame] (counted from 0). */
    fun label(frame: Long): String = label(frame, duration, rate, format)

    /** The widest label the transport can show, to keep the label's width steady while it plays. */
    val widestLabel: String get() = label(duration - 1)

    /** What TalkBack says for [frame]: "Frame 12 of 30", or the timecode. */
    fun spokenLabel(frame: Long): String = when (format) {
        TimeFormat.Frames -> "Frame ${frame + 1} of $duration"
        TimeFormat.Timecode -> label(frame)
    }

    /** Where the app says the playhead is: [live]'s position for it in [panel] when one arrived, else the described one. */
    fun appPosition(panel: String, live: LiveValues?): Long = (live?.position(panel, id) ?: position).coerceIn(0, duration - 1)

    override fun equals(other: Any?): Boolean = other is Transport && id == other.id && position == other.position &&
        duration == other.duration && rate == other.rate && format == other.format && playing == other.playing &&
        range == other.range && enabled == other.enabled

    override fun hashCode(): Int = listOf(id, position, duration, rate, format, playing, range, enabled).hashCode()

    override fun toString(): String = "Transport($id, $position/$duration @ $rate, $format, playing=$playing, range=$range, enabled=$enabled)"

    companion object {
        /**
         * A transport, its values kept valid: a position past the end is the last frame, a work area
         * past the end is cut to it (none if that leaves it empty). `null` without frames or with a
         * rate that isn't a finite number above zero.
         */
        fun of(
            id: String,
            position: Long,
            duration: Long,
            rate: Double,
            format: TimeFormat = TimeFormat.Frames,
            playing: Boolean = false,
            range: LongRange? = null,
            enabled: Boolean = true,
        ): Transport? {
            if (duration <= 0 || !rate.isFinite() || rate <= 0) return null
            val work = range?.let { maxOf(it.first, 0)..minOf(it.last, duration - 1) }?.takeUnless { it.isEmpty() }
            return Transport(id, position.coerceIn(0, duration - 1), duration, rate, format, playing, work, enabled)
        }

        internal fun decode(json: JsonObject): Transport = with(json) {
            // `[start, end]`, end exclusive; anything else (left out, backwards, not a pair) is none.
            val bounds = (this["range"] as? JsonArray)?.map { (it as? JsonPrimitive)?.takeUnless(JsonPrimitive::isString)?.longOrNull }
            val range = bounds?.takeIf { it.size == 2 }?.let { (start, end) -> if (start != null && end != null && start < end) start until end else null }
            of(
                id = string("id"),
                position = count("position"),
                duration = count("duration"),
                rate = double("rate"),
                format = lenientEnum(runCatching { optString("format") }.getOrNull(), TimeFormat.Frames),
                playing = bool("playing"),
                range = range,
                enabled = optBool("enabled") ?: true,
            ) ?: throw WireException("a transport needs frames and a rate above zero")
        }

        /** [frame] (counted from 0) as the label shows it: `frames` "12 / 30", `timecode` as [timecode]. */
        fun label(frame: Long, duration: Long, rate: Double, format: TimeFormat): String = when (format) {
            TimeFormat.Frames -> "${frame + 1} / $duration"
            TimeFormat.Timecode -> timecode(frame, rate)
        }

        /**
         * [frame] (counted from 0) as SMPTE timecode, `HH:MM:SS:FF`. At 29.97 and 59.94 it is drop-frame,
         * `HH:MM:SS;FF`; every other rate counts whole frames at its nominal rate, the rate rounded up
         * (23.976 counts 24). Hours don't wrap at 24.
         */
        fun timecode(frame: Long, rate: Double): String {
            val drop = dropFrames(rate)
            val nominal: Long
            var counted = frame
            if (drop != null) {
                nominal = drop * 15
                val perMinute = nominal * 60 - drop
                val perTenMinutes = perMinute * 10 + drop
                val tens = frame / perTenMinutes
                val rest = frame % perTenMinutes
                counted += drop * 9 * tens
                if (rest >= drop) counted += drop * ((rest - drop) / perMinute)
            } else {
                // Rounded up, as 23.976 counts 24; a hair over a whole rate (24.0000001) is still that rate.
                nominal = ceil(maxOf(1.0, minOf(rate, 1_000_000.0) - 1e-6)).toLong()
            }
            val seconds = counted / nominal
            val frames = counted % nominal
            fun two(n: Long) = n.toString().padStart(2, '0')
            return "${two(seconds / 3600)}:${two(seconds / 60 % 60)}:${two(seconds % 60)}${if (drop == null) ":" else ";"}${two(frames)}"
        }

        /** The frame numbers drop-frame timecode skips each minute: 2 at 29.97, 4 at 59.94, `null` otherwise. */
        fun dropFrames(rate: Double): Long? = when {
            abs(rate - 30000.0 / 1001) < 0.005 -> 2
            abs(rate - 60000.0 / 1001) < 0.005 -> 4
            else -> null
        }
    }
}

/** The first transport among [nodes], inside sections too. */
fun List<Node>.firstTransport(): Transport? = firstNotNullOfOrNull { node ->
    when (node) {
        is Transport -> node
        is Node.Section -> node.children.firstTransport()
        else -> null
    }
}

/**
 * The scrubber's drag over a transport's frames, as edits: a touch seeks at once (`begin`), the
 * finger moving to another frame sends `change`, lifting it `commit`s where it is; a cancelled drag
 * sends `cancel` with the frame from before it.
 *
 * While the drag runs, the scrubber shows the finger's frame, not the app's echoes. After a commit
 * it shows the frame it sent last until the app next says where the playhead is (a description or a
 * live position); after a cancel, the app's frame at once.
 */
@Stable
class Scrub {
    /** One edit's worth of a drag. */
    data class Step(val gesture: Long, val phase: Phase, val frame: Long)

    private class Drag(val gesture: Long, val from: Long, val now: Long)

    private var drag by mutableStateOf<Drag?>(null)
    private var settling by mutableStateOf<Long?>(null)

    val isScrubbing: Boolean get() = drag != null

    /** The frame the finger is on, mid-drag. */
    val current: Long? get() = drag?.now

    /** The finger came down on [frame] while the app's playhead was on [app]. */
    fun begin(frame: Long, app: Long): Step {
        val gesture = GestureIds.next()
        drag = Drag(gesture, app, frame)
        settling = null
        return Step(gesture, Phase.Begin, frame)
    }

    /** The finger is over [frame]: a `change` if that's another frame; `null` if it isn't, or no drag runs. */
    fun move(frame: Long): Step? {
        val running = drag?.takeIf { it.now != frame } ?: return null
        drag = Drag(running.gesture, running.from, frame)
        return Step(running.gesture, Phase.Change, frame)
    }

    /** The finger lifted over [frame]; `null` if no drag was running. */
    fun commit(frame: Long): Step? {
        val running = drag ?: return null
        drag = null
        settling = frame
        return Step(running.gesture, Phase.Commit, frame)
    }

    /** The drag was abandoned (or its view went away): the frame from before it; `null` if none was running. */
    fun cancel(): Step? {
        val running = drag ?: return null
        drag = null
        settling = null
        return Step(running.gesture, Phase.Cancel, running.from)
    }

    /** The app said where the playhead is (a description, or a live position): its frame shows from now on. */
    fun settled() {
        if (settling != null) settling = null
    }

    /** The frame to show: the finger's mid-drag, then the one the drag ended on until the app next says, the app's otherwise. */
    fun shown(app: Long): Long = drag?.now ?: settling ?: app

    companion object {
        /** The frame under [x] on a track [width] wide holding [duration] frames as equal cells, kept on the track. */
        fun frameAt(x: Double, width: Double, duration: Long): Long {
            if (duration <= 1 || width <= 0 || x.isNaN()) return 0
            val cell = floor(x / width * duration)
            if (cell <= 0) return 0
            return if (cell >= (duration - 1).toDouble()) duration - 1 else cell.toLong()
        }

        /** Where a frame's cell starts ([frame] == [duration] is the track's end). */
        fun xOfEdge(frame: Long, width: Double, duration: Long): Double =
            if (duration <= 0) 0.0 else width * minOf(frame, duration) / duration

        /** Where the playhead stands for [frame]: the middle of its cell. */
        fun xOfFrame(frame: Long, width: Double, duration: Long): Double =
            if (duration <= 0) 0.0 else width * (minOf(frame, duration - 1) + 0.5) / duration

        /** Whether moving the playhead from [old] to [new] crosses an edge of the work area [range]. */
        fun crossesEdge(old: Long, new: Long, range: LongRange?): Boolean {
            range ?: return false
            val end = range.last + 1
            return (old < range.first) != (new < range.first) || (old < end) != (new < end)
        }
    }
}

/** One transport's position (an entry of wire kind 17). */
@Immutable
data class LiveValue(val panel: String, val control: String, val position: Long)

/**
 * Transports' positions as the app moves them while playing (wire kind 17), without describing their
 * panels again. A position shows in place of the described one until the next description (wire kind
 * 13), which carries the positions itself.
 *
 * Only a transport's playhead reads it (the scrubber, in its draw phase, and the time), so a playing
 * transport redraws those and nothing else.
 */
@Stable
class LiveValues {
    private var positions by mutableStateOf<Map<Pair<String, String>, Long>>(emptyMap())

    /** The live position of the transport [control] in [panel], if one arrived since the last description. */
    fun position(panel: String, control: String): Long? = positions[panel to control]

    /** Positions that changed; written only if one did, so readers redraw only then. */
    fun apply(values: Iterable<LiveValue>) {
        val next = positions.toMutableMap()
        for (value in values) next[value.panel to value.control] = value.position
        if (next != positions) positions = next
    }

    /** The panels were described (wire kind 13): their positions are the truth again. */
    fun described() {
        if (positions.isNotEmpty()) positions = emptyMap()
    }

    companion object {
        /**
         * Wire kind 17 as JSON: a list of positions; an entry that doesn't decode is skipped.
         *
         * @throws kotlinx.serialization.SerializationException when it isn't a list at all.
         */
        fun parse(text: String): List<LiveValue> {
            val list = wireJson.parseToJsonElement(text) as? JsonArray ?: throw WireException("not a list")
            return list.decodeEach { with(it.asObject()) { LiveValue(string("panel"), string("control"), count("position")) } }
        }
    }
}
