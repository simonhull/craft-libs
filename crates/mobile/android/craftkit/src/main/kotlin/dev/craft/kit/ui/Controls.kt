package dev.craft.kit.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenu
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Label
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.SliderState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.ToggleButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.util.Locale

/** A label's text style beside a control. */
private val labelStyle: TextStyle @Composable get() = MaterialTheme.typography.bodyLarge

/** Numbers in tabular digits, so a changing value doesn't shift. */
private val TabularDigits = TextStyle(fontFeatureSettings = "tnum")

/**
 * A titled group the user can collapse: a tonal card whose header expands it. [collapsed] is only
 * how it starts; after that it's the user's, until the panel's views are built again.
 */
@Composable
internal fun CraftSection(title: String, collapsed: Boolean, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    var expanded by rememberSaveable { mutableStateOf(!collapsed) }
    val turn by animateFloatAsState(if (expanded) 180f else 0f, label = "chevron")
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
        Column {
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .toggleable(expanded, role = Role.Button) { expanded = it }
                    .semantics {
                        heading()
                        stateDescription = if (expanded) "Expanded" else "Collapsed"
                    }
                    .padding(start = 16.dp, end = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                Icon(Icons.Filled.ExpandMore, contentDescription = null, modifier = Modifier.rotate(turn))
            }
            AnimatedVisibility(expanded, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    content()
                }
            }
        }
    }
}

/**
 * A value in a range: Material 3's slider (a thick track, a bar for a handle, the value in a label
 * over the handle while it's held) with the value in a chip beside the label; tap the chip to type
 * one. The slider moves through positions 0..1, spread over the range by the scale; values (shown,
 * typed, sent) are in the number's own units.
 *
 * A drag sends `begin`, `change` for each new value, then `commit`; a typed value is one `commit`.
 * Nothing is sent while the app's value is shown: the app's description changes the slider, never an edit.
 * Disabled, the track still fills to the value, in the disabled colours.
 */
