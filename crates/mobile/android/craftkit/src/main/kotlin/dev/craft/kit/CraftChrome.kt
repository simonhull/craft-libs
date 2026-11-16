package dev.craft.kit

import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.craft.kit.ui.CraftMenuBar
import dev.craft.kit.ui.CraftStatusOverlay
import dev.craft.kit.ui.Feature
import dev.craft.kit.ui.ProvideCraftUi

/**
 * Material 3 Expressive for a Craft app: dark, as editors around an image are (the canvas reads
 * truer on dark chrome), in the device's own colors where it has them, with the expressive motion
 * scheme (springier shape and size changes).
 */
@Composable
fun CraftTheme(content: @Composable () -> Unit) {
    val scheme: ColorScheme = if (Build.VERSION.SDK_INT >= 31) dynamicDarkColorScheme(LocalContext.current) else darkColorScheme()
    MaterialExpressiveTheme(colorScheme = scheme, motionScheme = MotionScheme.expressive(), content = content)
}

/**
 * The whole shell: [CraftToolbar] over [CraftCanvas], and around the canvas whatever of the app's
 * chrome the shell draws natively. [actions] are the app's own toolbar buttons, shown before the
 * shared ones. Every part is off by default: an app that draws its own menus and panels would show
 * everything twice.
 *
 * @param chrome the shared app bar buttons (Open, Save, Paste, Undo, Redo) and the items panel.
 * @param nativePanels the app's native panels, each an app bar button: an inspector in a side sheet
 *   at the trailing edge in landscape (a bottom sheet in portrait), a tool in a popover from its
 *   button (a bottom sheet when compact); and its transport as a floating bar above the bottom edge.
 *   The app hides its own versions, and its own ways in (a menu item) open the native one.
 * @param menus the app's menus as text buttons in the app bar, folded into one Menu button when narrow.
 * @param rail the app's tool rail as a vertical floating toolbar at the canvas's leading edge.
 * @param status the app's status: messages as snackbars, progress with Cancel.
 */
@Composable
fun CraftScaffold(
    host: CraftHost,
    appName: String,
    chrome: Boolean = false,
    nativePanels: Boolean = false,
    menus: Boolean = false,
    rail: Boolean = false,
    status: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val features = remember(nativePanels, menus, rail, status) {
        listOf(nativePanels to Feature.Panels, menus to Feature.Menus, rail to Feature.Rail, status to Feature.Status).filter { it.first }.map { it.second }.toSet()
    }
    // Before the canvas starts the app, which hears them then.
    SideEffect { host.ui.features = features }
    var itemsShown by rememberSaveable { mutableStateOf(false) }
    val shell = rememberNativeChrome()
    val activity = LocalActivity.current
    // Back at the root leaves the app as Home does, documents and all, never finishing it:
    // an editor must not drop unsaved work on a stray swipe. (The later handlers win.)
    BackHandler { activity?.moveTaskToBack(true) }
    BackHandler(enabled = itemsShown) { itemsShown = false }
    BackHandler(enabled = shell.inspector != null) { shell.inspector = null }
    if (nativePanels || rail) NativeChromeEffects(host.ui, shell, nativePanels = nativePanels, rail = rail)
    val keyboard by host.keyboard.collectAsStateWithLifecycle()

    ProvideCraftUi(host.ui) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val layout = ChromeLayout.of(maxWidth, maxHeight)
            Scaffold(
                topBar = {
                    if (chrome || menus || nativePanels) {
                        CraftToolbar(
                            host, appName, chrome = chrome, itemsShown = itemsShown, onItemsShownChange = { itemsShown = it }, menus = menus,
                            actions = {
                                actions()
                                if (nativePanels) PanelButtons(host.ui, shell, layout)
                            },
                        )
                    }
                },
                containerColor = MaterialTheme.colorScheme.surfaceContainerLowest,
            ) { padding ->
                // The canvas shrinks above the on-screen keyboard, so the app's dialogs stay in view.
                Box(Modifier.padding(padding).consumeWindowInsets(padding).imePadding().fillMaxSize()) {
                    CraftCanvas(host, Modifier.fillMaxSize())
                    if (rail) ShellRail(host.ui, shell, Modifier.align(Alignment.CenterStart).padding(start = 16.dp, top = 16.dp, bottom = 16.dp))
                    // The transport bar's height while it's on screen, 0 while it isn't: progress clears it.
                    var transportHeight by remember { mutableStateOf(0.dp) }
                    // While typing, the keyboard is the bottom bar.
                    if (nativePanels && !keyboard) {
                        // Clear of the rail, and of the side sheet while it's open.
                        val end by animateDpAsState(if (layout.sideSheet && shell.inspector != null) SIDE_SHEET_ROOM else 24.dp, label = "transportEnd")
                        ShellTransport(host.ui, Modifier.align(Alignment.BottomCenter).padding(start = if (rail) 96.dp else 24.dp, end = end, bottom = 24.dp)) { transportHeight = it }
                    }
                    if (status) CraftStatusOverlay(host.ui.status, host.ui::command, bottomInset = if (transportHeight > 0.dp) 24.dp + transportHeight + 12.dp else 24.dp)
                    if (nativePanels && layout.sideSheet) InspectorSideSheet(host.ui, shell, Modifier.align(Alignment.CenterEnd))
                    AnimatedVisibility(
                        visible = chrome && itemsShown,
                        modifier = Modifier.align(Alignment.TopEnd),
                        enter = slideInHorizontally { it / 3 } + fadeIn(),
                        exit = slideOutHorizontally { it / 3 } + fadeOut(),
                    ) {
                        CraftItemsPanel(host, Modifier.padding(12.dp).width(320.dp).fillMaxHeight())
                    }
                }
            }
            if (nativePanels && !layout.sideSheet) InspectorBottomSheet(host.ui, shell)
        }
    }
}

