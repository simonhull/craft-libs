package dev.craft.kit.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.AutoFixHigh
import androidx.compose.material.icons.filled.AutoFixNormal
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.ChangeHistory
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Colorize
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Crop
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FileCopy
import androidx.compose.material.icons.filled.FilterNone
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.FormatColorFill
import androidx.compose.material.icons.filled.FormatPaint
import androidx.compose.material.icons.filled.Gesture
import androidx.compose.material.icons.filled.Gradient
import androidx.compose.material.icons.filled.GridOn
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Handyman
import androidx.compose.material.icons.filled.Healing
import androidx.compose.material.icons.filled.Hexagon
import androidx.compose.material.icons.filled.HighlightAlt
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.HorizontalRule
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Mouse
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.NearMe
import androidx.compose.material.icons.filled.OpenWith
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Pentagon
import androidx.compose.material.icons.filled.Polyline
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Rectangle
import androidx.compose.material.icons.filled.Redo
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SelectAll
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StickyNote2
import androidx.compose.material.icons.filled.Straighten
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.TextFormat
import androidx.compose.material.icons.filled.Title
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Water
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.AutoFixHigh
import androidx.compose.material.icons.outlined.AutoFixNormal
import androidx.compose.material.icons.outlined.Brush
import androidx.compose.material.icons.outlined.ChangeHistory
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Colorize
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.Crop
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Draw
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FileCopy
import androidx.compose.material.icons.outlined.FilterNone
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.FormatColorFill
import androidx.compose.material.icons.outlined.FormatPaint
import androidx.compose.material.icons.outlined.Gesture
import androidx.compose.material.icons.outlined.Gradient
import androidx.compose.material.icons.outlined.GridOn
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Handyman
import androidx.compose.material.icons.outlined.Healing
import androidx.compose.material.icons.outlined.Hexagon
import androidx.compose.material.icons.outlined.HighlightAlt
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.HorizontalRule
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.LibraryAdd
import androidx.compose.material.icons.outlined.LocalFireDepartment
import androidx.compose.material.icons.outlined.Mouse
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.NearMe
import androidx.compose.material.icons.outlined.OpenWith
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.Pentagon
import androidx.compose.material.icons.outlined.Polyline
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Rectangle
import androidx.compose.material.icons.outlined.Redo
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.RotateRight
import androidx.compose.material.icons.outlined.Save
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.SelectAll
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.ShowChart
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.StickyNote2
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.TextFormat
import androidx.compose.material.icons.outlined.Title
import androidx.compose.material.icons.outlined.TouchApp
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.Undo
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.Water
import androidx.compose.material.icons.outlined.WaterDrop
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * The catalogue's SF Symbol names as Material icons, outlined and filled (a selected tool shows the
 * filled one). A name without an icon here shows as a letter where there is one (a tool's), else as
 * text (a list action's label), so a new symbol in an app never breaks the shell; add it here.
 */
object CraftIcons {
    /** An icon in its two styles; made only when first drawn. */
    private class Pair(val outlined: () -> ImageVector, val filled: () -> ImageVector)

    @Suppress("DEPRECATION") // The auto-mirrored variants aren't in every icon's set; these read the same.
    private val icons: Map<String, Pair> = mapOf(
        // Panels and list actions.
        "square.3.layers.3d" to Pair({ Icons.Outlined.Layers }, { Icons.Filled.Layers }),
        "doc.on.doc" to Pair({ Icons.Outlined.FileCopy }, { Icons.Filled.FileCopy }),
        "hammer" to Pair({ Icons.Outlined.Handyman }, { Icons.Filled.Handyman }),
        "film" to Pair({ Icons.Outlined.Movie }, { Icons.Filled.Movie }),
        "plus" to Pair({ Icons.Outlined.Add }, { Icons.Filled.Add }),
        "folder.badge.plus" to Pair({ Icons.Outlined.CreateNewFolder }, { Icons.Filled.CreateNewFolder }),
        "folder" to Pair({ Icons.Outlined.FolderOpen }, { Icons.Filled.FolderOpen }),
        "plus.square.on.square" to Pair({ Icons.Outlined.LibraryAdd }, { Icons.Filled.LibraryAdd }),
        "trash" to Pair({ Icons.Outlined.Delete }, { Icons.Filled.Delete }),
        "xmark" to Pair({ Icons.Outlined.Close }, { Icons.Filled.Close }),
        "eye" to Pair({ Icons.Outlined.Visibility }, { Icons.Filled.Visibility }),
        "eye.slash" to Pair({ Icons.Outlined.VisibilityOff }, { Icons.Filled.VisibilityOff }),
        "slider.horizontal.3" to Pair({ Icons.Outlined.Tune }, { Icons.Filled.Tune }),
        "square.and.arrow.down" to Pair({ Icons.Outlined.Save }, { Icons.Filled.Save }),
        "square.and.arrow.up" to Pair({ Icons.Outlined.Share }, { Icons.Filled.Share }),
        "arrow.uturn.backward" to Pair({ Icons.Outlined.Undo }, { Icons.Filled.Undo }),
        "arrow.uturn.forward" to Pair({ Icons.Outlined.Redo }, { Icons.Filled.Redo }),
        "doc.on.clipboard" to Pair({ Icons.Outlined.ContentPaste }, { Icons.Filled.ContentPaste }),
        "square.on.square" to Pair({ Icons.Outlined.ContentCopy }, { Icons.Filled.ContentCopy }),
        // Tools.
        "arrow.up.and.down.and.arrow.left.and.right" to Pair({ Icons.Outlined.OpenWith }, { Icons.Filled.OpenWith }),
        "rectangle.on.rectangle" to Pair({ Icons.Outlined.FilterNone }, { Icons.Filled.FilterNone }),
        "rectangle.dashed" to Pair({ Icons.Outlined.HighlightAlt }, { Icons.Filled.HighlightAlt }),
        "circle.dashed" to Pair({ Icons.Outlined.RadioButtonUnchecked }, { Icons.Filled.RadioButtonUnchecked }),
        "arrow.left.and.right" to Pair({ Icons.Outlined.SwapHoriz }, { Icons.Filled.SwapHoriz }),
        "arrow.up.and.down" to Pair({ Icons.Outlined.SwapVert }, { Icons.Filled.SwapVert }),
        "lasso" to Pair({ Icons.Outlined.Gesture }, { Icons.Filled.Gesture }),
        "pentagon" to Pair({ Icons.Outlined.Pentagon }, { Icons.Filled.Pentagon }),
        "square.dashed.inset.filled" to Pair({ Icons.Outlined.SelectAll }, { Icons.Filled.SelectAll }),
        "wand.and.stars" to Pair({ Icons.Outlined.AutoFixHigh }, { Icons.Filled.AutoFixHigh }),
        "wand.and.rays" to Pair({ Icons.Outlined.AutoFixNormal }, { Icons.Filled.AutoFixNormal }),
        "crop" to Pair({ Icons.Outlined.Crop }, { Icons.Filled.Crop }),
        "square.split.2x2" to Pair({ Icons.Outlined.GridView }, { Icons.Filled.GridView }),
        "square.split.2x2.fill" to Pair({ Icons.Outlined.Dashboard }, { Icons.Filled.Dashboard }),
        "photo.artframe" to Pair({ Icons.Outlined.Image }, { Icons.Filled.Image }),
        "eyedropper" to Pair({ Icons.Outlined.Colorize }, { Icons.Filled.Colorize }),
        "ruler" to Pair({ Icons.Outlined.Straighten }, { Icons.Filled.Straighten }),
        "note.text" to Pair({ Icons.Outlined.StickyNote2 }, { Icons.Filled.StickyNote2 }),
        "number" to Pair({ Icons.Outlined.Tag }, { Icons.Filled.Tag }),
        "bandage" to Pair({ Icons.Outlined.Healing }, { Icons.Filled.Healing }),
        "paintbrush.pointed" to Pair({ Icons.Outlined.Brush }, { Icons.Filled.Brush }),
        "paintbrush" to Pair({ Icons.Outlined.FormatPaint }, { Icons.Filled.FormatPaint }),
        "pencil" to Pair({ Icons.Outlined.Edit }, { Icons.Filled.Edit }),
        "paintpalette" to Pair({ Icons.Outlined.Palette }, { Icons.Filled.Palette }),
        "square.grid.3x3.square" to Pair({ Icons.Outlined.GridOn }, { Icons.Filled.GridOn }),
        "clock.arrow.circlepath" to Pair({ Icons.Outlined.History }, { Icons.Filled.History }),
        "clock" to Pair({ Icons.Outlined.Schedule }, { Icons.Filled.Schedule }),
        "circle.lefthalf.striped.horizontal" to Pair({ Icons.Outlined.Gradient }, { Icons.Filled.Gradient }),
        "drop.fill" to Pair({ Icons.Outlined.FormatColorFill }, { Icons.Filled.FormatColorFill }),
        "drop" to Pair({ Icons.Outlined.WaterDrop }, { Icons.Filled.WaterDrop }),
        "triangle" to Pair({ Icons.Outlined.ChangeHistory }, { Icons.Filled.ChangeHistory }),
        "hand.point.up.left" to Pair({ Icons.Outlined.TouchApp }, { Icons.Filled.TouchApp }),
        "sun.max" to Pair({ Icons.Outlined.WbSunny }, { Icons.Filled.WbSunny }),
        "flame" to Pair({ Icons.Outlined.LocalFireDepartment }, { Icons.Filled.LocalFireDepartment }),
        "humidity" to Pair({ Icons.Outlined.Water }, { Icons.Filled.Water }),
        "pencil.tip" to Pair({ Icons.Outlined.Draw }, { Icons.Filled.Draw }),
        "scribble" to Pair({ Icons.Outlined.Gesture }, { Icons.Filled.Gesture }),
        "point.topleft.down.to.point.bottomright.curvepath" to Pair({ Icons.Outlined.ShowChart }, { Icons.Filled.ShowChart }),
        "point.3.connected.trianglepath.dotted" to Pair({ Icons.Outlined.Polyline }, { Icons.Filled.Polyline }),
        "plus.circle" to Pair({ Icons.Outlined.AddCircleOutline }, { Icons.Filled.AddCircleOutline }),
        "minus.circle" to Pair({ Icons.Outlined.RemoveCircleOutline }, { Icons.Filled.RemoveCircleOutline }),
        "textformat" to Pair({ Icons.Outlined.TextFormat }, { Icons.Filled.TextFormat }),
        "character.cursor.ibeam" to Pair({ Icons.Outlined.Title }, { Icons.Filled.Title }),
        "character.textbox" to Pair({ Icons.Outlined.TextFields }, { Icons.Filled.TextFields }),
        "cursorarrow" to Pair({ Icons.Outlined.NearMe }, { Icons.Filled.NearMe }),
        "cursorarrow.rays" to Pair({ Icons.Outlined.Mouse }, { Icons.Filled.Mouse }),
        "rectangle" to Pair({ Icons.Outlined.Rectangle }, { Icons.Filled.Rectangle }),
        "circle" to Pair({ Icons.Outlined.Circle }, { Icons.Filled.Circle }),
        "triangle.fill" to Pair({ Icons.Filled.ChangeHistory }, { Icons.Filled.ChangeHistory }),
        "hexagon" to Pair({ Icons.Outlined.Hexagon }, { Icons.Filled.Hexagon }),
        "line.diagonal" to Pair({ Icons.Outlined.HorizontalRule }, { Icons.Filled.HorizontalRule }),
        "star" to Pair({ Icons.Outlined.Star }, { Icons.Filled.Star }),
        "hand.raised" to Pair({ Icons.Outlined.PanTool }, { Icons.Filled.PanTool }),
        "rotate.right" to Pair({ Icons.Outlined.RotateRight }, { Icons.Filled.RotateRight }),
        "magnifyingglass" to Pair({ Icons.Outlined.Search }, { Icons.Filled.Search }),
    )

    /** Whether there's an icon for the SF Symbol [symbol]. */
    fun has(symbol: String): Boolean = symbol in icons

    /** The icon for the SF Symbol [symbol], filled or outlined; `null` when there's none. */
    fun icon(symbol: String, filled: Boolean = false): ImageVector? = icons[symbol]?.let { if (filled) it.filled() else it.outlined() }
}
