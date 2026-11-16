package dev.craft.kit.ui

import androidx.compose.ui.graphics.vector.ImageVector

/**
 * The catalogue's SF Symbol names as Material Symbols ([Symbols]), outlined and filled (a selected
 * tool shows the filled one). A name without an icon here shows as a letter where there is one (a tool's), else as
 * text (a list action's label), so a new symbol in an app never breaks the shell; add it here.
 */
object CraftIcons {
    /** An icon in its two styles; made only when first drawn. */
    private class Pair(val outlined: () -> ImageVector, val filled: () -> ImageVector)

    private val icons: Map<String, Pair> = mapOf(
        // Panels and list actions.
        "square.3.layers.3d" to Pair({ Symbols.Layers }, { Symbols.LayersFilled }),
        "doc.on.doc" to Pair({ Symbols.FileCopy }, { Symbols.FileCopyFilled }),
        "hammer" to Pair({ Symbols.Handyman }, { Symbols.HandymanFilled }),
        "film" to Pair({ Symbols.Movie }, { Symbols.MovieFilled }),
        "plus" to Pair({ Symbols.Add }, { Symbols.AddFilled }),
        "folder.badge.plus" to Pair({ Symbols.CreateNewFolder }, { Symbols.CreateNewFolderFilled }),
        "folder" to Pair({ Symbols.FolderOpen }, { Symbols.FolderOpenFilled }),
        "plus.square.on.square" to Pair({ Symbols.LibraryAdd }, { Symbols.LibraryAddFilled }),
        "trash" to Pair({ Symbols.Delete }, { Symbols.DeleteFilled }),
        "xmark" to Pair({ Symbols.Close }, { Symbols.CloseFilled }),
        "eye" to Pair({ Symbols.Visibility }, { Symbols.VisibilityFilled }),
        "eye.slash" to Pair({ Symbols.VisibilityOff }, { Symbols.VisibilityOffFilled }),
        "slider.horizontal.3" to Pair({ Symbols.Tune }, { Symbols.TuneFilled }),
        "square.and.arrow.down" to Pair({ Symbols.Save }, { Symbols.SaveFilled }),
        "square.and.arrow.up" to Pair({ Symbols.Share }, { Symbols.ShareFilled }),
        "arrow.uturn.backward" to Pair({ Symbols.Undo }, { Symbols.UndoFilled }),
        "arrow.uturn.forward" to Pair({ Symbols.Redo }, { Symbols.RedoFilled }),
        "doc.on.clipboard" to Pair({ Symbols.ContentPaste }, { Symbols.ContentPasteFilled }),
        "square.on.square" to Pair({ Symbols.ContentCopy }, { Symbols.ContentCopyFilled }),
        // Tools.
        "arrow.up.and.down.and.arrow.left.and.right" to Pair({ Symbols.OpenWith }, { Symbols.OpenWithFilled }),
        "rectangle.on.rectangle" to Pair({ Symbols.FilterNone }, { Symbols.FilterNoneFilled }),
        "rectangle.dashed" to Pair({ Symbols.HighlightMouseCursor }, { Symbols.HighlightMouseCursorFilled }),
        "circle.dashed" to Pair({ Symbols.RadioButtonUnchecked }, { Symbols.RadioButtonUncheckedFilled }),
        "arrow.left.and.right" to Pair({ Symbols.SwapHoriz }, { Symbols.SwapHorizFilled }),
        "arrow.up.and.down" to Pair({ Symbols.SwapVert }, { Symbols.SwapVertFilled }),
        "lasso" to Pair({ Symbols.Gesture }, { Symbols.GestureFilled }),
        "pentagon" to Pair({ Symbols.Pentagon }, { Symbols.PentagonFilled }),
        "square.dashed.inset.filled" to Pair({ Symbols.SelectAll }, { Symbols.SelectAllFilled }),
        "wand.and.stars" to Pair({ Symbols.WandStars }, { Symbols.WandStarsFilled }),
        "wand.and.rays" to Pair({ Symbols.WandShine }, { Symbols.WandShineFilled }),
        "crop" to Pair({ Symbols.Crop }, { Symbols.CropFilled }),
        "square.split.2x2" to Pair({ Symbols.GridView }, { Symbols.GridViewFilled }),
        "square.split.2x2.fill" to Pair({ Symbols.Dashboard }, { Symbols.DashboardFilled }),
        "photo.artframe" to Pair({ Symbols.Image }, { Symbols.ImageFilled }),
        "eyedropper" to Pair({ Symbols.Colorize }, { Symbols.ColorizeFilled }),
        "ruler" to Pair({ Symbols.Straighten }, { Symbols.StraightenFilled }),
        "note.text" to Pair({ Symbols.StickyNote2 }, { Symbols.StickyNote2Filled }),
        "number" to Pair({ Symbols.Tag }, { Symbols.TagFilled }),
        "bandage" to Pair({ Symbols.Healing }, { Symbols.HealingFilled }),
        "paintbrush.pointed" to Pair({ Symbols.Brush }, { Symbols.BrushFilled }),
        "paintbrush" to Pair({ Symbols.FormatPaint }, { Symbols.FormatPaintFilled }),
        "pencil" to Pair({ Symbols.Edit }, { Symbols.EditFilled }),
        "paintpalette" to Pair({ Symbols.Palette }, { Symbols.PaletteFilled }),
        "square.grid.3x3.square" to Pair({ Symbols.GridOn }, { Symbols.GridOnFilled }),
        "clock.arrow.circlepath" to Pair({ Symbols.History }, { Symbols.HistoryFilled }),
        "clock" to Pair({ Symbols.Schedule }, { Symbols.ScheduleFilled }),
        "circle.lefthalf.striped.horizontal" to Pair({ Symbols.Gradient }, { Symbols.GradientFilled }),
        "drop.fill" to Pair({ Symbols.FormatColorFill }, { Symbols.FormatColorFillFilled }),
        "drop" to Pair({ Symbols.WaterDrop }, { Symbols.WaterDropFilled }),
        "triangle" to Pair({ Symbols.ChangeHistory }, { Symbols.ChangeHistoryFilled }),
        "hand.point.up.left" to Pair({ Symbols.TouchApp }, { Symbols.TouchAppFilled }),
        "sun.max" to Pair({ Symbols.WbSunny }, { Symbols.WbSunnyFilled }),
        "flame" to Pair({ Symbols.LocalFireDepartment }, { Symbols.LocalFireDepartmentFilled }),
        "humidity" to Pair({ Symbols.Water }, { Symbols.WaterFilled }),
        "pencil.tip" to Pair({ Symbols.Draw }, { Symbols.DrawFilled }),
        "scribble" to Pair({ Symbols.Gesture }, { Symbols.GestureFilled }),
        "point.topleft.down.to.point.bottomright.curvepath" to Pair({ Symbols.ShowChart }, { Symbols.ShowChartFilled }),
        "point.3.connected.trianglepath.dotted" to Pair({ Symbols.Polyline }, { Symbols.PolylineFilled }),
        "plus.circle" to Pair({ Symbols.AddCircle }, { Symbols.AddCircleFilled }),
        "minus.circle" to Pair({ Symbols.DoNotDisturbOn }, { Symbols.DoNotDisturbOnFilled }),
        "textformat" to Pair({ Symbols.TextFormat }, { Symbols.TextFormatFilled }),
        "character.cursor.ibeam" to Pair({ Symbols.Title }, { Symbols.TitleFilled }),
        "character.textbox" to Pair({ Symbols.TextFields }, { Symbols.TextFieldsFilled }),
        "cursorarrow" to Pair({ Symbols.NearMe }, { Symbols.NearMeFilled }),
        "cursorarrow.rays" to Pair({ Symbols.Mouse }, { Symbols.MouseFilled }),
        "rectangle" to Pair({ Symbols.Rectangle }, { Symbols.RectangleFilled }),
        "circle" to Pair({ Symbols.Circle }, { Symbols.CircleFilled }),
        "triangle.fill" to Pair({ Symbols.ChangeHistoryFilled }, { Symbols.ChangeHistoryFilled }),
        "hexagon" to Pair({ Symbols.Hexagon }, { Symbols.HexagonFilled }),
        "line.diagonal" to Pair({ Symbols.HorizontalRule }, { Symbols.HorizontalRuleFilled }),
        "star" to Pair({ Symbols.Star }, { Symbols.StarFilled }),
        "hand.raised" to Pair({ Symbols.PanTool }, { Symbols.PanToolFilled }),
        "rotate.right" to Pair({ Symbols.RotateRight }, { Symbols.RotateRightFilled }),
        "magnifyingglass" to Pair({ Symbols.Search }, { Symbols.SearchFilled }),
    )

    /** Every SF Symbol name with an icon. */
    internal val symbols: Set<String> get() = icons.keys

    /** Whether there's an icon for the SF Symbol [symbol]. */
    fun has(symbol: String): Boolean = symbol in icons

    /** The icon for the SF Symbol [symbol], filled or outlined; `null` when there's none. */
    fun icon(symbol: String, filled: Boolean = false): ImageVector? = icons[symbol]?.let { if (filled) it.filled() else it.outlined() }
}
