package dev.craft.kit.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.NavigateBefore
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalFloatingToolbar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.changedToUp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop

/** How a transport is drawn: [Bar], the shell's floating toolbar; [Inline], plain, in a panel. */
enum class TransportStyle { Bar, Inline }

/**
 * A transport: to start, step back, play or pause (a large button that rounds while paused and
 * squares while playing), step forward and to end; a scrubber with the work area shaded; and the
 * time, in tabular digits.
 *
 * - The buttons send `transport` edits (`commit`).
 * - The scrubber sends `seek` edits: a touch seeks at once (`begin`), moving to another frame sends
 *   `change`, lifting the finger `commit`s; a drag that goes away mid-way sends `cancel`. Mid-drag
 *   it shows the finger's frame, not the app's. A light tick marks crossing an edge of the work area.
 * - The playhead shows the live position ([LocalCraftLiveValues]) when one arrived since the last
 *   description. Only the scrubber (in its draw phase) and the time read it, so a playing transport
 *   redraws those and not its buttons or the layout around them.
 *
 * In a row when there's room, else the buttons and time above the scrubber.
 */
@Composable
fun CraftTransport(transport: Transport, panel: String, send: (Edit) -> Unit, modifier: Modifier = Modifier, style: TransportStyle = TransportStyle.Bar) {
    val scrub = remember { Scrub() }
    val currentSend by rememberUpdatedState(send)
    val emit = { step: Scrub.Step -> currentSend(Edit(panel, transport.id, step.phase, step.gesture, EditValue.Seek(step.frame))) }
    // Re-described without this transport, or closed, mid-scrub: put the playhead back.
    DisposableEffect(Unit) { onDispose { scrub.cancel()?.let(emit) } }
    val press = { action: TransportAction -> send(Edit.commit(panel, transport.id, EditValue.Transport(action))) }

    val content = @Composable {
        BoxWithConstraints(Modifier.alpha(if (transport.enabled) 1f else 0.38f)) {
            if (maxWidth >= 560.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TransportButtons(transport, press)
                    TransportTrack(transport, panel, scrub, emit, Modifier.weight(1f).widthIn(min = 180.dp))
                    TransportTime(transport, panel, scrub, Modifier.padding(end = 12.dp))
                }
            } else {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TransportButtons(transport, press)
                        Spacer(Modifier.weight(1f))
                        TransportTime(transport, panel, scrub, Modifier.padding(end = 12.dp))
                    }
                    TransportTrack(transport, panel, scrub, emit, Modifier.fillMaxWidth())
                }
            }
        }
    }
    when (style) {
        TransportStyle.Bar -> HorizontalFloatingToolbar(
            expanded = true,
            modifier = modifier.widthIn(max = 760.dp),
            colors = floatingChromeColors(),
            // A toolbar's full round, as long as the bar is one row; two rows keep the same corners.
            shape = RoundedCornerShape(36.dp),
            expandedShadowElevation = FLOATING_ELEVATION,
        ) { content() }
        TransportStyle.Inline -> Box(modifier.fillMaxWidth()) { content() }
    }
}

@Composable
private fun TransportButtons(transport: Transport, press: (TransportAction) -> Unit) {
    val enabled = transport.enabled
    Row(verticalAlignment = Alignment.CenterVertically) {
        TransportButton(Icons.Filled.SkipPrevious, "Go to Start", enabled) { press(TransportAction.ToStart) }
        TransportButton(Icons.AutoMirrored.Filled.NavigateBefore, "Step Back", enabled) { press(TransportAction.StepBack) }
        PlayPause(transport.playing, enabled) { press(if (transport.playing) TransportAction.Pause else TransportAction.Play) }
        TransportButton(Icons.AutoMirrored.Filled.NavigateNext, "Step Forward", enabled) { press(TransportAction.StepForward) }
        TransportButton(Icons.Filled.SkipNext, "Go to End", enabled) { press(TransportAction.ToEnd) }
    }
}

@Composable
private fun TransportButton(icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    CraftTooltip(label, position = TipSide.Above) { IconButton(onClick = onClick, enabled = enabled) { Icon(icon, contentDescription = label) } }
}

/** Play and Pause as one medium filled icon button whose shape morphs: round while paused, a rounded square while playing. */
@Composable
private fun PlayPause(playing: Boolean, enabled: Boolean, onClick: () -> Unit) {
    CraftTooltip(if (playing) "Pause" else "Play", position = TipSide.Above) { PlayPauseButton(playing, enabled, onClick) }
}

@Composable
private fun PlayPauseButton(playing: Boolean, enabled: Boolean, onClick: () -> Unit) {
    FilledIconButton(
        onClick = onClick,
        enabled = enabled,
        shapes = IconButtonDefaults.shapes(
            shape = if (playing) IconButtonDefaults.mediumSquareShape else IconButtonDefaults.mediumRoundShape,
            pressedShape = IconButtonDefaults.mediumPressedShape,
        ),
        modifier = Modifier.padding(horizontal = 4.dp).size(IconButtonDefaults.mediumContainerSize()),
    ) {
        Icon(
            if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
            contentDescription = if (playing) "Pause" else "Play",
            modifier = Modifier.size(IconButtonDefaults.mediumIconSize),
        )
    }
}

/**
 * Settles [scrub] when the app says something new about the playhead: a description (changed or
 * not), or another live position. Reads the live positions in a flow, never in composition.
 */
@Composable
private fun SettleOnWord(transport: Transport, panel: String, scrub: Scrub) {
    val live = LocalCraftLiveValues.current
    val descriptions = LocalCraftDescriptions.current()
    LaunchedEffect(descriptions) { scrub.settled() }
    val current by rememberUpdatedState(transport)
    LaunchedEffect(panel, live) {
        snapshotFlow { current.appPosition(panel, live) }.distinctUntilChanged().drop(1).collect { scrub.settled() }
    }
}

