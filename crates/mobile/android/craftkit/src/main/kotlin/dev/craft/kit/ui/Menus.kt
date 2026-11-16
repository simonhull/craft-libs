package dev.craft.kit.ui

import androidx.compose.runtime.Immutable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonElement

/**
 * A keyboard shortcut in the portable form (`Cmd+Shift+Z`): modifiers, then one key. [ctrl] is the
 * Control key and [cmd] the command key (⌘ on Apple's keyboards; on Android, Ctrl or Meta, as
 * craft-mobile reads them), never folded together in the form. The key is one character (letters
 * upper case) or egui's canonical name for it (`Enter`, `ArrowUp`, `F5`).
 */
@Immutable
data class Shortcut(val key: String, val ctrl: Boolean = false, val cmd: Boolean = false, val alt: Boolean = false, val shift: Boolean = false) {
    /** The portable form, modifiers in craft-mobile's order (`Ctrl+Cmd+Alt+Shift+Key`). */
    val text: String
        get() = (listOf(ctrl to "Ctrl", cmd to "Cmd", alt to "Alt", shift to "Shift").filter { it.first }.map { it.second } + key).joinToString("+")

    /**
     * As Android shows a shortcut in a menu: `Ctrl+Shift+Z`. The command key is Ctrl here (craft-mobile
     * reads Ctrl as it); with Ctrl held too, it is Meta.
     */
    val label: String
        get() {
            val modifiers = listOf(
                (cmd || ctrl) to "Ctrl",
                (cmd && ctrl) to "Meta",
                alt to "Alt",
                shift to "Shift",
            ).filter { it.first }.map { it.second }
            return (modifiers + (keyLabels[key] ?: characters[key] ?: key)).joinToString("+")
        }

    companion object {
        /**
         * Parse the portable form exactly as craft-mobile's `Shortcut::parse` does (the catalogue's
         * shortcut cases test both); `null` for anything it refuses.
         */
        fun parse(text: String): Shortcut? {
            val (modifiers, key) = when {
                text.endsWith("++") -> text.dropLast(2) to "+"
                text == "+" -> null to "+"
                '+' in text -> text.substringBeforeLast('+') to text.substringAfterLast('+')
                else -> null to text
            }
            var shortcut = Shortcut(keyName(key) ?: return null)
            for (modifier in modifiers?.split('+').orEmpty()) {
                shortcut = when {
                    modifier == "Ctrl" && !shortcut.ctrl -> shortcut.copy(ctrl = true)
                    modifier == "Cmd" && !shortcut.cmd -> shortcut.copy(cmd = true)
                    modifier == "Alt" && !shortcut.alt -> shortcut.copy(alt = true)
                    modifier == "Shift" && !shortcut.shift -> shortcut.copy(shift = true)
                    else -> return null
                }
            }
            return shortcut
        }

        /** One printable character (a letter upper-cased), or a canonical named key. */
        private fun keyName(key: String): String? {
            if (key.codePointCount(0, key.length) == 1) {
                val c = key.codePointAt(0)
                if (!Character.isWhitespace(c) && !Character.isISOControl(c)) return key.uppercase()
            }
            return key.takeIf { it in namedKeys }
        }

        /** The named keys craft-mobile prints (`ui::named_keys`, in the catalogue). */
        val namedKeys: Set<String> = setOf(
            "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowUp", "Escape", "Tab", "Backspace", "Enter", "Space", "Insert", "Delete",
            "Home", "End", "PageUp", "PageDown", "Copy", "Cut", "Paste", "Colon", "Comma", "Backslash", "Slash", "Pipe",
            "Questionmark", "Exclamationmark", "OpenBracket", "CloseBracket", "OpenCurlyBracket", "CloseCurlyBracket", "Backtick",
            "Minus", "Period", "Plus", "Equals", "Semicolon", "Quote",
            "BrowserBack", "BrowserForward", "BrowserRefresh", "BrowserSearch", "BrowserHome", "BrowserFavorites", "BrowserStop",
            "MediaPlayPause", "MediaTrackNext", "MediaTrackPrevious", "MediaStop", "AudioVolumeMute", "AudioVolumeDown", "AudioVolumeUp",
            "LaunchMail", "LaunchApp1", "LaunchApp2", "ShiftLeft", "ShiftRight", "ControlLeft", "ControlRight", "AltLeft", "AltRight",
            "SuperLeft", "SuperRight", "IntlBackslash", "CapsLock", "NumLock", "ScrollLock", "PrintScreen", "Pause", "Menu", "Fn",
            "Eject", "Help", "Power", "Sleep", "Clear",
        ) + (1..35).map { "F$it" }

        /** How a menu names a named key. */
        private val keyLabels = mapOf(
            "Enter" to "Enter", "Backspace" to "Backspace", "Delete" to "Del", "Escape" to "Esc", "PageUp" to "PgUp", "PageDown" to "PgDn",
            "ArrowUp" to "↑", "ArrowDown" to "↓", "ArrowLeft" to "←", "ArrowRight" to "→",
        )

        /** The character a named punctuation key types: `Minus` and `-` are the same key. */
        private val characters = mapOf(
            "Minus" to "-", "Equals" to "=", "Plus" to "+", "Comma" to ",", "Period" to ".", "Slash" to "/", "Backslash" to "\\",
            "Semicolon" to ";", "Colon" to ":", "Quote" to "'", "Backtick" to "`", "OpenBracket" to "[", "CloseBracket" to "]",
            "OpenCurlyBracket" to "{", "CloseCurlyBracket" to "}", "Pipe" to "|", "Questionmark" to "?", "Exclamationmark" to "!",
        )
    }
}