/**
 * The app bar: the document's name and size; the app's menus ([menus]); the shared file actions,
 * undo and redo, and the items panel toggle ([chrome]); and [actions].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CraftToolbar(
    host: CraftHost,
    appName: String,
    itemsShown: Boolean,
    onItemsShownChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    chrome: Boolean = true,
    menus: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val snapshot by host.snapshot.collectAsStateWithLifecycle()
    val document = snapshot.document
    TopAppBar(
        modifier = modifier,
        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                // The menus take what's left: a weight here would halve their room.
                Column(Modifier.widthIn(max = 280.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(document?.name ?: appName, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f, fill = false))
                        if (document?.dirty == true) {
                            Spacer(Modifier.width(8.dp))
                            // Unsaved changes, as the desktop tab's dot shows them.
                            Box(Modifier.size(8.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary))
                        }
                    }
                    if (document != null) {
                        Text(document.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                    }
                }
                if (menus) {
                    Spacer(Modifier.width(16.dp))
                    CraftMenuBar(host.ui.menus, host.ui::command, Modifier.weight(1f, fill = false))
                }
            }
        },
        actions = {
            actions()
            if (chrome) {
                ToolbarButton(R.drawable.craft_ic_open, "Open") { host.perform(CraftAction.Open) }
                ToolbarButton(R.drawable.craft_ic_save, "Save", enabled = document != null) { host.perform(CraftAction.Save) }
                ToolbarButton(R.drawable.craft_ic_paste, "Paste") { host.paste() }
                VerticalDivider(Modifier.height(24.dp).padding(horizontal = 8.dp))
                ToolbarButton(R.drawable.craft_ic_undo, "Undo", enabled = snapshot.canUndo) { host.perform(CraftAction.Undo) }
                ToolbarButton(R.drawable.craft_ic_redo, "Redo", enabled = snapshot.canRedo) { host.perform(CraftAction.Redo) }
                VerticalDivider(Modifier.height(24.dp).padding(horizontal = 8.dp))
                IconToggleButton(checked = itemsShown, onCheckedChange = onItemsShownChange) {
                    Icon(painterResource(R.drawable.craft_ic_layers), contentDescription = snapshot.itemsTitle.ifEmpty { "Items" })
                }
            }
            Spacer(Modifier.width(8.dp))
        },
    )
}

/** An app bar button with an icon from [icon] (craftkit's `craft_ic_*` or the app's own). */
@Composable
fun ToolbarButton(icon: Int, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled) { Icon(painterResource(icon), contentDescription = label) }
}

/** The active document's items (layers, tracks, pages): select one, show or hide it. */
@Composable
fun CraftItemsPanel(host: CraftHost, modifier: Modifier = Modifier) {
    val snapshot by host.snapshot.collectAsStateWithLifecycle()
    Surface(modifier, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, shadowElevation = 6.dp) {
        Column {
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 16.dp, top = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(snapshot.itemsTitle.ifEmpty { "Items" }, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                if (snapshot.items.isNotEmpty()) {
                    Text("${snapshot.items.size}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (snapshot.document == null) {
                Text(
                    "No document open",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                )
            }
            LazyColumn(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(snapshot.items, key = { it.id }) { item -> ItemRow(item, host) }
            }
        }
    }
}

@Composable
private fun ItemRow(item: Item, host: CraftHost) {
    val colors = MaterialTheme.colorScheme
    val background = if (item.selected) colors.secondaryContainer else Color.Transparent
    val content = if (item.selected) colors.onSecondaryContainer else colors.onSurface
    val hidden = item.visible == false
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(background)
            .clickable(role = Role.Button, onClickLabel = "Select") { host.perform(CraftAction.Select(item.id)) }
            .padding(start = 12.dp + 16.dp * item.depth, end = 4.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(vertical = 6.dp)) {
            Text(
                item.name,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (item.selected) FontWeight.Medium else FontWeight.Normal,
                color = if (hidden) content.copy(alpha = 0.5f) else content,
            )
            if (item.kind.isNotEmpty()) {
                Text(item.kind, style = MaterialTheme.typography.labelSmall, color = colors.onSurfaceVariant)
            }
        }
        item.visible?.let { visible ->
            IconButton(onClick = { host.perform(CraftAction.SetVisible(item.id, !visible)) }) {
                Icon(
                    painterResource(if (visible) R.drawable.craft_ic_visible else R.drawable.craft_ic_hidden),
                    contentDescription = if (visible) "Hide ${item.name}" else "Show ${item.name}",
                    tint = if (visible) content else colors.onSurfaceVariant.copy(alpha = 0.6f),
                )
            }
        }
    }
}
