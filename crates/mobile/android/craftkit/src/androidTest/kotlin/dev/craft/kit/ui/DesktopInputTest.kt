package dev.craft.kit.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.InputModeManager
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performMouseInput
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.test.rightClick
import androidx.compose.ui.test.withKeyDown
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** What a mouse and a keyboard do in Android's desktop windowing: right-clicks, hover tooltips, Tab. */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class DesktopInputTest {
    @get:Rule
    val compose = createComposeRule()

    private fun node(json: String): Node = Node.decodeEach(Json.parseToJsonElement("[$json]") as JsonArray).single()

    private val palette = node(
        """{"type":"tool_palette","id":"palette","selected":"brush","options":null,"fallback_options":null,"slots":[
             {"tools":[{"id":"move","label":"Move","icon":{"symbol":"arrow.up.and.down.and.arrow.left.and.right","letter":"V"},"shortcut":"V"}]},
             {"tools":[{"id":"brush","label":"Brush","icon":{"symbol":"paintbrush.pointed","letter":"B"},"shortcut":"B"},
                       {"id":"pencil","label":"Pencil","icon":{"symbol":"pencil","letter":"N"},"shortcut":"N"}]}]}""",
    ) as ToolPalette

    private val sent = mutableListOf<Edit>()

    private fun showRail() = compose.setContent {
        MaterialTheme { CraftRail(palette, "tools", send = { sent += it }, command = {}, optionsPanel = null, onOptionsPanel = {}) }
    }

    private fun exists(text: String) = compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    /** A right-click on a slot with more tools opens its flyout, as a long press does. */
    @Test
    fun aRightClickOpensASlotsFlyout() {
        showRail()
        compose.onNodeWithContentDescription("Brush, shortcut B").performMouseInput { rightClick(center) }
        compose.waitUntil(3_000) { exists("Pencil") }
    }

    /** A right-click on a row opens its menu. */
    @Test
    fun aRightClickOpensARowsMenu() {
        val list = node(
            """{"type":"item_list","id":"layers","reorderable":false,"rows":[
                 {"id":1,"title":"Sky","subtitle":"Pixel","depth":0,"visible":true,"selected":false,"rename":"ask_first"}]}""",
        )
        compose.setContent { MaterialTheme { CraftPanelView(Panel("layers", "Layers", PanelRole.Inspector, listOf(list)), send = {}) } }
        compose.onNodeWithContentDescription("Sky, Pixel").performMouseInput { rightClick(center) }
        compose.waitUntil(3_000) { exists("Rename…") }
    }

    /** Hovering a tool names it, with its shortcut, in a tooltip; even a slot whose long press opens a flyout. */
    @Test
    fun hoverShowsAToolsNameAndShortcut() {
        showRail()
        compose.onNodeWithContentDescription("Brush, shortcut B").performMouseInput { moveTo(center) }
        compose.waitUntil(3_000) { exists(tooltipText("Brush", "B")) }
    }

    /** Tab and Shift-Tab walk the rail's tools, and Enter picks the focused one, with no pointer at all. */
    @Test
    fun tabAndEnterPickATool() {
        lateinit var inputMode: InputModeManager
        compose.setContent {
            inputMode = LocalInputModeManager.current
            MaterialTheme { CraftRail(palette, "tools", send = { sent += it }, command = {}, optionsPanel = null, onOptionsPanel = {}) }
        }
        // As a hardware keyboard's first key press does: controls take focus only out of touch mode.
        compose.runOnIdle { inputMode.requestInputMode(InputMode.Keyboard) }
        val move = compose.onNodeWithContentDescription("Move, shortcut V")
        val brush = compose.onNodeWithContentDescription("Brush, shortcut B")
        move.performSemanticsAction(SemanticsActions.RequestFocus)
        move.assertIsFocused()
        move.performKeyInput { pressKey(Key.Tab) }
        brush.assertIsFocused()
        brush.performKeyInput {
            withKeyDown(Key.ShiftLeft) { pressKey(Key.Tab) }
        }
        move.assertIsFocused()
        move.performKeyInput { pressKey(Key.Enter) }
        compose.waitForIdle()
        assertEquals(EditValue.Choice("move"), sent.single().value)
    }
}
