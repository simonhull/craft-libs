//! Every primitive with an example: the reference people and agents build panels from.

use std::collections::BTreeMap;
use std::fmt::Write as _;

use serde::Serialize;

use super::{
    Choice, ChoiceOption, Edit, EditValue, FrameRange, Icon, ItemAction, ItemList, LiveValue, Menu, MenuBar, MenuEntry, Message, Node, Number, Panel,
    PanelInfo, PanelRole, Phase, Position, Progress, Published, Rate, Row, Scale, Section, Status, TimeFormat, Toggle, Tool, ToolPalette, ToolSlot,
    Transport, Unit,
};

/// The catalogue's format version; bump it when a node's JSON changes.
const VERSION: u32 = 1;

/// One primitive: what it is for, its fields, what it sends back, and examples of both.
#[derive(Serialize)]
struct Primitive {
    name: &'static str,
    about: &'static str,
    fields: &'static str,
    sends: &'static str,
    example: Node,
    /// One edit it sends, as the shell sends it; `None` for a node that sends none.
    edit: Option<Message>,
}

/// One piece of chrome the shell draws for the app (the menu bar, the status): what it is, its
/// fields, the request kind that carries it, and what the shell sends back.
#[derive(Serialize)]
struct Chrome {
    name: &'static str,
    about: &'static str,
    fields: &'static str,
    /// The request kind that carries it.
    kind: i32,
    sends: &'static str,
    example: ChromeExample,
    /// Messages it sends, as the shell sends them (`Control::parse` reads each).
    messages: Vec<serde_json::Value>,
}

/// A chrome example, serialized as its own type (field order kept).
#[derive(Serialize)]
#[serde(untagged)]
enum ChromeExample {
    MenuBar(MenuBar),
    Status(Status),
}

/// What a shell's shortcut parser must agree with: the named keys a shortcut prints, and texts with
/// what `Shortcut::parse` makes of them (`null`: refused).
#[derive(Serialize)]
struct Shortcuts {
    named_keys: Vec<String>,
    cases: Vec<ShortcutCase>,
}

#[derive(Serialize)]
struct ShortcutCase {
    text: &'static str,
    parsed: Option<&'static str>,
}

/// The whole catalogue, as `ui.json` holds it.
#[derive(Serialize)]
struct Catalogue {
    version: u32,
    primitives: Vec<Primitive>,
    chrome: Vec<Chrome>,
    shortcuts: Shortcuts,
}

/// An edit to a control of the `layers` panel.
fn edit(control: &str, phase: Phase, gesture: u64, value: EditValue) -> Message {
    edit_in("layers", control, phase, gesture, value)
}

/// An edit to a control of `panel`.
fn edit_in(panel: &str, control: &str, phase: Phase, gesture: u64, value: EditValue) -> Message {
    Message::Edit(Edit { panel: panel.into(), control: control.into(), phase, gesture: gesture.into(), value })
}

