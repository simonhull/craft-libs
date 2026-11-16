package dev.craft.kit.ui

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The generated catalogue (`crates/mobile/catalogue/ui.json`) is the wire format: every example
 * decodes here, and every edit and message this kit sends encodes as the catalogue says Rust reads it.
 */
class CatalogueTest {
    private val catalogue: JsonObject = Json.parseToJsonElement(File(System.getProperty("craft.catalogue") ?: "../../catalogue/ui.json").readText()).jsonObject
    private val primitives = catalogue.getValue("primitives").jsonArray.map { it.jsonObject }
    private val chrome = catalogue.getValue("chrome").jsonArray.map { it.jsonObject }

    private fun primitive(name: String) = primitives.first { it.str("name") == name }

    private fun chrome(name: String) = chrome.first { it.str("name") == name }

    @Test
    fun everyPrimitiveIsOneThisKitDraws() {
        assertEquals(1, catalogue.getValue("version").jsonPrimitive.content.toInt())
        assertEquals(listOf("number", "toggle", "choice", "section", "item_list", "tool_palette", "transport"), primitives.map { it.str("name") })
        assertEquals(Node.knownTypes, primitives.map { it.str("name") }.toSet())
    }

    @Test
    fun everyExampleDecodesAsItsOwnNode() {
        for (entry in primitives) {
            val node = Node.decode(entry.getValue("example"))
            assertFalse("${entry.str("name")}: $node", node is Node.Unknown || node is Node.Malformed)
        }
    }

    @Test
    fun theExamplesDecodeToTheirValues() {
        assertEquals(
            Node.Number("size", "Size", 24.0, 1.0, 5000.0, 1.0, NumberUnit.Pixels, enabled = true, scale = Scale.Log),
            decode("number"),
        )
        assertEquals(Node.Toggle("visible", "Visible", value = true, enabled = true), decode("toggle"))
        assertEquals(
            Node.Choice("blend", "Blend Mode", "normal", listOf(ChoiceOption("normal", "Normal"), ChoiceOption("multiply", "Multiply"), ChoiceOption("screen", "Screen")), true),
            decode("choice"),
        )
        assertEquals(Node.Section("layer", "Layer", false, listOf(Node.Toggle("locked", "Lock", value = false, enabled = true))), decode("section"))
        val actions = listOf(ItemAction("duplicate", "Duplicate", "plus.square.on.square"), ItemAction("delete", "Delete", "trash", destructive = true))
        assertEquals(
            Node.ItemList(
                "layers",
                listOf(Row(2, "Sky", "Pixel", 0, true, true, actions), Row(1, "Background", "Pixel", 0, true, false, actions)),
                reorderable = true,
                actions = listOf(ItemAction("new_layer", "New Layer", "plus")),
            ),
            decode("item_list"),
        )
        assertEquals(
            ToolPalette(
                "palette",
                listOf(
                    ToolSlot(listOf(Tool("move", "Move", ToolIcon("arrow.up.and.down.and.arrow.left.and.right", "V"), "V"))),
                    ToolSlot(listOf(Tool("brush", "Brush", ToolIcon("paintbrush.pointed", "B"), "B"), Tool("pencil", "Pencil", ToolIcon("pencil", "N"), "N"))),
                    ToolSlot(listOf(Tool("smudge", "Smudge", ToolIcon(null, "S"), null))),
                ),
                selected = "brush",
                options = "brush",
                fallbackOptions = "window.toggle.optionsBar",
            ),
            decode("tool_palette"),
        )
        assertEquals(Transport.of("transport", 11, 30, 24.0, range = 0L until 24), decode("transport"))
    }

    private fun decode(name: String) = Node.decode(primitive(name).getValue("example"))