/** The time, sized for the widest it can be so the bar doesn't shift as the digits change. */
@Composable
private fun TransportTime(transport: Transport, panel: String, scrub: Scrub, modifier: Modifier = Modifier) {
    val live = LocalCraftLiveValues.current
    val shown = scrub.shown(transport.appPosition(panel, live))
    val style = MaterialTheme.typography.titleSmall.merge(TextStyle(fontFeatureSettings = "tnum"))
    Box(modifier, contentAlignment = Alignment.CenterEnd) {
        Text(transport.widestLabel, style = style, modifier = Modifier.alpha(0f), maxLines = 1)
        // The scrubber says the time to TalkBack.
        Text(transport.label(shown), style = style, textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.semantics { contentDescription = "" })
    }
}

/**
 * The scrubber's track: the frames side by side as equal cells, the work area shaded over them and
 * bracketed at its edges, and the playhead (a bar with a gap either side) in the middle of its frame's cell.
 */
@Composable
private fun TransportTrack(transport: Transport, panel: String, scrub: Scrub, emit: (Scrub.Step) -> Unit, modifier: Modifier) {
    SettleOnWord(transport, panel, scrub)
    val live = LocalCraftLiveValues.current
    val haptics = LocalHapticFeedback.current
    val colors = MaterialTheme.colorScheme
    val current by rememberUpdatedState(transport)
    val appFrame = { current.appPosition(panel, live) }
    val inset = 12.dp
    // Read in the draw phase and in semantics: a live position redraws the track, nothing more.
    Canvas(
        modifier
            .height(48.dp)
            .semantics {
                val frame = scrub.shown(appFrame())
                contentDescription = "Playhead"
                stateDescription = current.spokenLabel(frame)
                if (current.playing) liveRegion = LiveRegionMode.Polite
                progressBarRangeInfo = ProgressBarRangeInfo(frame.toFloat(), 0f..(current.duration - 1).coerceAtLeast(1).toFloat())
                setProgress { target ->
                    val to = target.toLong().coerceIn(0, current.duration - 1)
                    if (to != frame) currentSendSeek(emit, to)
                    true
                }
            }
            .pointerInput(transport.duration) {
                val edge = inset.toPx()
                fun frameAt(x: Float) = Scrub.frameAt((x - edge).toDouble(), (size.width - 2 * edge).toDouble().coerceAtLeast(1.0), current.duration)
                awaitEachGesture {
                    val down = awaitFirstDown()
                    down.consume()
                    emit(scrub.begin(frameAt(down.position.x), appFrame()))
                    while (true) {
                        val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                        if (change == null) {
                            scrub.cancel()?.let(emit)
                            break
                        }
                        val frame = frameAt(change.position.x)
                        if (change.changedToUp()) {
                            change.consume()
                            scrub.commit(frame)?.let(emit)
                            break
                        }
                        change.consume()
                        val old = scrub.current
                        scrub.move(frame)?.let { step ->
                            if (old != null && Scrub.crossesEdge(old, frame, current.range)) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            emit(step)
                        }
                    }
                }
            },
    ) {
        val edge = inset.toPx()
        val width = (size.width - 2 * edge).coerceAtLeast(1f)
        val t = current
        val frame = scrub.shown(appFrame())
        val mid = size.height / 2
        val trackHeight = 12.dp.toPx()
        drawRoundRect(colors.surfaceContainerHighest, Offset(edge, mid - trackHeight / 2), Size(width, trackHeight), CornerRadius(trackHeight / 2))
        val x = edge + Scrub.xOfFrame(frame, width.toDouble(), t.duration).toFloat()
        // Played: from the start to the playhead, as a slider's active track.
        drawRoundRect(colors.primary.copy(alpha = 0.35f), Offset(edge, mid - trackHeight / 2), Size(x - edge, trackHeight), CornerRadius(trackHeight / 2))
        t.range?.let { range ->
            val start = edge + Scrub.xOfEdge(range.first, width.toDouble(), t.duration).toFloat()
            val end = edge + Scrub.xOfEdge(range.last + 1, width.toDouble(), t.duration).toFloat()
            drawRect(colors.tertiary.copy(alpha = 0.45f), Offset(start, mid - trackHeight / 2), Size((end - start).coerceAtLeast(4f), trackHeight))
            val bracket = Size(3.dp.toPx(), 20.dp.toPx())
            for (at in listOf(start, end)) drawRoundRect(colors.tertiary, Offset(at - bracket.width / 2, mid - bracket.height / 2), bracket, CornerRadius(bracket.width))
        }
        // The playhead: a bar, cut out of the track by a gap either side, taller while scrubbing.
        val bar = Size(if (scrub.isScrubbing) 6.dp.toPx() else 4.dp.toPx(), if (scrub.isScrubbing) 40.dp.toPx() else 32.dp.toPx())
        val gap = 4.dp.toPx()
        drawRoundRect(colors.surfaceContainerHigh, Offset(x - bar.width / 2 - gap, mid - trackHeight / 2), Size(bar.width + 2 * gap, trackHeight))
        drawRoundRect(colors.primary, Offset(x - bar.width / 2, mid - bar.height / 2), bar, CornerRadius(bar.width / 2))
    }
}

/** One complete seek (TalkBack's adjust): a `commit` of its own. */
private fun currentSendSeek(emit: (Scrub.Step) -> Unit, frame: Long) = emit(Scrub.Step(GestureIds.next(), Phase.Commit, frame))