fn examples() -> Vec<Primitive> {
    let mut out = Vec::new();
    if let Ok(n) = Number::new("size", "Size", 1.0..=5000.0, 24.0).and_then(|n| n.step(1.0).unit(Unit::Pixels).scale(Scale::Log)) {
        out.push(Primitive {
            name: "number",
            about: "A value in a range: a slider, with the value shown beside it; tap the value to type one.",
            fields: "`value` within `min`..=`max`; `step` snaps it (`null`: continuous); `scale: \"log\"` spreads the slider by ratio, for a wide range such as a brush size (needs `min` above 0; left out, the slider is linear); `unit` is `none`, `percent` (a 0..=1 value shown as 0–100 %), `pixels` or `degrees`; `enabled: false` greys it out. Values and edits are in the number's own units whatever the scale.",
            sends: "`number` edits: `begin`, `change` while dragging, then `commit` (or `cancel`); a typed value is one `commit`.",
            example: Node::Number(n),
            edit: Some(edit_in("brush", "size", Phase::Change, 7, EditValue::Number(120.0))),
        });
    }
    out.push(Primitive {
        name: "toggle",
        about: "On or off: a switch.",
        fields: "`value`; `enabled: false` greys it out.",
        sends: "one `toggle` edit, `commit`.",
        example: Node::Toggle(Toggle::new("visible", "Visible", true)),
        edit: Some(edit("visible", Phase::Commit, 8, EditValue::Toggle(false))),
    });
    let blend = [ChoiceOption::new("normal", "Normal"), ChoiceOption::new("multiply", "Multiply"), ChoiceOption::new("screen", "Screen")];
    if let Ok(c) = Choice::new("blend", "Blend Mode", "normal", blend) {
        out.push(Primitive {
            name: "choice",
            about: "One of several options: segmented for up to 4, a menu for more.",
            fields: "`value` is the chosen option's `id`; option ids are unique; `enabled: false` greys it out.",
            sends: "one `choice` edit with the option's `id`, `commit`.",
            example: Node::Choice(c),
            edit: Some(edit("blend", Phase::Commit, 9, EditValue::Choice("multiply".into()))),
        });
    }
    out.push(Primitive {
        name: "section",
        about: "A titled group of other nodes; the user can collapse it.",
        fields: "`children` are any nodes; `collapsed` is how it starts.",
        sends: "nothing itself; its children send their own edits.",
        example: Node::Section(Section::new("layer", "Layer", vec![Node::Toggle(Toggle::new("locked", "Lock", false))])),
        edit: None,
    });
    out.push(Primitive {
        name: "item_list",
        about: "Rows of items such as layers, top to bottom: tap to select, swipe to hide, long-press for Rename and the row's own actions, drag to reorder. The list's own actions (New Layer) are icon buttons in its footer. Select beside the list's actions picks several rows, tap by tap, until Done; with a keyboard, Shift-tap selects a range and Command-tap adds or removes a row.",
        fields: "each row's `id` is the app's own and unique in the list; `depth` indents it (inside groups); `visible: null` means it can't be hidden; `reorderable` allows dragging. A row's `actions` (left out: none) are what the user can do to it, in its context menu after Rename: each has an `id` unique in the row, a `label`, an `icon` (an SF Symbol name, or `null`) and `destructive` (tinted red, and a trailing swipe action too); `icon` and `destructive` may be left out. `rename: \"no\"` takes Rename… away from a row with no name of its own to change (an open document); left out, a row can be renamed. The list's own `actions` (left out: none) are what the user can do to the list rather than to one row, as icon buttons in its footer: the same fields, `id`s unique among them; the `label` names the button for accessibility and as its tooltip, and shows in place of a missing `icon`.",
        sends: "`select`, `set_visible`, `rename`, `action`, `list_action` and (when reorderable) `move` edits, each one `commit`, naming rows by their `id`. A `select` has a `mode`: `replace` (a plain tap; also when left out), `toggle` (add the row or take it out) or `range` (from the last row selected to this one). An `action` names the row and the action's `id`: `{\"kind\":\"action\",\"value\":{\"row\":2,\"action\":\"delete\"}}`. A `list_action` names the list action's `id` alone: `{\"kind\":\"list_action\",\"value\":{\"action\":\"new_layer\"}}`. A `move` names the row dragged; an app moves the whole selection when that row is one of several selected.",
        example: Node::ItemList(
            ItemList::new("layers", vec![example_row(2, "Sky").selected(true), example_row(1, "Background")])
                .reorderable(true)
                .actions(vec![ItemAction::new("new_layer", "New Layer").icon(Some("plus"))]),
        ),
        edit: Some(edit("layers", Phase::Commit, 10, EditValue::Move { row: 1.into(), target: 2.into(), position: Position::Above })),
    });
    if let Ok(palette) = example_palette() {
        out.push(Primitive {
            name: "tool_palette",
            about: "The app's tools, in a panel with the `rail` role: a vertical Liquid Glass rail at the canvas's leading edge. Tap a tool to select it; long-press a slot (a small corner mark says it has more) for its flyout of the other tools; double-tap the selected tool, or the rail's options button, for its options.",
            fields: "`slots`, top to bottom, each with `tools`: the slot shows the selected tool when it holds it, else its first. A tool has an `id` (unique in the palette), a `label`, an `icon` (`symbol`, an SF Symbol name; `letter`, shown when the platform has no such symbol; the label's first letter when neither works) and a `shortcut` or `null`. `selected` is one of the tools. `options` names the app's Tool panel for the selected tool's options; without one, `fallback_options` is a command that shows them the app's own way; both `null`: no options.",
            sends: "one `choice` edit with the tool's `id`, `commit`, when a tool is tapped or picked from a flyout. Options open the `options` panel as a popover from the rail, or send `{\"action\":\"command\",\"id\":…}` with `fallback_options`.",
            example: Node::ToolPalette(palette),
            edit: Some(edit_in("tools", "palette", Phase::Commit, 11, EditValue::Choice("pencil".into()))),
        });
    }
    if let Ok(transport) = example_transport() {
        out.push(Primitive {
            name: "transport",
            about: "A transport bar, in a panel with the `transport` role: a floating Liquid Glass bar above the bottom toolbar while the app offers it, hidden while the keyboard is up. Buttons go to the start, step back, play or pause, step forward and go to the end; a scrubber drags the playhead, with the work area shaded; a label shows the time. While it plays, its position moves without the panel being described again (request kind 17, below).",
            fields: "`position` is the playhead's frame, counted from 0, below `duration` (at least 1 frame). `rate` is frames per second, above 0 and not necessarily whole (`29.97`). `format` says how the label shows a time, and only that: `frames` (the frame counted from 1, of the duration: `12 / 30`; also when left out) or `timecode` (`HH:MM:SS:FF` at `rate`). `playing` shows Pause in place of Play. `range` is the work area (the loop region) as `[start, end]`, `start` inclusive and `end` exclusive, not empty and ending at `duration` at most; `null` or left out for none. `enabled: false` greys it out.",
            sends: "`seek` edits from the scrubber, with the `frame`: `begin`, `change` while scrubbing, then `commit` at release (or `cancel`). `transport` edits from the buttons, each one `commit`, naming the action: `play`, `pause`, `stop`, `step_back`, `step_forward`, `to_start` or `to_end`, as `{\"kind\":\"transport\",\"value\":\"step_forward\"}`. What Stop does beyond pausing, and whether stepping pauses, are the app's rules.",
            example: Node::Transport(transport),
            edit: Some(edit_in("timeline", "transport", Phase::Change, 12, EditValue::Seek { frame: 12 })),
        });
    }
    out
}

