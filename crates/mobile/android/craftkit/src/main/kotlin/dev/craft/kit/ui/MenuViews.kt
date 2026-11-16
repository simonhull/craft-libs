package dev.craft.kit.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp

/**
 * The app's menus in the top app bar: each a text button opening its menu, or, when they don't all
 * fit, one Menu button holding them all as submenus. Choosing an item sends its command with
 * [choose] (a hardware keyboard's shortcuts go to the app's own key handling, as they always do).
 * Nothing while the app has no menus.
 */
@Composable
fun CraftMenuBar(bar: MenuBar, choose: (String) -> Unit, modifier: Modifier = Modifier) {
    if (bar.menus.isEmpty()) return
    // Both are composed; the layout places the row of menus when it fits, else the Menu button.
    Layout(
        contents = listOf(
            { Row(verticalAlignment = Alignment.CenterVertically) { bar.menus.forEach { menu -> MenuButton(menu, choose) } } },
            { FoldedMenus(bar, choose) },
        ),
        modifier = modifier,
    ) { (wide, folded), constraints ->
        val loose = constraints.copy(minWidth = 0, maxWidth = Constraints.Infinity)
        val row = wide.first().measure(loose)
        val chosen = if (row.width <= constraints.maxWidth) row else folded.first().measure(constraints.copy(minWidth = 0))
        layout(chosen.width, chosen.height) { chosen.placeRelative(0, 0) }
    }
}

@Composable
private fun MenuButton(menu: Menu, choose: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { open = true }) { Text(menu.title, style = MaterialTheme.typography.labelLarge) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, shape = RoundedCornerShape(16.dp)) {
            MenuItems(menu.items) { id ->
                open = false
                choose(id)
            }
        }
    }
}

/** Every menu behind one button, each a submenu. */
@Composable
private fun FoldedMenus(bar: MenuBar, choose: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { open = true }) {
            Icon(Symbols.Menu, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Menu")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, shape = RoundedCornerShape(16.dp)) {
            bar.menus.forEach { menu ->
                Submenu(menu.title, menu.items) { id ->
                    open = false
                    choose(id)
                }
            }
        }
    }
}

/**
 * A menu's entries: separators as dividers, submenus opening beside their item, a checked item with
 * a check, the shortcut trailing, a disabled item greyed.
 */
@Composable
internal fun MenuItems(items: List<MenuEntry>, choose: (String) -> Unit) {
    items.forEach { item ->
        when (item) {
            MenuEntry.Separator -> HorizontalDivider(Modifier.padding(vertical = 4.dp))
            is MenuEntry.Submenu -> Submenu(item.label, item.items, choose)
            is MenuEntry.Command -> {
                val command = item.command
                DropdownMenuItem(
                    text = { Text(command.label) },
                    onClick = { choose(command.id) },
                    enabled = command.enabled,
                    leadingIcon = command.checked?.let { checked ->
                        { if (checked) Icon(Symbols.Check, contentDescription = "Checked") else Spacer(Modifier.size(24.dp)) }
                    },
                    trailingIcon = command.shortcut?.let { shortcut ->
                        { Text(shortcut.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    },
                )
            }
        }
    }
}

/** An item that opens its own menu beside it, level with it. */
@Composable
private fun Submenu(label: String, items: List<MenuEntry>, choose: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    var size by remember { mutableStateOf(DpSize.Zero) }
    val density = LocalDensity.current
    Box {
        DropdownMenuItem(
            text = { Text(label) },
            onClick = { open = true },
            trailingIcon = { Icon(Symbols.ChevronRight, contentDescription = null) },
            modifier = Modifier.onSizeChanged { size = with(density) { DpSize(it.width.toDp(), it.height.toDp()) } },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, offset = DpOffset(size.width, -size.height), shape = RoundedCornerShape(16.dp)) {
            MenuItems(items) { id ->
                open = false
                choose(id)
            }
        }
    }
}
