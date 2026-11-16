package dev.craft.kit.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.ReportProblem
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * Draws one described panel, its nodes top to bottom with the platform's controls. [send] delivers
 * edits to the app; it is called only for the user's own gestures, never when a value from the app
 * is shown. Scrolls when it doesn't fit.
 */
@Composable
fun CraftPanelView(panel: Panel, send: (Edit) -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        CraftNodes(panel.nodes, panel.id, send)
    }
}

/** [nodes], each keyed among its siblings, so a node keeps its state (a drag in progress) when others come and go. */
@Composable
internal fun CraftNodes(nodes: List<Node>, panel: String, send: (Edit) -> Unit) {
    for ((key, node) in Node.keyed(nodes)) {
        key(key) { CraftNodeView(node, panel, send) }
    }
}

@Composable
private fun CraftNodeView(node: Node, panel: String, send: (Edit) -> Unit) {
    when (node) {
        is Node.Section -> CraftSection(node.title, node.collapsed) { CraftNodes(node.children, panel, send) }
        is Node.Number -> CraftNumber(node, panel, send)
        is Node.Toggle -> CraftToggle(node, panel, send)
        is Node.Choice -> CraftChoice(node, panel, send)
        is Node.ItemList -> CraftItemList(node, panel, send)
        // In a panel, a row of the same tools; the rail itself is the shell's (`rail` role).
        is ToolPalette -> CraftRail(node.withoutOptions, panel, send, command = {}, optionsPanel = null, onOptionsPanel = {}, horizontal = true)
        // In a panel, plain; the floating bar is the shell's (`transport` role).
        is Transport -> CraftTransport(node, panel, send, style = TransportStyle.Inline)
        is Node.Unknown -> Placeholder(Icons.AutoMirrored.Outlined.HelpOutline, "Needs a newer craftkit: ${node.type}")
        is Node.Malformed -> Placeholder(Icons.Outlined.ReportProblem, "This ${node.type} couldn't be shown")
    }
}

/** A labelled placeholder for a node this kit can't draw: the rest of the panel still shows. */
@Composable
private fun Placeholder(icon: ImageVector, text: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * One of the app's panels from [ui], as described. Until the app describes it, a spinner; if it
 * answered without it (it offers the panel but can't describe it now), "Not available".
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class) // LoadingIndicator, still experimental in 1.5.
@Composable
fun CraftPanelHost(ui: CraftUi, id: String, modifier: Modifier = Modifier) {
    val panel = ui.open[id]
    if (panel != null) {
        CraftPanelView(panel, ui::send, modifier)
        return
    }
    Box(modifier.fillMaxWidth().heightIn(min = 160.dp).padding(24.dp), contentAlignment = Alignment.Center) {
        if (ui.describedSinceShowing) {
            val title = ui.panels.firstOrNull { it.id == id }?.title.orEmpty()
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Not available", style = MaterialTheme.typography.titleMedium)
                Text("$title has nothing to show right now.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            // A short wait for the app to describe the panel: the expressive loading indicator.
            LoadingIndicator()
        }
    }
}

/** Previews of the catalogue's examples, as a Layers inspector and a Brush popover. */
internal object PanelPreviews {
    private val rowActions = listOf(ItemAction("duplicate", "Duplicate", "plus.square.on.square"), ItemAction("delete", "Delete", "trash", destructive = true))

    val layers = Panel(
        "layers", "Layers", PanelRole.Inspector,
        listOf(
            Node.Choice("blend", "Blend Mode", "normal", listOf(ChoiceOption("normal", "Normal"), ChoiceOption("multiply", "Multiply"), ChoiceOption("screen", "Screen")), true),
            Node.Number("opacity", "Opacity", 0.8, 0.0, 1.0, null, NumberUnit.Percent, true),
            Node.Section("layer", "Layer", false, listOf(Node.Toggle("locked", "Lock", value = false, enabled = true))),
            Node.ItemList(
                "layers",
                listOf(Row(2, "Sky", "Pixel", 0, true, true, rowActions), Row(1, "Background", "Pixel", 0, false, false, rowActions)),
                reorderable = true,
                actions = listOf(ItemAction("new_layer", "New Layer", "plus"), ItemAction("new_group", "New Group", "folder.badge.plus")),
            ),
            Node.Unknown("hologram"),
            Node.Malformed("number"),
        ),
    )

    val brush = Panel(
        "brush", "Brush", PanelRole.Tool,
        listOf(
            Node.Number("size", "Size", 24.0, 1.0, 5000.0, 1.0, NumberUnit.Pixels, true, Scale.Log),
            Node.Number("angle", "Angle", 45.0, 0.0, 360.0, 1.0, NumberUnit.Degrees, false),
            Node.Choice(
                "tip", "Tip", "round",
                listOf("Round", "Square", "Chalk", "Ink", "Spray").map { ChoiceOption(it.lowercase(), it) },
                true,
            ),
            Node.Section("dynamics", "Dynamics", true, listOf(Node.Toggle("pressure", "Pressure", value = true, enabled = true))),
        ),
    )
}

@Preview(name = "Layers inspector", widthDp = 360, heightDp = 720)
@Composable
private fun LayersPreview() = dev.craft.kit.CraftTheme {
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) { CraftPanelView(PanelPreviews.layers, send = {}) }
}

@Preview(name = "Brush popover", widthDp = 340, heightDp = 480)
@Composable
private fun BrushPreview() = dev.craft.kit.CraftTheme {
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) { CraftPanelView(PanelPreviews.brush, send = {}) }
}

@Preview(name = "Transport bar", widthDp = 800, heightDp = 200)
@Composable
private fun TransportPreview() = dev.craft.kit.CraftTheme {
    val transport = Transport.of("transport", 11, 30, 24.0, range = 0L until 24)
    Box(Modifier.fillMaxSize().padding(16.dp)) {
        if (transport != null) CraftTransport(transport, "timeline", send = {})
    }
}