/// A transport for the catalogue: paused on frame 12 (counted from 1) of 30 at 24 fps, with a
/// work area of the first 24 frames.
fn example_transport() -> Result<Transport, super::UiError> {
    Ok(Transport::new("transport", 11, 30, Rate::new(24.0)?)?.range(Some(FrameRange::new(0, 24)?))?.format(TimeFormat::Frames))
}

/// A layer row for the catalogue, with a plain and a destructive action.
fn example_row(id: u64, title: &str) -> Row {
    let actions = vec![
        ItemAction::new("duplicate", "Duplicate").icon(Some("plus.square.on.square")),
        ItemAction::new("delete", "Delete").icon(Some("trash")).destructive(true),
    ];
    Row::new(id, title).subtitle("Pixel").visible(Some(true)).actions(actions)
}

/// A palette for the catalogue: a one-tool slot, a slot with a flyout, a letter-only icon, and
/// options in a Tool panel.
fn example_palette() -> Result<ToolPalette, super::UiError> {
    let slots = vec![
        ToolSlot::one(
            Tool::new("move", "Move", Icon::symbol("arrow.up.and.down.and.arrow.left.and.right").or_letter('V')).shortcut("V".parse().ok()),
        ),
        ToolSlot::new(vec![
            Tool::new("brush", "Brush", Icon::symbol("paintbrush.pointed").or_letter('B')).shortcut("B".parse().ok()),
            Tool::new("pencil", "Pencil", Icon::symbol("pencil").or_letter('N')).shortcut("N".parse().ok()),
        ]),
        ToolSlot::one(Tool::new("smudge", "Smudge", Icon::letter('S'))),
    ];
    Ok(ToolPalette::new("palette", slots, "brush")?.options(Some("brush".into())).fallback_options(Some("window.toggle.optionsBar".into())))
}

/// A menu bar for the catalogue: a command with a shortcut, a disabled one, a separator, a
/// checked item and a submenu.
fn example_menu_bar() -> MenuBar {
    let undo = MenuEntry::command("edit.undo", "Undo").shortcut("Cmd+Z".parse().ok());
    let redo = MenuEntry::command("edit.redo", "Redo").shortcut("Cmd+Shift+Z".parse().ok()).enabled(false);
    let rulers = MenuEntry::command("view.rulers", "Rulers").shortcut("Cmd+R".parse().ok()).checked(Some(true));
    let flip = MenuEntry::command("image.flip_horizontal", "Flip Horizontal");
    let menus = vec![
        Menu::new("Edit", vec![undo.into(), redo.into(), MenuEntry::Separator, MenuEntry::submenu("Transform", vec![flip.into()])])
            .role(Some(super::MenuRole::Edit)),
        Menu::new("View", vec![rulers.into()]).role(Some(super::MenuRole::View)),
        Menu::new("Layer", vec![MenuEntry::command("layer.new", "New Layer").shortcut("Cmd+Shift+N".parse().ok()).into()]),
    ];
    MenuBar::new(menus).unwrap_or_default()
}

