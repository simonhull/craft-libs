package dev.craft.kit.ui

import androidx.compose.runtime.Immutable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** A tool's picture (craft-mobile's `ui::Icon`): an SF Symbol name, and a letter for when there's no such icon. */
@Immutable
data class ToolIcon(val symbol: String? = null, val letter: String? = null) {
    /** What to draw: an icon for the symbol, or a letter. */
    sealed interface Shown {
        data class Symbol(val name: String) : Shown

        data class Letter(val letter: String) : Shown
    }

    /** The symbol when [exists] says there's an icon for it, else the letter, else [label]'s first letter (upper case). */
    fun shown(label: String, exists: (String) -> Boolean = CraftIcons::has): Shown {
        symbol?.takeIf(exists)?.let { return Shown.Symbol(it) }
        letter?.takeIf { it.isNotEmpty() }?.let { return Shown.Letter(it) }
        return Shown.Letter(label.firstOrNull()?.uppercase() ?: "?")
    }
}

/** One tool of a palette (`ui::Tool`); [shortcut] in the portable form (`B`, `Shift+B`). */
@Immutable
data class Tool(val id: String, val label: String, val icon: ToolIcon, val shortcut: String? = null) {
    internal companion object {
        fun decode(element: JsonElement): Tool = with(element.asObject()) {
            val icon = (this["icon"] as? JsonObject ?: throw WireException("`icon` is missing")).let { ToolIcon(it.optString("symbol"), it.optString("letter")) }
            Tool(string("id"), string("label"), icon, optString("shortcut"))
        }
    }
}

/** One place on the rail (`ui::ToolSlot`): it shows the selected tool when it holds it, else its first. */
@Immutable
data class ToolSlot(val tools: List<Tool>) {
    /** The tool the slot shows while [selected] is the selected tool. */
    fun shown(selected: String): Tool? = tools.firstOrNull { it.id == selected } ?: tools.firstOrNull()
}

/** How a tool's options open: the app's Tool panel as a popover from the rail, or an app command. */
sealed interface RailOptions {
    data class Panel(val id: String) : RailOptions

    data class Command(val id: String) : RailOptions
}

/**
 * The app's tools (`ui::ToolPalette`), as the rail shows them. [options] names the app's Tool panel
 * with the selected tool's options; without one, [fallbackOptions] is the command that shows them.
 */
@Immutable
data class ToolPalette(
    override val id: String,
    val slots: List<ToolSlot>,
    val selected: String,
    val options: String? = null,
    val fallbackOptions: String? = null,
) : Node {
    /** The same palette with another tool selected (as the app describes it after a pick). */
    fun selecting(tool: String): ToolPalette = copy(selected = tool)

    /** The palette without its options (in a panel, which has nowhere to open them). */
    val withoutOptions: ToolPalette get() = copy(options = null, fallbackOptions = null)

    /** How the selected tool's options open, if it has any. */
    val optionsRoute: RailOptions?
        get() = options?.let(RailOptions::Panel) ?: fallbackOptions?.let(RailOptions::Command)

    /** Where [tool] sits on the rail: the index of the slot that holds it. */
    fun slotIndex(tool: String): Int? = slots.indexOfFirst { slot -> slot.tools.any { it.id == tool } }.takeIf { it >= 0 }

    /** The options a double-tap on [tool] opens now: only the selected tool's are known, so another must wait until the app selects it. */
    fun optionsNow(tool: String): RailOptions? = if (tool == selected) optionsRoute else null

    internal companion object {
        /** Lenient as the menus are: a slot or tool this kit can't read is left out (a slot left with no tools too). */
        fun decode(json: JsonObject): ToolPalette = with(json) {
            ToolPalette(
                id = string("id"),
                slots = array("slots").decodeEach { slot -> ToolSlot(slot.asObject().array("tools").decodeEach(Tool::decode)) }
                    .filter { it.tools.isNotEmpty() },
                selected = string("selected"),
                options = lenient { optString("options") },
                fallbackOptions = lenient { optString("fallback_options") },
            )
        }

        private inline fun lenient(read: () -> String?): String? = try {
            read()
        } catch (_: SerializationException) {
            null
        }
    }
}

/** The palette's first tool palette among a rail panel's nodes. */
fun Panel.toolPalette(): ToolPalette? = nodes.firstNotNullOfOrNull { it as? ToolPalette }

/**
 * Taps on the rail's tools: a tap selects; a second tap on the same tool soon after (a double-tap)
 * opens its options. A tap on the tool already selected selects nothing new.
 */
class RailTaps {
    enum class Outcome { Select, Options, Nothing }

    private var last: Pair<String, Long>? = null

    /** A tap on [tool] at [nowMillis] (monotonic), while [selected] is the selected tool. */
    fun tap(tool: String, selected: String, nowMillis: Long): Outcome {
        val previous = last
        if (previous != null && previous.first == tool && nowMillis - previous.second in 0..INTERVAL_MILLIS) {
            last = null
            return Outcome.Options
        }
        last = tool to nowMillis
        return if (tool == selected) Outcome.Nothing else Outcome.Select
    }

    companion object {
        /** How soon a second tap counts as a double-tap. */
        const val INTERVAL_MILLIS = 350L
    }
}

/**
 * Where the rail scrolls to bring the tool in slot [index] into view: centred in a [viewport]
 * (pixels) scrolled by [scrolled], with each slot [slotPx] tall; null when it's already in view,
 * or before the rail has been laid out (a zero viewport would scroll the first tool away).
 */
fun railScrollTarget(index: Int, slotPx: Float, scrolled: Int, viewport: Int): Int? {
    if (viewport <= 0) return null
    val top = (index * slotPx).toInt()
    if (top >= scrolled && top + slotPx <= scrolled + viewport) return null
    return (top - viewport / 2 + slotPx.toInt() / 2).coerceAtLeast(0)
}
