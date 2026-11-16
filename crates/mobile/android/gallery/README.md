# craftkit Gallery (Android)

An Android app that shows every native panel primitive (`number`, `toggle`, `choice`, `section`,
`item_list`, `tool_palette`, `transport`) and the chrome (`menu_bar`, `status`) live, drawn by
craftkit's Material 3 renderer (`dev.craft.kit.ui`), with no Rust and no Craft app behind it. It is
the Android twin of `swift/Gallery`: use it to see how a primitive looks and feels on Android, and
to check what it sends.

The Gallery reads the catalogue that craft-mobile generates, `crates/mobile/catalogue/ui.json`
(copied into its assets at build time; regenerate it with `UPDATE_CATALOGUE=1 cargo test -p
craft-mobile`), so it always shows the examples the Rust side documents in `catalogue/ui.md`.

The sidebar lists each primitive and piece of chrome, plus **Everything**: all examples in one
panel, as an app's inspector would hold them. For each one:

- The panel is in a side sheet, as `CraftScaffold` shows an inspector; the app bar's popover button
  shows it as a tool popover, as the shell shows a tool panel.
- The Gallery plays the app: each edit is applied to its own copy of the example, so the controls
  respond, and a cancelled drag puts that control's value back.
- **Sent** lists every edit and command, newest first, as the JSON the app would receive through
  `CraftNative.action`.

**tool_palette** also shows the palette as the shell's rail, at the detail's leading edge: tap,
long-press a slot for its flyout, double-tap or the options button for a stand-in Tool panel.
**transport** also shows the floating bar; Play moves the playhead by live positions (wire kind
17), as PhotoCraft plays a timeline. **menu_bar** puts the catalogue's menus in an app bar, wide and
folded. **status** shows the catalogue's status, with buttons for a message, an error, a job and a
countdown under one message id.

## Running it

With the Android SDK (and `sdk.dir` in `local.properties`, or `ANDROID_HOME`):

```sh
cd crates/mobile/android/gallery
gradle assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start --activity-clear-task -n dev.craft.gallery/.GalleryActivity --es selection item_list
```

`--es selection <name>` opens a primitive by its catalogue name (or `everything`).

craftkit's unit tests (the catalogue's examples decoded, edits encoded as Rust reads them, the
controls' gesture rules) run from here too: `gradle :craftkit:testDebugUnitTest`.