/// A status for the catalogue: an error, and a job with a Cancel button.
fn example_status() -> Status {
    Status::new()
        .error("Couldn't open b.psd: not a Photoshop file")
        .message_id(7)
        .progress(Progress::new("Exporting a.png").fraction(0.4).cancel("job.cancel"))
}

fn chrome() -> Vec<Chrome> {
    let status = Chrome {
        name: "status",
        about: "What the app is telling the user: a message as a transient toast at the top (red for an error), and a long job as a progress capsule with a Cancel button. `Platform::set_status` sends it whenever it changes (request kind 16), and again when the shell restarts.",
        fields: "`message` (`null` for none): its `text`, its `tone` (`info` or `error`) and an `id` (0 when left out). Give each new message a new id (`Status::message_id`) so the same text said again shows again, and keep the id while the message stands: new text with the same id (a countdown) updates the toast on screen in place, without showing it again, and a toast the user dismissed stays dismissed. Without an id (0), a message shows when its text or tone changes. `progress` (`null` for none): a `label`, a `fraction` from 0 to 1 (`null` while unknown) and `cancel`, a command id or `null` for a job that can't be stopped.",
        kind: 16,
        sends: "the `cancel` command when the user taps Cancel.",
        example: ChromeExample::Status(example_status()),
        messages: vec![serde_json::json!({"action": "command", "id": "job.cancel"})],
    };
    vec![
        Chrome {
            name: "menu_bar",
            about: "The app's menus, in the iPad menu bar (pointer at the top edge, or hold ⌘) and a toolbar menu for touch. `Platform::set_menu` sends it whenever it changes (request kind 15), and again when the shell restarts.",
            fields: "`menus`, left to right, each a `title`, a `role` and `items`. The `role` (`file`, `edit`, `view`, `window` or `help`; `null` or left out for a menu of the app's own) says which system menu it takes the place of, matched by role and never by its translated title; Window keeps the system's window items after the app's. An item is a `command` (an `id` unique in the whole bar, a `label`, a `shortcut` in the portable form such as `Cmd+Shift+Z` or `null`, `enabled`, and `checked`: `true` or `false` for a check mark, `null` for none), a `separator`, or a `submenu` with a `label` and `items`. Labels are never empty. A shortcut's modifiers are `Ctrl`, `Cmd`, `Alt` and `Shift` (`Ctrl` is the Control key, not ⌘), then one key: a character or a named key (`Enter`, `Tab`, `ArrowUp`, `F5`).",
            kind: 15,
            sends: "a `command` with the item's `id` when the user picks an item with the pointer or by touch, shortcut or not (so Edit › Copy acts on the document even while a text field has the keyboard); a `shortcut` with its `keys` when the user presses them on a hardware keyboard, so the app's own key handling decides, as for the key itself. Enabled and checked are read when a menu opens, so changing them alone redraws nothing.",
            example: ChromeExample::MenuBar(example_menu_bar()),
            messages: vec![
                serde_json::json!({"action": "command", "id": "image.flip_horizontal"}),
                serde_json::json!({"action": "shortcut", "keys": "Cmd+Z"}),
            ],
        },
        status,
    ]
}

/// The catalogue as JSON: `{version, primitives: [{name, about, fields, sends, example, edit}],
/// chrome: [{name, about, fields, kind, sends, example, messages}]}`.
#[must_use]
pub fn catalogue_json() -> String {
    let shortcuts = Shortcuts {
        named_keys: super::named_keys(),
        cases: super::command::PARSE_CASES.iter().map(|&(text, parsed)| ShortcutCase { text, parsed }).collect(),
    };
    let catalogue = Catalogue { version: VERSION, primitives: examples(), chrome: chrome(), shortcuts };
    let mut s = serde_json::to_string_pretty(&catalogue).unwrap_or_default();
    s.push('\n');
    s
}

