package dev.craft.kit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NativeChromeTest {
    /** The inspector and a tool's popover share the trailing edge: opening one closes the other. */
    @Test
    fun aToolPanelReplacesTheOpenInspector() {
        val shell = NativeChrome()
        shell.openInspector("layers")
        shell.openPopover("brush")
        assertEquals("brush", shell.popover)
        assertNull("Layers mustn't peek out behind Brush", shell.inspector)
    }

    @Test
    fun anInspectorReplacesTheOpenToolPanel() {
        val shell = NativeChrome()
        shell.openPopover("brush")
        shell.openInspector("layers")
        assertEquals("layers", shell.inspector)
        assertNull(shell.popover)
    }

    @Test
    fun closingOneLeavesTheOtherAsItWas() {
        val shell = NativeChrome(inspector = "layers")
        shell.openPopover(null)
        assertEquals("layers", shell.inspector)
        shell.openInspector(null)
        assertNull(shell.inspector)
    }

    @Test
    fun theRailsOptionsAreAtTheOtherEdgeAndStay() {
        val shell = NativeChrome(railOptions = "brush.options")
        shell.openInspector("layers")
        shell.openPopover("brush")
        assertEquals("brush.options", shell.railOptions)
    }
}
