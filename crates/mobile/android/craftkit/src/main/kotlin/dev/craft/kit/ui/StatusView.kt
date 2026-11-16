package dev.craft.kit.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.WavyProgressIndicatorDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * The app's status over the canvas: a new message as a snackbar at the top that goes away by itself
 * (an error, in error colours, stays longer; tap or close dismisses it), and a job's progress as a
 * card with a wavy bar and Cancel at the bottom, [bottomInset] above the edge, while it lasts.
 * Cancel sends the job's command with [command].
 *
 * A message with an id keeps its snackbar while the id stands: new text (a countdown) changes it in
 * place and starts its time again. A new id is a new snackbar; a dismissed one stays dismissed.
 */
@Composable
fun CraftStatusOverlay(status: Status, command: (String) -> Unit, modifier: Modifier = Modifier, bottomInset: Dp = 24.dp) {
    var dismissed by remember { mutableStateOf<Any?>(null) }
    // Cleared, the same message may come back as news.
    LaunchedEffect(status.message == null) { if (status.message == null) dismissed = null }
    val toast = Status.shown(status.message, dismissed)
    Box(modifier.fillMaxSize()) {
        AnimatedContent(
            targetState = toast,
            contentKey = { it?.identity },
            transitionSpec = { (slideInVertically { -it } + fadeIn()) togetherWith (slideOutVertically { -it } + fadeOut()) },
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 16.dp, start = 24.dp, end = 24.dp),
            label = "message",
        ) { message ->
            if (message != null) {
                LaunchedEffect(message) {
                    delay(message.durationMillis)
                    dismissed = message.identity
                }
                StatusMessage(message) { dismissed = message.identity }
            }
        }
        AnimatedVisibility(
            visible = status.progress != null,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = bottomInset),
        ) {
            // The last progress stays drawn while it leaves.
            var last by remember { mutableStateOf(status.progress) }
            status.progress?.let { last = it }
            last?.let { ProgressCard(it, command) }
        }
    }
}

@Composable
private fun StatusMessage(message: Status.Message, dismiss: () -> Unit) {
    val error = message.tone == Tone.Error
    val colors = MaterialTheme.colorScheme
    Snackbar(
        modifier = Modifier
            .widthIn(max = 560.dp)
            .clickable(onClickLabel = "Dismiss", onClick = dismiss)
            .semantics {
                contentDescription = if (error) "Error: ${message.text}" else message.text
                liveRegion = if (error) LiveRegionMode.Assertive else LiveRegionMode.Polite
            },
        shape = RoundedCornerShape(16.dp),
        containerColor = if (error) colors.errorContainer else colors.inverseSurface,
        contentColor = if (error) colors.onErrorContainer else colors.inverseOnSurface,
        dismissAction = {
            IconButton(onClick = dismiss) { Icon(Symbols.Close, contentDescription = "Dismiss") }
        },
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(if (error) Symbols.Error else Symbols.Info, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(12.dp))
            Text(message.text, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A job in progress: its label, a wavy bar (moving while its length is unknown), and Cancel when it can be stopped. */
@Composable
private fun ProgressCard(progress: Status.Progress, command: (String) -> Unit) {
    Surface(shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, shadowElevation = 3.dp) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 12.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(progress.label, style = MaterialTheme.typography.bodyMedium)
                val fraction = progress.fraction?.coerceIn(0.0, 1.0)?.toFloat()
                val bar = Modifier.width(220.dp)
                if (fraction != null) {
                    val shown by animateFloatAsState(fraction, WavyProgressIndicatorDefaults.ProgressAnimationSpec, label = "progress")
                    LinearWavyProgressIndicator(progress = { shown }, modifier = bar)
                } else {
                    LinearWavyProgressIndicator(modifier = bar)
                }
            }
            Spacer(Modifier.width(12.dp))
            progress.cancel?.let { cancel ->
                TextButton(onClick = { command(cancel) }, modifier = Modifier.semantics { contentDescription = "Cancel ${progress.label}" }) { Text("Cancel") }
            }
        }
    }
}