/// The catalogue as Markdown, for people.
#[must_use]
pub fn catalogue_markdown() -> String {
    let mut s = format!(
        "# craft-mobile UI primitives (v{VERSION})\n\n\
         Generated by `UPDATE_CATALOGUE=1 cargo test -p craft-mobile`. Do not edit.\n\n\
         An app describes each native panel as a list of these nodes (`craft_mobile::ui`), and the \
         shell draws them with the platform's own controls. A node says what a control is, never \
         where it goes. Every node has an `id`, unique in its panel.\n\n\
         When the user changes a control, the shell sends an edit: the panel, the control's `id`, \
         a phase (`begin`, `change`, `commit` or `cancel`), a gesture number shared by every edit \
         of one drag, and the value. The app applies it and describes the panel again; if it \
         rejects the edit, the shell gets the panel again unchanged and the control goes back to \
         the app's value.\n\n\
         A shell sends edits only for the user's own gestures, never while showing a value the app \
         sent: a rejected edit is answered with the old value, and an edit for that would loop.\n"
    );
    for e in examples() {
        let json = serde_json::to_string_pretty(&e.example).unwrap_or_default();
        let _ = write!(s, "\n## `{}`\n\n{}\n\n**Fields:** {}\n\n```json\n{json}\n```\n\n**Sends:** {}\n", e.name, e.about, e.fields, e.sends);
        if let Some(edit) = &e.edit {
            let _ = write!(s, "\nFor example:\n\n```json\n{}\n```\n", serde_json::to_string(edit).unwrap_or_default());
        }
    }
    s.push_str(&wire_markdown());
    s.push_str(&chrome_markdown());
    s
}

/// The chrome the shell draws, and the messages it sends about it.
fn chrome_markdown() -> String {
    let mut s = String::from(
        "\n## Chrome\n\n\
         A shell that draws parts of the app's chrome natively says so each time it starts the app, \
         before it says which panels are on screen (`CraftApp::shell`); the app then hides its own \
         versions. The features are `panels`, `menus`, `rail` and `status`; a name the app doesn't \
         know is ignored:\n\n```json\n{\"action\":\"shell\",\"features\":[\"panels\",\"menus\",\"rail\",\"status\"]}\n```\n\n\
         A `command` without `params` runs the app's command as its menu item does \
         (`CraftApp::command`); with `params` it is the app's `Action::Command`, as before. A \
         `shortcut` goes to the app's own key handling (`CraftApp::shortcut`).\n",
    );
    for c in chrome() {
        let json = serde_json::to_string_pretty(&c.example).unwrap_or_default();
        let _ = write!(
            s,
            "\n### `{}` (request kind {})\n\n{}\n\n**Fields:** {}\n\n```json\n{json}\n```\n\n**Sends:** {}\n",
            c.name, c.kind, c.about, c.fields, c.sends
        );
        if !c.messages.is_empty() {
            let messages: Vec<String> = c.messages.iter().map(|m| serde_json::to_string(m).unwrap_or_default()).collect();
            let _ = write!(s, "\nFor example:\n\n```json\n{}\n```\n", messages.join("\n"));
        }
    }
    s
}