    /** The catalogue's sample edits are what Rust parses; [Edit] must encode the same JSON. */
    @Test
    fun editsEncodeAsTheCatalogueSays() {
        val expected = mapOf(
            "number" to Edit("brush", "size", Phase.Change, 7, EditValue.Number(120.0)),
            "toggle" to Edit("layers", "visible", Phase.Commit, 8, EditValue.Toggle(false)),
            "choice" to Edit("layers", "blend", Phase.Commit, 9, EditValue.Choice("multiply")),
            "item_list" to Edit("layers", "layers", Phase.Commit, 10, EditValue.Move(1, 2, Position.Above)),
            "tool_palette" to Edit("tools", "palette", Phase.Commit, 11, EditValue.Choice("pencil")),
            "transport" to Edit("timeline", "transport", Phase.Change, 12, EditValue.Seek(12)),
        )
        var checked = 0
        for (entry in primitives) {
            val sample = entry["edit"]?.takeUnless { it is JsonNull } ?: continue
            val edit = expected[entry.str("name")] ?: error("no Kotlin edit for the catalogue's ${entry.str("name")} sample")
            assertJsonEquals(entry.str("name"), sample, Json.parseToJsonElement(edit.toJson()))
            checked += 1
        }
        assertEquals(expected.size, checked)
    }

    /** The examples in the catalogue's prose (`sends`), one per kind of value. */
    @Test
    fun everyKindOfEditEncodesAsRustReadsIt() {
        val cases = listOf(
            EditValue.Select(2) to """{"kind":"select","value":{"row":2,"mode":"replace"}}""",
            EditValue.Select(2, SelectMode.Toggle) to """{"kind":"select","value":{"row":2,"mode":"toggle"}}""",
            EditValue.Select(2, SelectMode.Range) to """{"kind":"select","value":{"row":2,"mode":"range"}}""",
            EditValue.SetVisible(2, false) to """{"kind":"set_visible","value":{"row":2,"visible":false}}""",
            EditValue.Rename(4, "Sky") to """{"kind":"rename","value":{"row":4,"name":"Sky"}}""",
            EditValue.Move(4, 9, Position.Below) to """{"kind":"move","value":{"row":4,"target":9,"position":"below"}}""",
            EditValue.Action(2, "delete") to """{"kind":"action","value":{"row":2,"action":"delete"}}""",
            EditValue.ListAction("new_layer") to """{"kind":"list_action","value":{"action":"new_layer"}}""",
            EditValue.Seek(12) to """{"kind":"seek","value":{"frame":12}}""",
        ) + TransportAction.entries.map { EditValue.Transport(it) to """{"kind":"transport","value":"${it.wire}"}""" }
        for ((value, json) in cases) {
            val edit = Edit("layers", "rows", Phase.Commit, 1, value)
            val expected = """{"action":"edit","panel":"layers","control":"rows","phase":"commit","gesture":1,"value":$json}"""
            assertJsonEquals("$value", Json.parseToJsonElement(expected), Json.parseToJsonElement(edit.toJson()))
        }
        assertEquals(listOf("play", "pause", "stop", "step_back", "step_forward", "to_start", "to_end"), TransportAction.entries.map { it.wire })
        assertEquals(listOf("begin", "change", "commit", "cancel"), Phase.entries.map { it.wire })
    }

    /** The wire section's own example: the panels and the open one described. */
    @Test
    fun theWireExampleDecodes() {
        val json = """
            {"panels":[{"id":"layers","title":"Layers","icon":"square.3.layers.3d","role":"inspector"},
                       {"id":"brush","title":"Brush","icon":"paintbrush.pointed","role":"tool"}],
             "open":{"layers":{"id":"layers","title":"Layers","role":"inspector",
                     "nodes":[{"type":"toggle","id":"visible","label":"Visible","value":true,"enabled":true}]}}}
        """
        val panels = Panels.parse(json)
        assertEquals(listOf(PanelRole.Inspector, PanelRole.Tool), panels.panels.map { it.role })
        assertEquals(listOf(Node.Toggle("visible", "Visible", value = true, enabled = true)), panels.open["layers"]?.nodes)
    }

