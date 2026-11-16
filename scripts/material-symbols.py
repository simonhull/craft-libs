#!/usr/bin/env python3
"""Regenerate craftkit's Material Symbols from Google's pinned SVGs.

craftkit (crates/mobile/android/craftkit) draws Material Symbols Rounded, weight 400, grade 0,
optical size 24: as Compose ImageVectors in `ui/Symbols.kt` (each in its outlined style, fill 0,
and its filled one, fill 1), and as the vector drawables `res/drawable/craft_ic_*.xml` for the app
bar and the notification. No font is bundled; the paths are copied from the SVGs unmodified.

    python3 -I scripts/material-symbols.py /path/to/new-empty-dir

The SVGs are downloaded into that directory (it must be new or empty), checked to be one plain
path each, then the Kotlin and the drawables are written into the checkout. `--reuse` generates
again from SVGs this script already downloaded there. To add a symbol, add it to SYMBOLS (its
name as on fonts.google.com/icons) and run this again.

Source: github.com/google/material-design-icons at COMMIT, Apache-2.0 (see ATTRIBUTION.md).
"""

import argparse
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

COMMIT = "10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7"
STYLE = "materialsymbolsrounded"
BASE = f"https://raw.githubusercontent.com/google/material-design-icons/{COMMIT}/symbols/web"

# Every symbol craftkit and the Gallery draw. `True` mirrors it in right-to-left layouts.
SYMBOLS = {
    "add": False,
    "add_circle": False,
    "brush": False,
    "change_history": False,
    "check": False,
    "check_circle": False,
    "chevron_right": True,
    "circle": False,
    "close": False,
    "colorize": False,
    "content_copy": False,
    "content_paste": False,
    "create_new_folder": False,
    "crop": False,
    "dashboard": False,
    "delete": False,
    "do_not_disturb_on": False,
    "drag_handle": False,
    "draw": False,
    "edit": False,
    "error": False,
    "expand_more": False,
    "file_copy": False,
    "filter_none": False,
    "folder_open": False,
    "format_color_fill": False,
    "format_paint": False,
    "gesture": False,
    "gradient": False,
    "grid_on": False,
    "grid_view": False,
    "handyman": False,
    "healing": False,
    "help": True,
    "hexagon": False,
    "highlight_mouse_cursor": False,
    "history": False,
    "horizontal_rule": False,
    "image": False,
    "info": False,
    "layers": False,
    "library_add": False,
    "local_fire_department": False,
    "menu": False,
    "mouse": False,
    "movie": False,
    "navigate_before": True,
    "navigate_next": True,
    "near_me": False,
    "open_with": False,
    "palette": False,
    "pan_tool": False,
    "pause": False,
    "pentagon": False,
    "picture_in_picture": False,
    "play_arrow": False,
    "polyline": False,
    "radio_button_unchecked": False,
    "rectangle": False,
    "redo": True,
    "rotate_right": False,
    "save": False,
    "schedule": False,
    "search": False,
    "select_all": False,
    "share": False,
    "show_chart": False,
    "skip_next": False,
    "skip_previous": False,
    "star": False,
    "sticky_note_2": False,
    "straighten": False,
    "swap_horiz": False,
    "swap_vert": False,
    "tag": False,
    "text_fields": False,
    "text_format": False,
    "title": False,
    "touch_app": False,
    "tune": False,
    "undo": True,
    "view_sidebar": True,
    "visibility": False,
    "visibility_off": False,
    "wand_shine": False,
    "wand_stars": False,
    "warning": False,
    "water": False,
    "water_drop": False,
    "wb_sunny": False,
}

# craftkit's drawables (app bar buttons, the notification): outlined, white, as Android tints them.
DRAWABLES = {
    "craft_ic_hidden": "visibility_off",
    "craft_ic_layers": "layers",
    "craft_ic_new": "add",
    "craft_ic_open": "folder_open",
    "craft_ic_paste": "content_paste",
    "craft_ic_redo": "redo",
    "craft_ic_save": "save",
    "craft_ic_undo": "undo",
    "craft_ic_visible": "visibility",
}

CRAFTKIT = Path(__file__).resolve().parent.parent / "crates/mobile/android/craftkit/src/main"
KOTLIN = CRAFTKIT / "kotlin/dev/craft/kit/ui/Symbols.kt"
DRAWABLE_DIR = CRAFTKIT / "res/drawable"

# An SVG as the repository publishes it: one path in a 0 -960 960 960 box, nothing else. Anything
# else is refused rather than interpreted.
SVG = re.compile(
    r'<svg xmlns="http://www\.w3\.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24">'
    r'<path d="([MmLlHhVvCcSsQqTtAaZz0-9.,\- ]{1,20000})"/></svg>\s*'
)
NAME = re.compile(r"[a-z0-9_]{1,64}")
MAX_SVG = 64 * 1024


def fetch(url):
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError("refusing to fetch a non-HTTPS URL")
    with urllib.request.urlopen(url, timeout=60) as response:
        body = response.read(MAX_SVG + 1)
    if len(body) > MAX_SVG:
        raise ValueError(f"{url} is larger than {MAX_SVG} bytes")
    return body