/// How panels and edits travel between the app and the shell.
fn wire_markdown() -> String {
    let layers = PanelInfo { id: "layers".into(), title: "Layers".into(), icon: "square.3.layers.3d".into(), role: PanelRole::Inspector };
    let brush = PanelInfo { id: "brush".into(), title: "Brush".into(), icon: "paintbrush.pointed".into(), role: PanelRole::Tool };
    let panel = Panel::new("layers", "Layers", PanelRole::Inspector, vec![Node::Toggle(Toggle::new("visible", "Visible", true))]);
    let published = Published { panels: vec![layers, brush], open: BTreeMap::from([("layers".into(), panel)]) };
    let open = Message::OpenPanels { open: vec!["layers".into()] };
    let edit = edit("visible", Phase::Commit, 3, EditValue::Toggle(false));
    let mut s = String::from(
        "\n## Wire\n\n\
         The app sends the shell its panels (request kind 13) whenever they change: `panels`, every \
         panel it offers, and `open`, the open ones described, by id. Each entry of `panels` has an \
         `id`, a `title`, an `icon` (an SF Symbol name; Android maps it to a Material icon) and a \
         `role`: `inspector` slides in beside the canvas, `tool` is a popover from its toolbar \
         button, `rail` is a vertical rail at the canvas's leading edge, always on screen (its \
         `tool_palette`), and `transport` is a floating bar above the bottom toolbar, on screen \
         while the app offers it (its `transport`). The shell counts a rail or transport it shows \
         among the panels on screen.\n\n",
    );
    let _ = write!(s, "```json\n{}\n```\n", serde_json::to_string_pretty(&published).unwrap_or_default());
    s.push_str(
        "\nThe app can also ask the shell to open one of its panels (request kind 14, the panel's \
         `id` as text; `Platform::open_panel`), for its own way in to a panel the shell now shows \
         natively, such as a menu item. The shell opens it in its role's place, as its toolbar \
         button would, and then says which panels are on screen (`open_panels`, below) as usual; an id the app doesn't offer opens \
         nothing. Unlike the panels, it isn't sent again to a shell that starts listening later.\n",
    );
    let live = [LiveValue { panel: "timeline".into(), control: "transport".into(), position: 12 }];
    let _ = write!(
        s,
        "\nWhile a transport plays, only its position changes from frame to frame. Then the app sends \
         the positions alone (request kind 17), not the panels: a list with an entry for each \
         transport whose `position` changed since the shell last heard it, by panel and control \
         `id`. The shell shows it in place of the described `position` until the next description, \
         which carries the current positions itself. Anything else that changes sends the panels \
         as usual. Unlike the panels, it isn't sent again to a shell that starts listening later.\n\n```json\n{}\n```\n",
        serde_json::to_string(&live).unwrap_or_default()
    );
    let _ = write!(
        s,
        "\nThe shell sends messages through the same call as its actions (`craft_action`, `CraftNative.action`). It says which panels are on screen, and gets them all again:\n\n```json\n{}\n```\n",
        serde_json::to_string(&open).unwrap_or_default()
    );
    let _ = write!(
        s,
        "\nAnd it sends edits, one message each; here the user switched Visible off:\n\n```json\n{}\n```\n",
        serde_json::to_string_pretty(&edit).unwrap_or_default()
    );
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    const CRATE: &str = env!("CARGO_MANIFEST_DIR");

    /// The checked-in catalogue, and the Swift tests' copy of it, are what the types produce.
    /// `UPDATE_CATALOGUE=1` rewrites them.
    #[test]
    fn the_catalogue_is_current() {
        let (json, md) = (catalogue_json(), catalogue_markdown());
        let files = [
            (format!("{CRATE}/catalogue/ui.json"), &json),
            (format!("{CRATE}/catalogue/ui.md"), &md),
            (format!("{CRATE}/swift/CraftUI/Tests/CraftUITests/Fixtures/ui.json"), &json),
        ];
        for (path, generated) in &files {
            if std::env::var_os("UPDATE_CATALOGUE").is_some() {
                let dir = std::path::Path::new(path).parent().unwrap();
                std::fs::create_dir_all(dir).unwrap();
                std::fs::write(path, generated).unwrap();
            }
            assert_eq!(&std::fs::read_to_string(path).unwrap_or_default(), *generated, "{path} is stale: run with UPDATE_CATALOGUE=1");
        }
    }

    #[test]
    fn every_example_round_trips() {
        for e in examples() {
            let json = serde_json::to_string(&e.example).unwrap();
            assert_eq!(serde_json::from_str::<Node>(&json).unwrap(), e.example, "{}", e.name);
            if let Some(edit) = &e.edit {
                let json = serde_json::to_vec(edit).unwrap();
                assert_eq!(crate::control::Control::parse(&json).unwrap(), crate::control::Control::Ui(edit.clone()), "{}", e.name);
            }
        }
    }

    /// Each chrome example is what its Rust type produces, and each message parses as a control.
    #[test]
    fn every_chrome_example_is_valid() {
        let menu_bar = chrome().into_iter().find(|c| c.name == "menu_bar").unwrap();
        let json = serde_json::to_string(&menu_bar.example).unwrap();
        assert_eq!(serde_json::from_str::<MenuBar>(&json).unwrap(), example_menu_bar());
        assert_eq!(example_menu_bar().menus().len(), 3, "valid, not the empty default");
        let status = chrome().into_iter().find(|c| c.name == "status").unwrap();
        assert_eq!(serde_json::from_str::<Status>(&serde_json::to_string(&status.example).unwrap()).unwrap(), example_status());
        for c in chrome() {
            for message in &c.messages {
                let json = serde_json::to_vec(message).unwrap();
                assert!(crate::control::Control::parse(&json).is_ok(), "{}: {message}", c.name);
            }
        }
    }

    #[test]
    fn every_primitive_has_an_example() {
        let names: Vec<_> = examples().iter().map(|e| e.name).collect();
        for t in ["section", "number", "toggle", "choice", "item_list", "tool_palette", "transport"] {
            assert!(names.contains(&t), "{t}");
        }
    }
}
