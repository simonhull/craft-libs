# CraftUI Gallery

An iPad app that shows every CraftUI primitive (`number`, `toggle`, `choice`, `section`,
`item_list`) live, with no Rust and no Craft app behind it. Use it to see how a primitive looks and
feels on iPadOS, and to check what it sends, before an app describes a panel with it.

The Gallery reads the catalogue that craft-mobile generates, `crates/mobile/catalogue/ui.json`
(regenerate it with `UPDATE_CATALOGUE=1 cargo test -p craft-mobile`), so it always shows the
examples the Rust side documents in `catalogue/ui.md`.

The sidebar lists each primitive, plus **Everything**: all examples in one panel, as an app's
inspector would hold them. For each one:

- The panel is in the **inspector** column, as `CraftShell` shows an inspector
  panel; the toolbar's **Popover** button shows it as a tool popover (`CraftPopover`), as the shell shows a tool panel.
- The Gallery plays the app: each edit is applied to its own copy of the example, so the controls
  respond, and a cancelled drag puts that control's value back.
- **Edits Sent** lists every edit, newest first, as the JSON the app would receive through
  `craft_action`.

## Running it

Needs Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project is
generated and not checked in.

```sh
cd crates/mobile/swift/Gallery
xcodegen
open Gallery.xcodeproj   # then run the Gallery scheme on an iPad simulator or device
```

Or from the command line, on a booted iPad simulator:

```sh
xcodebuild build -project Gallery.xcodeproj -scheme Gallery \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Gallery.app
xcrun simctl launch booted dev.craft.Gallery -selection item_list
```

`-selection <name>` opens a primitive by its catalogue name (or `everything`); the Gallery
otherwise reopens the last one picked.
