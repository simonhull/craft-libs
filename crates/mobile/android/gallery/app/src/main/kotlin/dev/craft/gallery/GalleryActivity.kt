package dev.craft.gallery

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import dev.craft.kit.CraftTheme
import dev.craft.kit.ui.CraftMenuBar
import dev.craft.kit.ui.CraftPanelView
import dev.craft.kit.ui.CraftPopover
import dev.craft.kit.ui.CraftRail
import dev.craft.kit.ui.CraftStatusOverlay
import dev.craft.kit.ui.CraftTransport
import dev.craft.kit.ui.LocalCraftDescriptions
import dev.craft.kit.ui.LocalCraftLiveValues
import dev.craft.kit.ui.Panel
import dev.craft.kit.ui.PanelRole
import dev.craft.kit.ui.PopoverSide
import dev.craft.kit.ui.Symbols
import dev.craft.kit.ui.Tone

/**
 * Every craftkit native panel primitive from the generated catalogue, live against a fake app: each
 * in a side sheet beside its description and the edits it sent, and as a tool popover from the app
 * bar. `adb shell am start -n dev.craft.gallery/.GalleryActivity --es selection item_list` opens a
 * primitive by its catalogue name (or `everything`).
 */
class GalleryActivity : ComponentActivity() {
    /** The page the launching intent asked for, if any. */
    private var asked by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        asked = intent.getStringExtra("selection")
        setContent { CraftTheme { Gallery(asked) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("selection")?.let { asked = it }
    }
}

@Composable
private fun Gallery(start: String?) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { GalleryStore(context.assets.open("ui.json").bufferedReader().use { it.readText() }, scope) }
    var selection by rememberSaveable { mutableStateOf("number") }
    LaunchedEffect(start) { start?.let { selection = it } }
    CompositionLocalProvider(LocalCraftDescriptions provides store::descriptions, LocalCraftLiveValues provides store.live) {
        Surface(color = MaterialTheme.colorScheme.surfaceContainerLowest) {
            Row(Modifier.fillMaxSize().safeDrawingPadding()) {
                Sidebar(store, selection) { selection = it }
                Box(Modifier.weight(1f).fillMaxHeight()) { Detail(store, selection) }
            }
        }
    }
}

@Composable
private fun Sidebar(store: GalleryStore, selection: String, select: (String) -> Unit) {
    LazyColumn(Modifier.width(240.dp).fillMaxHeight().padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        item { Text("CraftUI", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(16.dp)) }
        item { SectionTitle("Primitives") }
        items(store.entries, key = { it.name }) { entry -> SidebarItem(entry.name, selection, select) }
        item { SectionTitle("Chrome") }
        items(store.chrome, key = { "chrome-${it.name}" }) { chrome -> SidebarItem(chrome.name, selection, select) }
        item { SectionTitle("Panels") }
        item { SidebarItem(GalleryStore.EVERYTHING, selection, select, label = "Everything") }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp))
}

@Composable
private fun SidebarItem(name: String, selection: String, select: (String) -> Unit, label: String = name) {
    NavigationDrawerItem(
        label = { Text(label, fontFamily = if (label == name) FontFamily.Monospace else FontFamily.Default) },
        selected = selection == name,
        onClick = { select(name) },
    )
}

@Composable
private fun BoxScope.Detail(store: GalleryStore, selection: String) {
    store.problem?.let { problem ->
        Text(problem, modifier = Modifier.padding(32.dp))
        return
    }
    when (selection) {
        "menu_bar" -> MenuDetail(store)
        "status" -> StatusDetail(store)
        GalleryStore.EVERYTHING -> PanelDetail(store, "Everything", "Every example in one panel, as an app's inspector would put them.") { store.everything(it) }
        else -> {
            val entry = store.entries.firstOrNull { it.name == selection } ?: return
            PanelDetail(store, entry.name, entry.about) { store.panel(entry, it) }
            when (entry.name) {
                "tool_palette" -> GalleryRail(store, Modifier.align(Alignment.CenterStart).padding(start = 16.dp))
                "transport" -> store.transport?.let { transport ->
                    CraftTransport(transport, GalleryStore.TIMELINE, store::send, Modifier.align(Alignment.BottomCenter).padding(start = 24.dp, end = 400.dp, bottom = 24.dp))
                }
            }
        }
    }
}