@OptIn(ExperimentalMaterial3Api::class) // The value label over the thumb.
@Composable
internal fun CraftNumber(node: Node.Number, panel: String, send: (Edit) -> Unit, modifier: Modifier = Modifier) {
    val hold = remember { GestureHold() }
    val shown = hold.shown(node.value)
    val locale = LocalConfiguration.current.locales[0]
    val formatted = NumberMath.format(shown, node.unit, locale = locale)
    val currentSend by rememberUpdatedState(send)
    val emit = { step: GestureHold.Step -> currentSend(Edit(panel, node.id, step.phase, step.gesture, EditValue.Number(step.value))) }
    var typing by remember { mutableStateOf(false) }

    // A new description, or a new value: an ended drag's value gives way to the app's.
    val descriptions = LocalCraftDescriptions.current()
    LaunchedEffect(descriptions, node.value) { hold.described() }
    // Re-described without this control, or the panel closed, mid-drag: put the value back.
    DisposableEffect(Unit) { onDispose { hold.cancel()?.let(emit) } }

    Column(modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.alpha(if (node.enabled) 1f else DISABLED_ALPHA)) {
            Text(node.label, style = labelStyle, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Surface(
                onClick = { typing = true },
                enabled = node.enabled,
                shape = RoundedCornerShape(10.dp),
                color = MaterialTheme.colorScheme.secondaryContainer,
                contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                modifier = Modifier.heightIn(min = 32.dp).semantics {
                    contentDescription = node.label
                    stateDescription = formatted
                    onClick(label = "Type a value") { typing = true; true }
                },
            ) {
                Text(
                    formatted,
                    style = MaterialTheme.typography.labelLarge.merge(TabularDigits),
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }
        val range = node.range
        val state = remember { SliderState() }
        state.value = NumberMath.position(shown, range, node.scale).toFloat()
        // The thumb hears the slider's own presses and drags.
        val interaction = remember { MutableInteractionSource() }
        Slider(
            state = state,
            onValueChange = { t ->
                val new = NumberMath.snap(NumberMath.valueAt(t.toDouble(), range, node.scale), node.step, range)
                hold.slide(new, node.value).forEach(emit)
            },
            onValueChangeFinished = { hold.commit()?.let(emit) },
            enabled = node.enabled,
            interactionSource = interaction,
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = node.label; stateDescription = formatted },
            thumb = {
                Label(label = { PlainTooltip { Text(formatted, style = TabularDigits) } }, interactionSource = interaction) {
                    SliderDefaults.Thumb(interactionSource = interaction, isVertical = false, enabled = node.enabled)
                }
            },
            // No stop dot: the value chip says where the end is.
            track = { SliderDefaults.Track(sliderState = it, enabled = node.enabled, drawStopIndicator = null) },
        )
    }

    if (typing) {
        NumberEntry(node, shown, locale, onDismiss = { typing = false }) { value ->
            typing = false
            send(Edit.commit(panel, node.id, EditValue.Number(NumberMath.snap(value, node.step, range = node.range))))
        }
    }
}

/** Material's disabled-content opacity, for a label beside a disabled control. */
private const val DISABLED_ALPHA = 0.38f

/** Numeric entry for a number: its value typed in the locale, a unit allowed; Set sends it, snapped. */
@Composable
private fun NumberEntry(node: Node.Number, shown: Double, locale: Locale, onDismiss: () -> Unit, onSet: (Double) -> Unit) {
    var text by remember { mutableStateOf(NumberMath.format(shown, node.unit, withUnit = false, locale = locale)) }
    val parsed = NumberMath.parse(text, node.unit, locale)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(node.label) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                singleLine = true,
                isError = parsed == null,
                suffix = unitSuffix(node.unit)?.let { suffix -> { Text(suffix) } },
                // The number pad has no minus key everywhere: a range below zero gets the full keyboard.
                keyboardOptions = KeyboardOptions(keyboardType = if (node.range.start < 0) KeyboardType.Text else KeyboardType.Decimal),
            )
        },
        confirmButton = { TextButton(onClick = { parsed?.let(onSet) }, enabled = parsed != null) { Text("Set") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

private fun unitSuffix(unit: NumberUnit): String? = when (unit) {
    NumberUnit.Percent -> "%"
    NumberUnit.Pixels -> "px"
    NumberUnit.Degrees -> "°"
    NumberUnit.None -> null
}

/** On or off: a switch with a check in its thumb; the whole row toggles it. Sends one `commit`. */
@Composable
internal fun CraftToggle(node: Node.Toggle, panel: String, send: (Edit) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(node.value, enabled = node.enabled, role = Role.Switch) { new ->
                if (new != node.value) send(Edit.commit(panel, node.id, EditValue.Toggle(new)))
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(node.label, style = labelStyle, modifier = Modifier.weight(1f))
        Switch(
            checked = node.value,
            onCheckedChange = null,
            enabled = node.enabled,
            thumbContent = if (node.value) {
                { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(SwitchDefaults.IconSize)) }
            } else {
                null
            },
        )
    }
}

/**
 * One of several options: Material 3's connected button group for up to four (the chosen one
 * rounds fully and shows a check), an exposed dropdown menu for more. Picking the current option
 * sends nothing.
 */
@Composable
internal fun CraftChoice(node: Node.Choice, panel: String, send: (Edit) -> Unit, modifier: Modifier = Modifier) {
    val pick = { option: String -> if (option != node.value) send(Edit.commit(panel, node.id, EditValue.Choice(option))) }
    if (node.options.size <= MAX_SEGMENTS) {
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(node.label, style = labelStyle, modifier = Modifier.alpha(if (node.enabled) 1f else DISABLED_ALPHA))
            ConnectedChoice(node.options, node.value, node.enabled, pick)
        }
    } else {
        ChoiceMenu(node, pick, modifier)
    }
}

private const val MAX_SEGMENTS = 4

/** The options as connected toggle buttons, one chosen: a radio group to TalkBack. */
@Composable
private fun ConnectedChoice(options: List<ChoiceOption>, value: String, enabled: Boolean, pick: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().selectableGroup(), horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)) {
        options.forEachIndexed { index, option ->
            val selected = option.id == value
            ToggleButton(
                checked = selected,
                onCheckedChange = { pick(option.id) },
                enabled = enabled,
                shapes = when (index) {
                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                    options.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                },
                icon = if (selected) {
                    { Icon(Icons.Filled.Check, contentDescription = null) }
                } else {
                    null
                },
                // The unchosen ones a step above a panel's surface, so the group's extent reads in a dark inspector.
                colors = ToggleButtonDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainerHighest),
                // Narrower than a lone button's, so a check and a word fit a quarter of a panel.
                contentPadding = PaddingValues(horizontal = 8.dp),
                modifier = Modifier.weight(1f).semantics {
                    role = Role.RadioButton
                    this.selected = selected
                },
            ) {
                Text(option.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** More than four options: an exposed dropdown menu, the chosen option checked. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChoiceMenu(node: Node.Choice, pick: (String) -> Unit, modifier: Modifier) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded && node.enabled, onExpandedChange = { expanded = it }, modifier = modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = node.options.firstOrNull { it.id == node.value }?.label ?: node.value,
            onValueChange = {},
            readOnly = true,
            enabled = node.enabled,
            singleLine = true,
            label = { Text(node.label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable, node.enabled),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            node.options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option.label) },
                    onClick = {
                        expanded = false
                        pick(option.id)
                    },
                    leadingIcon = { if (option.id == node.value) Icon(Icons.Filled.Check, contentDescription = "Chosen") else Spacer(Modifier.size(24.dp)) },
                    contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                )
            }
        }
    }
}
