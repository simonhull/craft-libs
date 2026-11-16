package dev.craft.kit

import android.util.Log
import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import dev.craft.kit.ui.CraftIcons
import dev.craft.kit.ui.CraftPanelHost
import dev.craft.kit.ui.CraftPopover
import dev.craft.kit.ui.CraftRail
import dev.craft.kit.ui.CraftTooltip
import dev.craft.kit.ui.CraftTransport
import dev.craft.kit.ui.CraftUi
import dev.craft.kit.ui.PanelHeader
import dev.craft.kit.ui.PanelInfo
import dev.craft.kit.ui.PanelRole
import dev.craft.kit.ui.PopoverSide
import dev.craft.kit.ui.firstTransport
import dev.craft.kit.ui.toolPalette
import kotlin.coroutines.cancellation.CancellationException

// The app's native panels in the shell. Each part reads only the state it shows: the app bar's
// buttons read the panels offered (which change rarely), an open panel its description, and only a
// transport's playhead the live positions, so a drag redraws the open panel and nothing around it.

/** Which of the app's panels the shell has open. Kept across a rotation. */
@Stable
internal class NativeChrome(inspector: String? = null, popover: String? = null, railOptions: String? = null) {
    /** The inspector panel in the side (or bottom) sheet. */
    var inspector by mutableStateOf(inspector)

    /** The tool panel whose popover is up. */
    var popover by mutableStateOf(popover)

    /** The Tool panel the rail opened for the selected tool's options. */
    var railOptions by mutableStateOf(railOptions)

    /**
     * Opens inspector [id] (`null` closes it). The inspector and a tool's popover share the trailing
     * edge, so one replaces the other: a popover over the side sheet would leave the inspector
     * peeking out behind it.
     */
    fun openInspector(id: String?) {
        inspector = id
        if (id != null) popover = null
    }

    /** Opens tool panel [id] in its popover (`null` closes it), in place of an open inspector. */
    fun openPopover(id: String?) {
        popover = id
        if (id != null) inspector = null
    }

    companion object {
        val saver: Saver<NativeChrome, *> = listSaver(
            save = { listOf(it.inspector, it.popover, it.railOptions) },
            restore = { NativeChrome(it[0], it[1], it[2]) },
        )
    }
}

@Composable
internal fun rememberNativeChrome(): NativeChrome = rememberSaveable(saver = NativeChrome.saver) { NativeChrome() }

/** Where panels go at this window size. */
internal data class ChromeLayout(val sideSheet: Boolean, val compact: Boolean) {
    companion object {
        /** An inspector is a side sheet in landscape (a bottom sheet in portrait); tools are popovers unless the window is compact. */
        fun of(width: Dp, height: Dp) = ChromeLayout(sideSheet = width > height && width >= 600.dp, compact = width < 600.dp)
    }
}

/**
 * Tells the app which panels are on screen whenever that changes; closes a panel the app no longer
 * offers; opens one the app asks for (wire kind 14) as its button would.
 */
@Composable
internal fun NativeChromeEffects(ui: CraftUi, shell: NativeChrome, nativePanels: Boolean, rail: Boolean) {
    val shown = buildSet {
        shell.inspector?.let(::add)
        shell.popover?.let(::add)
        if (rail) {
            // The rail is always on screen; so is the options panel it opened.
            ui.panels.filter { it.role == PanelRole.Rail }.forEach { add(it.id) }
            shell.railOptions?.let(::add)
        }
        // The transport bar is on screen while the app offers it.
        if (nativePanels) ui.panels.filter { it.role == PanelRole.Transport }.forEach { add(it.id) }
    }
    LaunchedEffect(shown) { if (nativePanels) ui.showing(shown) }
    LaunchedEffect(ui.panels) {
        val offered = ui.panels.map(PanelInfo::id).toSet()
        if (shell.inspector !in offered) shell.inspector = null
        if (shell.popover !in offered) shell.popover = null
        if (shell.railOptions !in offered) shell.railOptions = null
    }
    val request = ui.openRequest
    LaunchedEffect(request) {
        request ?: return@LaunchedEffect
        ui.openRequestHandled()
        val info = ui.panels.firstOrNull { it.id == request.id }
        when (info?.role) {
            PanelRole.Inspector -> shell.openInspector(info.id)
            PanelRole.Tool -> shell.openPopover(info.id)
            // Always on screen while the shell shows them.
            PanelRole.Rail, PanelRole.Transport -> Unit
            null -> Log.d("craftkit", "the app asked to open panel ${request.id}, which it doesn't offer")
        }
    }
}

/** The app's inspector and tool panels as app bar buttons: an inspector toggles its sheet, a tool its popover. The open one is checked. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PanelButtons(ui: CraftUi, shell: NativeChrome, layout: ChromeLayout) {
    for (info in ui.panels) {
        key(info.id) {
            when (info.role) {
                PanelRole.Inspector -> PanelButton(info, shell.inspector == info.id) { shell.openInspector(if (it) info.id else null) }
                PanelRole.Tool -> Box {
                    PanelButton(info, shell.popover == info.id) { shell.openPopover(if (it) info.id else null) }
                    if (shell.popover == info.id) {
                        val close = { if (shell.popover == info.id) shell.popover = null }
                        if (layout.compact) {
                            ModalBottomSheet(onDismissRequest = close, sheetState = rememberModalBottomSheetState()) { PanelSheetContent(ui, info, close) }
                        } else {
                            CraftPopover(PopoverSide.Below, onDismiss = close, title = info.title) { PanelSheetContent(ui, info, close = null, header = false) }
                        }
                    }
                }
                // The rail is beside the canvas, the transport above its bottom edge: neither is a button.
                PanelRole.Rail, PanelRole.Transport -> Unit
            }
        }
    }
}

@Composable
private fun PanelButton(info: PanelInfo, open: Boolean, onOpenChange: (Boolean) -> Unit) {
    CraftTooltip(info.accessibilityName) {
        IconToggleButton(checked = open, onCheckedChange = onOpenChange, modifier = Modifier.semantics { contentDescription = info.accessibilityName }) {
            val icon = CraftIcons.icon(info.icon, filled = open)
            if (icon != null) {
                Icon(icon, contentDescription = null)
            } else {
                Text(info.accessibilityName.take(1).uppercase(), fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/**
 * A panel's contents under its header: its title, with a close button where there's [close]. A
 * popover draws its own header ([header] `false`).
 */
