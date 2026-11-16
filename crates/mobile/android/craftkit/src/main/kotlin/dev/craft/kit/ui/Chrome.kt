package dev.craft.kit.ui

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** A part of the app's chrome the shell draws natively (craft-mobile's `ui::Feature`). */
enum class Feature(override val wire: String) : WireName {
    Panels("panels"),
    Menus("menus"),
    Rail("rail"),
    Status("status"),
}

/**
 * What the shell sends the app about its chrome: what it draws, which panels are on screen, and the
 * commands its menus, rail and status deliver. Each encodes as the JSON craft-mobile's `Control::parse` reads.
 */
sealed interface ChromeMessage {
    /** `{"action":"shell","features":[…]}`: sent when the app starts, before the open panels. */
    data class Shell(val features: Set<Feature>) : ChromeMessage

    /** `{"action":"open_panels","open":[…]}`: the panels on screen, which the app describes. */
    data class OpenPanels(val open: Collection<String>) : ChromeMessage

    /** `{"action":"command","id":…}`: run the app's command as its menu item does. */
    data class Command(val id: String) : ChromeMessage

    /** `{"action":"shortcut","keys":"Cmd+Z"}`: for the app's own key handling to decide. */
    data class Shortcut(val keys: String) : ChromeMessage

    fun toJson(): String = buildJsonObject {
        when (val message = this@ChromeMessage) {
            is Shell -> {
                put("action", "shell")
                // In the wire order, each once.
                put("features", JsonArray(Feature.entries.filter { it in message.features }.map { JsonPrimitive(it.wire) }))
            }
            is OpenPanels -> {
                put("action", "open_panels")
                put("open", JsonArray(message.open.sorted().map(::JsonPrimitive)))
            }
            is Command -> {
                put("action", "command")
                put("id", message.id)
            }
            is Shortcut -> {
                put("action", "shortcut")
                put("keys", message.keys)
            }
        }
    }.toString()
}
