package dev.craft.kit.ui

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Whatever the app sends, the shell shows what it can and never crashes. */
class DecodingTest {
    private fun node(json: String) = Node.decode(Json.parseToJsonElement(json))

    private fun panel(json: String) = Panel.decode(Json.parseToJsonElement(json))

    @Test
    fun anUnknownNodeBecomesAPlaceholder() {
        assertEquals(Node.Unknown("hologram"), node("""{"type":"hologram","id":"x"}"""))
    }

    /** One bad node shows as a placeholder; the rest of the panel still shows. */
    @Test
    fun aMalformedNodeBecomesAPlaceholder() {
        val json = """
            {"id":"layers","title":"Layers","role":"inspector","nodes":[
              {"type":"toggle","id":"bad","label":"No value","enabled":true},
              {"type":"section","id":"s","title":"S","collapsed":false,"children":[
                {"type":"number","id":"n","label":"No range","value":1,"unit":"none","enabled":true}, 7]},
              {"type":"toggle","id":"ok","label":"Fine","value":true,"enabled":true}]}
        """
        assertEquals(
            listOf(
                Node.Malformed("toggle"),
                Node.Section("s", "S", false, listOf(Node.Malformed("number"), Node.Unknown(""))),
                Node.Toggle("ok", "Fine", value = true, enabled = true),
            ),
            panel(json).nodes,
        )
    }

    /** A newer app's panel role, or a broken entry, drops only that panel. */
    @Test
    fun theEnvelopeSkipsPanelsItCantShow() {
        val json = """
            {"panels":[{"id":"layers","title":"Layers","icon":"square.3.layers.3d","role":"inspector"},
                       {"id":"timeline","title":"Timeline","icon":"film","role":"drawer"},
                       {"id":"broken","title":"No icon","role":"tool"},
                       {"id":"brush","title":"Brush","icon":"paintbrush.pointed","role":"tool"}],
             "open":{"layers":{"id":"layers","title":"Layers","role":"inspector","nodes":[]},
                     "timeline":{"id":"timeline","title":"Timeline","role":"drawer","nodes":[]},
                     "brush":{"id":"brush","title":"Brush","role":"tool"}}}
        """
        val panels = Panels.parse(json)
        assertEquals(listOf("layers", "brush"), panels.panels.map { it.id })
        assertEquals(setOf("layers"), panels.open.keys)
    }