@Composable
private fun PanelSheetContent(ui: CraftUi, info: PanelInfo, close: (() -> Unit)?, modifier: Modifier = Modifier, header: Boolean = true) {
    Column(modifier) {
        if (header) PanelHeader(info.title, close)
        // Another panel is another view: none of this one's state (a drag, a collapsed section) carries over.
        key(info.id) { CraftPanelHost(ui, info.id) }
    }
}

/** How much smaller the side sheet gets at the end of a back gesture, as Material's sheets do. */
private const val PREDICTIVE_BACK_SHRINK = 0.1f

/** How much of the canvas's width the side sheet covers, its margins included. */
internal val SIDE_SHEET_ROOM = 392.dp

/** The open inspector as a standard side sheet, floating at the trailing edge (landscape). */
@Composable
internal fun InspectorSideSheet(ui: CraftUi, shell: NativeChrome, modifier: Modifier = Modifier) {
    val info = ui.panels.firstOrNull { it.id == shell.inspector && it.role == PanelRole.Inspector }
    // The last one stays drawn while the sheet slides away.
    var last by remember { mutableStateOf(info) }
    if (info != null) last = info
    // Back closes it, the predictive way: the sheet shrinks toward its edge as the gesture goes.
    var back by remember { mutableFloatStateOf(0f) }
    val edge = if (LocalLayoutDirection.current == LayoutDirection.Ltr) 1f else 0f
    LaunchedEffect(info != null) { if (info != null) back = 0f }
    PredictiveBackHandler(enabled = info != null) { events ->
        try {
            events.collect { back = it.progress }
            shell.inspector = null
        } catch (cancelled: CancellationException) {
            back = 0f
            throw cancelled
        }
    }
    AnimatedVisibility(
        visible = info != null,
        modifier = modifier,
        enter = slideInHorizontally { it / 2 } + fadeIn(),
        exit = slideOutHorizontally { it / 2 } + fadeOut(),
    ) {
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            shadowElevation = 6.dp,
            modifier = Modifier
                .padding(16.dp)
                .width(360.dp)
                .fillMaxHeight()
                .graphicsLayer {
                    val scale = 1f - PREDICTIVE_BACK_SHRINK * back
                    scaleX = scale
                    scaleY = scale
                    transformOrigin = TransformOrigin(edge, 0.5f)
                },
        ) {
            last?.let { PanelSheetContent(ui, it, close = { shell.inspector = null }) }
        }
    }
}

/** The open inspector as a modal bottom sheet (portrait). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun InspectorBottomSheet(ui: CraftUi, shell: NativeChrome) {
    val info = ui.panels.firstOrNull { it.id == shell.inspector && it.role == PanelRole.Inspector } ?: return
    ModalBottomSheet(onDismissRequest = { shell.inspector = null }, sheetState = rememberModalBottomSheetState()) {
        PanelSheetContent(ui, info, close = null, Modifier.navigationBarsPadding())
    }
}

/**
 * The app's rail panel (its tool palette), while it offers one and has described it. Tool options
 * open the palette's Tool panel in a popover beside the rail, or send its fallback command.
 */
@Composable
internal fun ShellRail(ui: CraftUi, shell: NativeChrome, modifier: Modifier = Modifier) {
    val info = ui.panels.firstOrNull { it.role == PanelRole.Rail }
    val palette = info?.let { ui.open[it.id]?.toolPalette() }
    AnimatedVisibility(palette != null, modifier, enter = slideInHorizontally { -it } + fadeIn(), exit = slideOutHorizontally { -it } + fadeOut()) {
        if (info != null && palette != null) {
            CraftRail(
                palette = palette,
                panel = info.id,
                send = ui::send,
                command = ui::command,
                optionsPanel = shell.railOptions,
                onOptionsPanel = { shell.railOptions = it },
                optionsTitle = { id -> ui.panels.firstOrNull { it.id == id }?.title },
            ) { id -> ui.panels.firstOrNull { it.id == id }?.let { options -> PanelSheetContent(ui, options, close = null, header = false) } }
        }
    }
}

/**
 * The app's transport panel as a floating bar, while it offers one and has described it. Reports
 * its height while it's on screen, 0 once it's gone. Its live positions redraw only its playhead.
 */
@Composable
internal fun ShellTransport(ui: CraftUi, modifier: Modifier = Modifier, onHeight: (Dp) -> Unit) {
    val info = ui.panels.firstOrNull { it.role == PanelRole.Transport }
    val transport = info?.let { ui.open[it.id]?.nodes?.firstTransport() }
    val report by rememberUpdatedState(onHeight)
    val density = LocalDensity.current
    DisposableEffect(Unit) { onDispose { report(0.dp) } }
    LaunchedEffect(transport == null) { if (transport == null) report(0.dp) }
    AnimatedVisibility(transport != null, modifier, enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
        if (info != null && transport != null) {
            CraftTransport(transport, info.id, ui::send, Modifier.onSizeChanged { report(with(density) { it.height.toDp() }) })
        }
    }
}
