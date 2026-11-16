package dev.craft.kit.ui

import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorPath
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class CraftIconsTest {
    /** Each mapped name draws a 24dp Material Symbol in both styles, from its 960-unit SVG box. */
    @Test
    fun everySymbolDrawsInBothStyles() {
        assertTrue(CraftIcons.symbols.size > 60)
        for (symbol in CraftIcons.symbols) {
            for (filled in listOf(false, true)) {
                val icon = CraftIcons.icon(symbol, filled)
                assertNotNull("$symbol, filled $filled", icon)
                icon!!
                assertEquals(24.dp, icon.defaultWidth)
                assertEquals(960f, icon.viewportWidth)
                val group = icon.root.single() as VectorGroup
                assertEquals("the SVG's box starts at y = -960", 960f, group.translationY)
                assertTrue("$symbol has a path", (group.single() as VectorPath).pathData.isNotEmpty())
            }
        }
    }

    /** A selected tool shows the filled style, which is another drawing. */
    @Test
    fun theFilledStyleIsFilled() {
        assertTrue(CraftIcons.icon("paintbrush.pointed", filled = true) !== CraftIcons.icon("paintbrush.pointed"))
        assertEquals("brush_fill1", CraftIcons.icon("paintbrush.pointed", filled = true)?.name)
        assertEquals("brush", CraftIcons.icon("paintbrush.pointed")?.name)
    }

    @Test
    fun anUnknownSymbolHasNoIcon() {
        assertNull(CraftIcons.icon("no.such.symbol"))
    }

    /** Every SF Symbol the catalogue's examples name has an icon, so the Gallery shows none as a letter. */
    @Test
    fun theCataloguesSymbolsAllHaveIcons() {
        val text = File(System.getProperty("craft.catalogue") ?: "../../catalogue/ui.json").readText()
        val named = Regex("\"(?:icon|symbol)\":\\s*\"([^\"]+)\"").findAll(text).map { it.groupValues[1] }.toSet()
        assertTrue(named.isNotEmpty())
        assertEquals(emptySet<String>(), named - CraftIcons.symbols)
    }
}