/** One item of a menu that runs a command (`ui::MenuCommand`); [checked] `null`: no check mark. */
@Immutable
data class MenuCommand(val id: String, val label: String, val shortcut: Shortcut? = null, val enabled: Boolean = true, val checked: Boolean? = null)

/** One entry of a menu (`ui::MenuEntry`). */
@Immutable
sealed interface MenuEntry {
    data class Command(val command: MenuCommand) : MenuEntry

    data object Separator : MenuEntry

    data class Submenu(val label: String, val items: List<MenuEntry>) : MenuEntry

    companion object {
        /** One entry; a type this kit doesn't know, or a broken one, throws (its menu skips it). */
        internal fun decode(element: JsonElement): MenuEntry = with(element.asObject()) {
            when (val type = string("type")) {
                "command" -> Command(
                    MenuCommand(
                        id = string("id"),
                        label = string("label"),
                        // One this kit can't read shows as none.
                        shortcut = optString("shortcut")?.let(Shortcut::parse),
                        enabled = bool("enabled"),
                        checked = optBool("checked"),
                    ),
                )
                "separator" -> Separator
                "submenu" -> Submenu(string("label"), array("items").decodeEach(::decode))
                else -> throw WireException("unknown menu entry $type")
            }
        }
    }
}

/** The system menu an app menu takes the place of (`ui::MenuRole`), matched by role, never by its title. */
enum class MenuRole(override val wire: String) : WireName {
    File("file"),
    Edit("edit"),
    View("view"),
    Window("window"),
    Help("help"),
}

/** One menu of the bar (`ui::Menu`); [role] `null` for a menu of the app's own. */
@Immutable
data class Menu(val title: String, val role: MenuRole? = null, val items: List<MenuEntry>)

/** The app's menu bar (wire kind 15, `ui::MenuBar`). An entry or menu this kit can't read is left out. */
@Immutable
data class MenuBar(val menus: List<Menu> = emptyList()) {
    /** Every command, by id (the first, should one repeat). */
    val commands: Map<String, MenuCommand>
        get() = buildMap {
            fun walk(items: List<MenuEntry>) {
                for (item in items) {
                    when (item) {
                        is MenuEntry.Command -> putIfAbsent(item.command.id, item.command)
                        is MenuEntry.Submenu -> walk(item.items)
                        MenuEntry.Separator -> Unit
                    }
                }
            }
            menus.forEach { walk(it.items) }
        }

    companion object {
        /**
         * Wire kind 15 as JSON.
         *
         * @throws SerializationException when it isn't JSON or has no `menus`.
         */
        fun parse(text: String): MenuBar = MenuBar(
            parseObject(text).array("menus").decodeEach { element ->
                with(element.asObject()) {
                    val role = runCatching { optString("role") }.getOrNull()?.let { name -> MenuRole.entries.firstOrNull { it.wire == name } }
                    Menu(string("title"), role, array("items").decodeEach(MenuEntry::decode))
                }
            },
        )
    }
}