    @Test
    fun aNumbersScaleAndUnitDefaultLeniently() {
        fun number(extra: String) = node("""{"type":"number","id":"n","label":"N","value":2,"min":1,"max":10,"step":null,"unit":"none","enabled":true$extra}""") as Node.Number
        assertEquals(Scale.Log, number(""","scale":"log"""").scale)
        assertEquals(Scale.Linear, number("").scale)
        assertEquals(Scale.Linear, number(""","scale":"spiral"""").scale)
        assertEquals(Scale.Linear, number(""","scale":null""").scale)
        assertNull(number("").step)
        val furlongs = node("""{"type":"number","id":"n","label":"N","value":2,"min":1,"max":10,"step":1,"unit":"furlongs","enabled":true}""")
        assertEquals(NumberUnit.None, (furlongs as Node.Number).unit)
        assertEquals(Node.Malformed("number"), Node.decodeEach(Json.parseToJsonElement("""[{"type":"number","id":"n","label":"N","value":"2","min":1,"max":10,"unit":"none","enabled":true}]""") as kotlinx.serialization.json.JsonArray).single())
    }

    @Test
    fun rowsAndTheirActionsAreLenient() {
        fun list(extra: String) = node("""{"type":"item_list","id":"rows","rows":[],"reorderable":false$extra}""")
        assertEquals(Node.ItemList("rows", emptyList(), false), list(""))
        assertEquals(
            Node.ItemList("rows", emptyList(), false, listOf(ItemAction("new", "New Layer", "plus"), ItemAction("group", "New Group"))),
            list(""","actions":[{"id":"new","label":"New Layer","icon":"plus"},{"icon":"folder"},{"id":"group","label":"New Group"}]"""),
        )
        assertEquals(Node.ItemList("rows", emptyList(), false), list(""","actions":"nonsense""""))
        val row = Row.decode(
            Json.parseToJsonElement(
                """{"id":1,"title":"a","subtitle":"","depth":0,"visible":null,"selected":false,"rename":"ask_first",
                   "actions":[{"id":"close","label":"Close"},{"label":"no id"},{"id":"rm","label":"Remove","icon":"trash","destructive":true}]}""",
            ),
        )
        assertEquals(listOf(ItemAction("close", "Close"), ItemAction("rm", "Remove", "trash", destructive = true)), row.actions)
        assertEquals(Rename.Allowed, row.rename)
        assertNull(row.visible)
        val no = Row.decode(Json.parseToJsonElement("""{"id":1,"title":"a","subtitle":"","depth":0,"visible":true,"selected":false,"rename":"no"}"""))
        assertEquals(Rename.No, no.rename)
    }

    @Test
    fun aPaletteSkipsWhatItCantRead() {
        val json = """
            {"type":"tool_palette","id":"palette","selected":"move","options":null,"fallback_options":7,"slots":[
              {"tools":[{"id":"move","label":"Move","icon":{"symbol":null,"letter":"V"},"shortcut":null}]},
              {"tools":[{"id":"broken"}]},
              7,
              {"tools":[{"label":"No id"},{"id":"smudge","label":"Smudge","icon":{"symbol":null,"letter":null},"shortcut":"S"}]}]}
        """
        val palette = node(json) as ToolPalette
        assertEquals(listOf(listOf("move"), listOf("smudge")), palette.slots.map { slot -> slot.tools.map { it.id } })
        assertNull("a fallback that isn't text is none", palette.optionsRoute)
    }

    @Test
    fun aTransportDecodesLeniently() {
        fun transport(fields: String) = node("""{"type":"transport","id":"transport",$fields}""")
        val every = transport(""""position":3,"duration":100,"rate":29.97,"format":"timecode","playing":true,"range":[10,20],"enabled":false""") as Transport
        assertEquals(listOf(3L, 100L), listOf(every.position, every.duration))
        assertEquals(TimeFormat.Timecode, every.format)
        assertEquals(10L until 20, every.range)
        assertTrue(every.playing && !every.enabled)
        val base = """"position":0,"duration":30,"rate":24,"playing":false"""
        val bare = transport(base) as Transport
        assertEquals(TimeFormat.Frames, bare.format)
        assertNull(bare.range)
        assertTrue(bare.enabled)
        assertEquals(TimeFormat.Frames, (transport("""$base,"format":"bars_beats"""") as Transport).format)
        for (range in listOf("null", "[5,5]", "[9,3]", "[1]", "\"all\"", "[30,40]")) {
            assertNull(range, (transport("""$base,"range":$range""") as Transport).range)
        }
        assertEquals(20L until 30, (transport("""$base,"range":[20,40]""") as Transport).range)
        assertEquals(29L, (transport(""""position":99,"duration":30,"rate":24,"playing":false""") as Transport).position)
        // What can't be shown is a placeholder.
        val bad = listOf(
            """{"type":"transport","id":"a","position":0,"duration":0,"rate":24,"playing":false}""",
            """{"type":"transport","id":"b","position":0,"duration":30,"rate":0,"playing":false}""",
            """{"type":"transport","id":"c","position":0,"duration":30,"rate":-24,"playing":false}""",
            """{"type":"transport","id":"d","position":0,"duration":30,"playing":false}""",
            """{"type":"transport","id":"e","position":-1,"duration":30,"rate":24,"playing":false}""",
        )
        assertEquals(List(bad.size) { Node.Malformed("transport") }, Node.decodeEach(Json.parseToJsonElement(bad.joinToString(",", "[", "]")) as kotlinx.serialization.json.JsonArray))
    }

    @Test
    fun menusSkipWhatTheyCantRead() {
        val bar = MenuBar.parse(
            """{"menus":[{"title":"File","role":"file","items":[
                {"type":"command","id":"a","label":"A","shortcut":"Hyper+A","enabled":true,"checked":null},
                {"type":"sparkle"},
                {"type":"command","label":"no id","enabled":true},
                {"type":"submenu","label":"More","items":[{"type":"separator"}]}]},
              {"title":"Mine","role":"toolbox","items":[]},
              {"role":"edit","items":[]}]}""",
        )
        assertEquals(listOf("File", "Mine"), bar.menus.map { it.title })
        assertEquals(listOf(MenuRole.File, null), bar.menus.map { it.role })
        assertEquals(
            listOf(MenuEntry.Command(MenuCommand("a", "A", null, true, null)), MenuEntry.Submenu("More", listOf(MenuEntry.Separator))),
            bar.menus.first().items,
        )
    }

    @Test
    fun statusIsLenient() {
        assertEquals(Status(), Status.parse("""{"message":null,"progress":null}"""))
        assertEquals(Status.Message("Hi", Tone.Info), Status.parse("""{"message":{"text":"Hi","tone":"cheerful"},"progress":null}""").message)
        val broken = Status.parse("""{"message":{"tone":"error"},"progress":{"label":"Exporting","fraction":null,"cancel":null}}""")
        assertNull(broken.message)
        assertEquals(Status.Progress("Exporting"), broken.progress)
    }

    @Test
    fun liveValuesSkipWhatTheyCantRead() {
        assertEquals(
            listOf(LiveValue("timeline", "transport", 12)),
            LiveValues.parse("""[{"panel":"timeline","control":"transport","position":12},{"panel":"x"},7]"""),
        )
    }

    @Test
    fun aPanelsButtonAlwaysHasAName() {
        assertEquals("Layers", PanelInfo("layers", "Layers", "square.3.layers.3d", PanelRole.Inspector).accessibilityName)
        assertEquals("square 3 layers 3d", PanelInfo("layers", "  ", "square.3.layers.3d", PanelRole.Inspector).accessibilityName)
        assertEquals("x", PanelInfo("x", "", "", PanelRole.Tool).accessibilityName)
    }

    @Test
    fun siblingsGetUniqueKeys() {
        val nodes = listOf(Node.Unknown("a"), Node.Toggle("t", "T", value = true, enabled = true), Node.Unknown("a"), Node.Unknown("a"))
        assertEquals(listOf("unknown-a", "t", "unknown-a#1", "unknown-a#2"), Node.keyed(nodes).map { it.first })
    }

    /** Requests that don't decode leave the shell as it was. */
    @Test
    fun aBrokenRequestDecodesAsNothing() {
        assertNull(CraftUi.decode(13, "not json"))
        assertNull(CraftUi.decode(15, """{"menus":7}"""))
        assertNull(CraftUi.decode(17, """{}"""))
        assertNull(CraftUi.decode(3, "{}"))
        assertEquals(CraftUi.Request.Open("layers"), CraftUi.decode(14, "layers"))
    }
}