    @Test
    fun chromeMessagesEncodeAsTheCatalogueSays() {
        assertJsonEquals(
            "shell",
            Json.parseToJsonElement("""{"action":"shell","features":["panels","menus","rail","status"]}"""),
            Json.parseToJsonElement(ChromeMessage.Shell(Feature.entries.reversed().toSet()).toJson()),
        )
        assertEquals("""{"action":"open_panels","open":["layers"]}""", ChromeMessage.OpenPanels(listOf("layers")).toJson())
        assertEquals("""{"action":"command","id":"image.flip_horizontal"}""", ChromeMessage.Command("image.flip_horizontal").toJson())
        assertEquals("""{"action":"shortcut","keys":"Cmd+Z"}""", ChromeMessage.Shortcut("Cmd+Z").toJson())
        // The catalogue lists the messages each piece of chrome sends; this kit sends the same.
        val sent = chrome.flatMap { entry -> entry["messages"]?.jsonArray.orEmpty().map { it.jsonObject } }
        assertTrue("the catalogue lists chrome messages", sent.isNotEmpty())
        for (message in sent) {
            val encoded = when (message.str("action")) {
                "command" -> ChromeMessage.Command(message.str("id")).toJson()
                "shortcut" -> ChromeMessage.Shortcut(message.str("keys")).toJson()
                else -> error("a chrome message this kit doesn't send: $message")
            }
            assertJsonEquals("$message", message, Json.parseToJsonElement(encoded))
        }
    }

    @Test
    fun theMenuBarExampleDecodes() {
        val bar = MenuBar.parse(chrome("menu_bar").getValue("example").toString())
        assertEquals(listOf("Edit", "View", "Layer"), bar.menus.map { it.title })
        assertEquals(listOf(MenuRole.Edit, MenuRole.View, null), bar.menus.map { it.role })
        val edit = bar.menus.first().items
        assertEquals(MenuEntry.Command(MenuCommand("edit.undo", "Undo", Shortcut("Z", cmd = true), enabled = true, checked = null)), edit[0])
        assertEquals(MenuEntry.Separator, edit[2])
        assertEquals(
            MenuEntry.Submenu("Transform", listOf(MenuEntry.Command(MenuCommand("image.flip_horizontal", "Flip Horizontal")))),
            edit[3],
        )
        assertEquals(false, bar.commands.getValue("edit.redo").enabled)
        assertEquals(true, bar.commands.getValue("view.rulers").checked)
        assertEquals("Ctrl+Shift+Z", bar.commands.getValue("edit.redo").shortcut?.label)
    }

    @Test
    fun theStatusExampleDecodes() {
        val status = Status.parse(chrome("status").getValue("example").toString())
        assertEquals(
            Status(Status.Message("Couldn't open b.psd: not a Photoshop file", Tone.Error, 7), Status.Progress("Exporting a.png", 0.4, "job.cancel")),
            status,
        )
    }

    /** Shortcuts parse exactly as craft-mobile's `Shortcut::parse` does: the catalogue's cases. */
    @Test
    fun shortcutsParseAsRustDoes() {
        val shortcuts = catalogue.getValue("shortcuts").jsonObject
        assertEquals(shortcuts.getValue("named_keys").jsonArray.map { it.jsonPrimitive.content }.toSet(), Shortcut.namedKeys)
        val cases = shortcuts.getValue("cases").jsonArray.map { it.jsonObject }
        assertTrue(cases.size > 10)
        for (case in cases) {
            val text = case.str("text")
            val parsed = (case["parsed"] as? JsonPrimitive)?.takeIf { it.isString }?.content
            assertEquals("`$text`", parsed, Shortcut.parse(text)?.text)
        }
    }

    private fun JsonObject.str(key: String) = getValue(key).jsonPrimitive.content
}

/** JSON equal as values: numbers by value (`120` is `120.0`), a bool never a number, objects by key. */
fun assertJsonEquals(message: String, expected: JsonElement, actual: JsonElement) {
    fun same(a: JsonElement, b: JsonElement): Boolean = when {
        a is JsonObject && b is JsonObject -> a.keys == b.keys && a.keys.all { same(a.getValue(it), b.getValue(it)) }
        a is JsonArray && b is JsonArray -> a.size == b.size && a.indices.all { same(a[it], b[it]) }
        a is JsonNull || b is JsonNull -> a == b
        a is JsonPrimitive && b is JsonPrimitive -> when {
            a.isString || b.isString -> a.isString == b.isString && a.content == b.content
            a.booleanOrNull != null || b.booleanOrNull != null -> a.booleanOrNull == b.booleanOrNull
            else -> a.doubleOrNull == b.doubleOrNull
        }
        else -> false
    }
    assertTrue("$message: expected $expected, got $actual", same(expected, actual))
}
