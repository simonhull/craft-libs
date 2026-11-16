package dev.craft.kit.ui

import androidx.compose.runtime.Immutable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Where a panel shows (craft-mobile's `ui::PanelRole`): `inspector` beside the canvas, `tool` as a
 * popover from its button, `rail` the tool rail at the canvas's leading edge (its tool palette),
 * `transport` a floating bar above the bottom of the canvas (its transport).
 */
enum class PanelRole(override val wire: String) : WireName {
    Inspector("inspector"),
    Tool("tool"),
    Rail("rail"),
    Transport("transport"),
}

/** A panel the app offers (`ui::PanelInfo`); [icon] is an SF Symbol name ([CraftIcons] maps it). */
@Immutable
data class PanelInfo(val id: String, val title: String, val icon: String, val role: PanelRole) {
    /**
     * What TalkBack calls the panel's button: its title, else its icon's name in words
     * (`square.3.layers.3d`: "square 3 layers 3d"), else its id. Never empty.
     */
    val accessibilityName: String
        get() = title.trim().ifEmpty { icon.split('.').joinToString(" ").ifEmpty { id } }

    internal companion object {
        fun decode(element: JsonElement): PanelInfo = with(element.asObject()) {
            PanelInfo(string("id"), string("title"), string("icon"), strictEnum(string("role")))
        }
    }
}

/** One panel's contents (`ui::Panel`). */
@Immutable
data class Panel(val id: String, val title: String, val role: PanelRole, val nodes: List<Node>) {
    internal companion object {
        fun decode(element: JsonElement): Panel = with(element.asObject()) {
            Panel(string("id"), string("title"), strictEnum(string("role")), Node.decodeEach(array("nodes")))
        }
    }
}

/**
 * Everything the app sent (wire kind 13): its panels, and the open ones described, by id. A panel
 * this kit can't show (a role it doesn't know, or an entry that doesn't decode) is left out, in
 * [panels] and in [open] alike; the others still show.
 */
@Immutable
data class Panels(val panels: List<PanelInfo> = emptyList(), val open: Map<String, Panel> = emptyMap()) {
    companion object {
        /**
         * Wire kind 13 as JSON.
         *
         * @throws SerializationException when it isn't JSON, or lacks `panels` or `open`.
         */
        fun parse(text: String): Panels = with(parseObject(text)) {
            val open = optObject("open")
            Panels(
                panels = array("panels").decodeEach(PanelInfo::decode),
                open = open.entries.mapNotNull { (id, panel) -> runCatching { id to Panel.decode(panel) }.getOrNull() }.toMap(),
            )
        }

        private fun JsonObject.optObject(key: String): JsonObject = this[key] as? JsonObject ?: throw WireException("`$key` is missing")
    }
}

/** One option of a [Node.Choice]. */
@Immutable
data class ChoiceOption(val id: String, val label: String)

/**
 * Something the user can do in an item list (`ui::ItemAction`), to one row or to the list itself.
 * A row's shows in its long-press menu after Rename, and as a swipe action too when [destructive];
 * the list's own (New Layer) is a button in the list's footer, named by [label].
 */
@Immutable
data class ItemAction(val id: String, val label: String, val icon: String? = null, val destructive: Boolean = false) {
    internal companion object {
        fun decode(element: JsonElement): ItemAction = with(element.asObject()) {
            ItemAction(string("id"), string("label"), optString("icon"), optBool("destructive") ?: false)
        }
    }
}

/** Whether the user can rename a row (`ui::Rename`). Left out, or a value this kit doesn't know, it can. */
enum class Rename(override val wire: String) : WireName {
    Allowed("allowed"),
    No("no"),
}

/** One row of a [Node.ItemList]; [id] is the app's own (a layer id). [visible] `null`: it can't be hidden. */
@Immutable
data class Row(
    val id: Long,
    val title: String,
    val subtitle: String = "",
    val depth: Int = 0,
    val visible: Boolean? = null,
    val selected: Boolean = false,
    val actions: List<ItemAction> = emptyList(),
    val rename: Rename = Rename.Allowed,
) {
    internal companion object {
        fun decode(element: JsonElement): Row = with(element.asObject()) {
            Row(
                id = count("id"),
                title = string("title"),
                subtitle = string("subtitle"),
                depth = count("depth").coerceAtMost(MAX_DEPTH.toLong()).toInt(),
                visible = optBool("visible"),
                selected = bool("selected"),
                actions = optArray("actions")?.decodeEach(ItemAction::decode).orEmpty(),
                rename = lenientEnum(optString("rename"), Rename.Allowed),
            )
        }

        /** Deeper than this indents no further: a row must stay readable in a narrow panel. */
        const val MAX_DEPTH = 16
    }
}

/** What a number measures; the view formats it. A unit this kit doesn't know shows as [None]. */
enum class NumberUnit(override val wire: String) : WireName {
    None("none"),
    Percent("percent"),
    Pixels("pixels"),
    Degrees("degrees"),
}

/**
 * How a number's slider spreads its range: [Log] by ratio (`min·(max/min)^t`), for a wide range
 * such as a brush size. Missing, or one this kit doesn't know, is [Linear].
 */
enum class Scale(override val wire: String) : WireName {
    Linear("linear"),
    Log("log"),
}

/**
 * One primitive (`ui::Node`). In a list of nodes, a type this kit doesn't know becomes [Unknown] and
 * a known one that doesn't decode [Malformed]: one bad node never takes the panel down with it.
 */
@Immutable
sealed interface Node {
    /** The node's id, unique in its panel (placeholders use their type). */
    val id: String

    /**
     * A titled group. [collapsed] is only how it starts: after it first appears, collapsing is the
     * user's, until the panel's views are built again.
     */
    data class Section(override val id: String, val title: String, val collapsed: Boolean, val children: List<Node>) : Node

    /** A value in [min]..[max]: a slider, the value beside it; tap the value to type one. */
    data class Number(
        override val id: String,
        val label: String,
        val value: Double,
        val min: Double,
        val max: Double,
        val step: Double?,
        val unit: NumberUnit,
        val enabled: Boolean,
        val scale: Scale = Scale.Linear,
    ) : Node {
        /** The range, never inverted: the app checks `min <= max`, but a bad one must not trap here. */
        val range: ClosedFloatingPointRange<Double> get() = if (min <= max) min..max else min..min
    }

    data class Toggle(override val id: String, val label: String, val value: Boolean, val enabled: Boolean) : Node

    data class Choice(override val id: String, val label: String, val value: String, val options: List<ChoiceOption>, val enabled: Boolean) : Node

    /** Rows such as layers; [actions] are the list's own (its footer's buttons), not a row's. */
    data class ItemList(override val id: String, val rows: List<Row>, val reorderable: Boolean, val actions: List<ItemAction> = emptyList()) : Node

    /** A type this kit doesn't know (the app is newer). */
    data class Unknown(val type: String) : Node {
        override val id: String get() = "unknown-$type"
    }

    /** A known type that didn't decode (the app sent it wrong). */
    data class Malformed(val type: String) : Node {
        override val id: String get() = "malformed-$type"
    }

    companion object {
        /** The `type`s this kit draws. */
        val knownTypes: Set<String> = setOf("section", "number", "toggle", "choice", "item_list", "tool_palette", "transport")

        /** One node; a type this kit doesn't know is [Unknown], and a known one that doesn't decode throws. */
        fun decode(element: JsonElement): Node = with(element.asObject()) {
            when (val type = string("type")) {
                "section" -> Section(string("id"), string("title"), bool("collapsed"), decodeEach(array("children")))
                "number" -> Number(
                    id = string("id"),
                    label = string("label"),
                    value = double("value"),
                    min = double("min"),
                    max = double("max"),
                    step = optDouble("step"),
                    unit = lenientEnum(string("unit"), NumberUnit.None),
                    enabled = bool("enabled"),
                    scale = lenientEnum(optString("scale"), Scale.Linear),
                )
                "toggle" -> Toggle(string("id"), string("label"), bool("value"), bool("enabled"))
                "choice" -> Choice(
                    string("id"),
                    string("label"),
                    string("value"),
                    array("options").map { option -> with(option.asObject()) { ChoiceOption(string("id"), string("label")) } },
                    bool("enabled"),
                )
                "item_list" -> ItemList(
                    id = string("id"),
                    rows = array("rows").map(Row::decode),
                    reorderable = bool("reorderable"),
                    // Left out (an older app) or not a list: none. One action that doesn't decode is skipped.
                    actions = (this["actions"] as? JsonArray)?.decodeEach(ItemAction::decode).orEmpty(),
                )
                "tool_palette" -> ToolPalette.decode(this)
                "transport" -> Transport.decode(this)
                else -> Unknown(type)
            }
        }

        /**
         * A list of nodes, each decoded on its own: one that fails becomes [Malformed] (a known type)
         * or [Unknown] (with its `type`, empty if it has none) instead of failing the list.
         */
        fun decodeEach(nodes: JsonArray): List<Node> = nodes.map { element ->
            try {
                decode(element)
            } catch (_: SerializationException) {
                placeholder(element)
            } catch (_: IllegalArgumentException) {
                placeholder(element)
            }
        }

        private fun placeholder(element: JsonElement): Node {
            val type = ((element as? JsonObject)?.get("type") as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()
            return if (type in knownTypes) Malformed(type) else Unknown(type)
        }

        /**
         * Each node with a key unique among its siblings: its id, and `#n` for the n-th repeat. The app
         * keeps ids unique, but placeholders share theirs, and a repeat mustn't take another's state.
         */
        fun keyed(nodes: List<Node>): List<Pair<String, Node>> {
            val seen = HashMap<String, Int>()
            return nodes.map { node ->
                val count = seen.getOrElse(node.id) { 0 }
                seen[node.id] = count + 1
                (if (count == 0) node.id else "${node.id}#$count") to node
            }
        }
    }
}