def file_name(symbol, fill):
    return f"{symbol}_fill1_24px.svg" if fill else f"{symbol}_24px.svg"


def download(directory):
    for symbol in SYMBOLS:
        for fill in (False, True):
            name = file_name(symbol, fill)
            url = f"{BASE}/{symbol}/{STYLE}/{name}"
            try:
                (directory / name).write_bytes(fetch(url))
            except urllib.error.HTTPError as error:
                sys.exit(f"{url}: HTTP {error.code}")


def path_data(directory, symbol, fill):
    text = (directory / file_name(symbol, fill)).read_text(encoding="utf-8")
    match = SVG.fullmatch(text)
    if match is None:
        sys.exit(f"{file_name(symbol, fill)} isn't a single-path Material Symbols SVG")
    return match.group(1)


def pascal(symbol):
    return "".join(part[:1].upper() + part[1:] for part in symbol.split("_"))


def kotlin(directory):
    lines = [
        "// Generated by scripts/material-symbols.py: run it again rather than editing this file.",
        f"// Material Symbols Rounded (weight 400, grade 0, optical size 24) from google/material-design-icons",
        f"// at {COMMIT}, Apache-2.0 (see ATTRIBUTION.md).",
        "package dev.craft.kit.ui",
        "",
        "import androidx.compose.ui.graphics.Color",
        "import androidx.compose.ui.graphics.SolidColor",
        "import androidx.compose.ui.graphics.vector.ImageVector",
        "import androidx.compose.ui.graphics.vector.addPathNodes",
        "import androidx.compose.ui.unit.dp",
        "import java.util.concurrent.ConcurrentHashMap",
        "",
        "/**",
        " * Material Symbols Rounded at 24dp, weight 400: each in its outlined style (fill 0) and as",
        " * `…Filled` (fill 1). Each is built when first drawn and kept; R8 drops the ones never used.",
        " */",
        "object Symbols {",
    ]
    for symbol, mirrored in SYMBOLS.items():
        mirror = ", autoMirror = true" if mirrored else ""
        for fill in (False, True):
            prop = pascal(symbol) + ("Filled" if fill else "")
            key = symbol + ("_fill1" if fill else "")
            lines.append(f'    val {prop}: ImageVector get() = symbol("{key}", "{path_data(directory, symbol, fill)}"{mirror})')
        lines.append("")
    lines[-1] = "}"
    lines += [
        "",
        "private val built = ConcurrentHashMap<String, ImageVector>()",
        "",
        "/** Symbol [name] from its SVG [pathData], drawn in a 960-unit box whose top is at y = -960. */",
        "private fun symbol(name: String, pathData: String, autoMirror: Boolean = false): ImageVector = built.getOrPut(name) {",
        "    ImageVector.Builder(name, 24.dp, 24.dp, viewportWidth = 960f, viewportHeight = 960f, autoMirror = autoMirror)",
        "        .addGroup(translationY = 960f)",
        "        .addPath(addPathNodes(pathData), fill = SolidColor(Color.Black))",
        "        .build()",
        "}",
        "",
    ]
    KOTLIN.write_text("\n".join(lines), encoding="utf-8")


def drawables(directory):
    for drawable, symbol in DRAWABLES.items():
        mirrored = "true" if SYMBOLS[symbol] else "false"
        xml = (
            f"<!-- Material Symbols Rounded `{symbol}`, from scripts/material-symbols.py (Apache-2.0, see ATTRIBUTION.md). -->\n"
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="24dp" android:height="24dp" android:viewportWidth="960" android:viewportHeight="960"\n'
            f'    android:autoMirrored="{mirrored}">\n'
            '    <group android:translateY="960">\n'
            f'        <path android:fillColor="@android:color/white" android:pathData="{path_data(directory, symbol, False)}" />\n'
            "    </group>\n"
            "</vector>\n"
        )
        (DRAWABLE_DIR / f"{drawable}.xml").write_text(xml, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("directory", type=Path, help="a new or empty directory for the downloaded SVGs")
    parser.add_argument("--reuse", action="store_true", help="generate from SVGs already downloaded there")
    args = parser.parse_args()
    for symbol in SYMBOLS:
        if NAME.fullmatch(symbol) is None:
            sys.exit(f"bad symbol name {symbol!r}")
    directory = args.directory.resolve()
    if directory.is_relative_to(Path(__file__).resolve().parent.parent):
        sys.exit("download outside the checkout")
    if not args.reuse:
        directory.mkdir(parents=True, exist_ok=True)
        if any(directory.iterdir()):
            sys.exit(f"{directory} isn't empty (use --reuse to generate from what's there)")
        download(directory)
    kotlin(directory)
    drawables(directory)
    print(f"{len(SYMBOLS)} symbols -> {KOTLIN}; {len(DRAWABLES)} drawables -> {DRAWABLE_DIR}")


if __name__ == "__main__":
    main()