/** A primitive (or all of them): what it is and the edits it sent; the panel in a side sheet, and as a popover from the app bar. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PanelDetail(store: GalleryStore, title: String, about: String, panel: (PanelRole) -> Panel) {
    var inspector by rememberSaveable { mutableStateOf(true) }
    var popover by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f)) {
            TopAppBar(
                title = { Text(title, fontFamily = FontFamily.Monospace) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest),
                actions = {
                    IconButton(onClick = store::clearLog, enabled = store.log.isNotEmpty()) { Icon(Symbols.Delete, contentDescription = "Clear Log") }
                    Box {
                        IconToggleButton(checked = popover, onCheckedChange = { popover = it }) { Icon(Symbols.PictureInPicture, contentDescription = "Popover") }
                        if (popover) {
                            CraftPopover(PopoverSide.Below, onDismiss = { popover = false }, title = title) { CraftPanelView(panel(PanelRole.Tool), store::send) }
                        }
                    }
                    IconToggleButton(checked = inspector, onCheckedChange = { inspector = it }) { Icon(Symbols.ViewSidebar, contentDescription = "Inspector") }
                },
            )
            Log(store, about, Modifier.padding(start = if (title == "tool_palette") 88.dp else 0.dp))
        }
        if (inspector) {
            Surface(
                shape = RoundedCornerShape(28.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                modifier = Modifier.padding(12.dp).width(360.dp).fillMaxHeight(),
            ) {
                Column {
                    Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(start = 24.dp, top = 20.dp))
                    CraftPanelView(panel(PanelRole.Inspector), store::send)
                }
            }
        }
    }
}

/** What the primitive is, then every message it sent, newest first, as the JSON the app would receive. */
@Composable
private fun Log(store: GalleryStore, about: String, modifier: Modifier = Modifier) {
    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 24.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item { Text(about, style = MaterialTheme.typography.bodyLarge) }
        item { Text("Sent", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp)) }
        if (store.log.isEmpty()) {
            item { Text("Use the controls: each edit shows here as the JSON the app would receive.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        items(store.log.size) { index ->
            Text(store.log[index], style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
        }
    }
}

/** The palette as the shell's rail: tap, long-press a slot for its flyout, double-tap or the options button for a stand-in Tool panel. */
@Composable
private fun GalleryRail(store: GalleryStore, modifier: Modifier) {
    val palette = store.palette ?: return
    var options by remember { mutableStateOf<String?>(null) }
    CraftRail(
        palette,
        GalleryStore.TOOLS,
        store::send,
        command = store::command,
        optionsPanel = options,
        onOptionsPanel = { options = it },
        modifier = modifier,
        optionsTitle = { it.replaceFirstChar(Char::uppercase) },
    ) { id -> CraftPanelView(store.optionsPanel(id), store::send) }
}

/** The catalogue's menus in an app bar, wide and folded (as when narrow); what each item sends. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MenuDetail(store: GalleryStore) {
    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("menu_bar", fontFamily = FontFamily.Monospace)
                    CraftMenuBar(store.menus, store::command, Modifier.padding(start = 24.dp))
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        )
        Row(Modifier.padding(24.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Narrow, the menus fold into one button:", modifier = Modifier.padding(end = 16.dp))
            Box(Modifier.width(120.dp).background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(12.dp))) {
                CraftMenuBar(store.menus, store::command)
            }
        }
        Log(store, store.chrome.firstOrNull { it.name == "menu_bar" }?.about.orEmpty())
    }
}

/** The catalogue's status over the detail, as the shell shows it over the canvas, with buttons that set a new one. */
@Composable
private fun StatusDetail(store: GalleryStore) {
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(top = 96.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(onClick = { store.say("Saved great-wave.pcraft", Tone.Info) }) { Text("Message") }
                FilledTonalButton(onClick = { store.say("Couldn't open b.psd: not a Photoshop file", Tone.Error) }) { Text("Error") }
                FilledTonalButton(onClick = store::startJob) { Text("Job") }
                FilledTonalButton(onClick = store::countDown) { Text("Countdown") }
            }
            Log(store, store.chrome.firstOrNull { it.name == "status" }?.about.orEmpty())
        }
        CraftStatusOverlay(store.status, command = { store.cancelJob() })
    }
}
