package dev.craft.kit.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performMouseInput
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PopoverTest {
    @get:Rule
    val compose = createComposeRule()

    private var open by mutableStateOf(true)

    private fun showBrush() {
        compose.setContent {
            MaterialTheme {
                if (open) CraftPopover(PopoverSide.Below, onDismiss = { open = false }, title = "Brush") { Text("Size") }
            }
        }
        compose.onNodeWithText("Brush").assertExists()
        compose.onNodeWithText("Size").assertExists()
    }

    /** The header's Close button closes the popover, as the inspector's side sheet's does. */
    @Test
    fun closeClosesIt() {
        showBrush()
        compose.onNodeWithContentDescription("Close Brush").performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Size").assertDoesNotExist()
    }

    /** Back still closes it. */
    @Test
    fun backClosesIt() {
        showBrush()
        Espresso.pressBackUnconditionally()
        compose.waitForIdle()
        compose.onNodeWithText("Size").assertDoesNotExist()
    }

    /** With a mouse, Close names itself in a tooltip on hover. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun closeSaysWhatItIsOnHover() {
        showBrush()
        compose.onNodeWithContentDescription("Close Brush").performMouseInput { moveTo(center) }
        compose.waitUntil(timeoutMillis = 3_000) { compose.onAllNodesWithText("Close").fetchSemanticsNodes().isNotEmpty() }
    }

    @Test
    fun withoutATitleItIsStillClosable() {
        compose.setContent {
            MaterialTheme {
                if (open) CraftPopover(PopoverSide.End, onDismiss = { open = false }) { Text("Size") }
            }
        }
        compose.onNodeWithContentDescription("Close").performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Size").assertDoesNotExist()
    }
}
