package dev.craft.kit.ui

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.SerializationException

/**
 * The app's native chrome as the shell shows it: its panels, menus, status and live positions, and
 * the way back for edits and commands. Each part is its own state, so a view redraws only for the
 * part it reads: the panel buttons read [panels] (which changes when the panels offered do), an
 * open panel reads [open], and only a transport's playhead reads [live].
 *
 * Feed it the app's requests with [receive] on the main thread ([decode] them anywhere first).
 * [send] delivers messages to the app: craftkit's host passes them to `CraftNative.action`; the
 * Gallery plays the app itself.
 */
@Stable
class CraftUi(private val send: (String) -> Unit) {
    /** Every panel the app offers (wire kind 13's `panels`). */
    var panels: List<PanelInfo> by mutableStateOf(emptyList())
        private set

    /** The open panels, described, by id (wire kind 13's `open`): changes as often as once a frame while a control is dragged. */
    var open: Map<String, Panel> by mutableStateOf(emptyMap())
        private set

    /**
     * How many descriptions have arrived, changed or not: a refused edit is answered with the panels
     * again, unchanged, and a number control that ended a drag waits for exactly that.
     */
    var descriptions: Long by mutableLongStateOf(0)
        private set

    /** Whether the app has described its panels since the shell last said which are on screen. */
    var describedSinceShowing: Boolean by mutableStateOf(false)
        private set

    /** The app's menus (wire kind 15). */
    var menus: MenuBar by mutableStateOf(MenuBar())
        private set

    /** What the app is telling the user (wire kind 16). */
    var status: Status by mutableStateOf(Status())
        private set

    /** The transports' positions while they play (wire kind 17). */
    val live = LiveValues()

    /** A panel the app asked to open (wire kind 14), until the shell opened it and called [openRequestHandled]. */
    var openRequest: OpenRequest? by mutableStateOf(null)
        private set

    private var openRequests = 0L

    /** What the shell draws itself, said to the app each time it starts. Set before the app starts. */
    var features: Set<Feature> = emptySet()

    private var shown: Set<String> = emptySet()

    /** One of the app's requests, decoded off the main thread. */
    sealed interface Request {
        data class Described(val panels: Panels) : Request

        data class Open(val id: String) : Request

        data class Menus(val bar: MenuBar) : Request

        data class Said(val status: Status) : Request

        data class Live(val values: List<LiveValue>) : Request
    }

    /** A request to open the panel [id]; [serial] tells two requests for the same panel apart. */
    data class OpenRequest(val id: String, val serial: Long)

    companion object {
        /** Wire kinds 13 to 17. */
        val kinds: IntRange = 13..17

        /**
         * Decode the app's request [kind] with [text]; `null` for a kind this isn't, and for one that
         * doesn't decode (the shell keeps what it had).
         */
        fun decode(kind: Int, text: String): Request? = try {
            when (kind) {
                13 -> Request.Described(Panels.parse(text))
                14 -> Request.Open(text)
                15 -> Request.Menus(MenuBar.parse(text))
                16 -> Request.Said(Status.parse(text))
                17 -> Request.Live(LiveValues.parse(text))
                else -> null
            }
        } catch (_: SerializationException) {
            null
        }
    }

    /** Apply a decoded request (main thread). */
    fun receive(request: Request) {
        when (request) {
            is Request.Described -> {
                if (request.panels.panels != panels) panels = request.panels.panels
                if (request.panels.open != open) open = request.panels.open
                // The description carries the positions; live ones give way to it.
                live.described()
                descriptions += 1
                if (!describedSinceShowing) describedSinceShowing = true
            }
            is Request.Open -> {
                openRequests += 1
                openRequest = OpenRequest(request.id, openRequests)
            }
            is Request.Menus -> if (request.bar != menus) menus = request.bar
            is Request.Said -> if (request.status != status) status = request.status
            is Request.Live -> live.apply(request.values)
        }
    }

    /** The shell dealt with [openRequest]. */
    fun openRequestHandled() {
        openRequest = null
    }

    /** Deliver an edit from a native panel to the app. Only for the user's own gestures. */
    fun send(edit: Edit) = send(edit.toJson())

    /** Run one of the app's commands as its menu item does (a menu, the rail, Cancel). */
    fun command(id: String) = send(ChromeMessage.Command(id).toJson())

    /** The panels on screen now, by id; only they are described. Call whenever the set changes. */
    fun showing(ids: Set<String>) {
        shown = ids
        describedSinceShowing = false
        send(ChromeMessage.OpenPanels(ids).toJson())
    }

    /** The app started: tell it what the shell draws, then which panels are on screen, in case it wasn't there to hear. */
    fun started() {
        send(ChromeMessage.Shell(features).toJson())
        send(ChromeMessage.OpenPanels(shown).toJson())
    }
}
