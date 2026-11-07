//! Every primitive with an example: the reference people and agents build panels from.

use std::collections::BTreeMap;
use std::fmt::Write as _;

use serde::Serialize;

use super::{
    Choice, ChoiceOption, Edit, EditValue, ItemList, Message, Node, Number, Panel, PanelInfo, PanelRole, Phase, Position, Published, Row, Scale,
    Section, Toggle, Unit,
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

/// The whole catalogue, as `ui.json` holds it.
#[derive(Serialize)]
struct Catalogue {
    version: u32,
    primitives: Vec<Primitive>,
}

/// An edit to a control of the `layers` panel.
fn edit(control: &str, phase: Phase, gesture: u64, value: EditValue) -> Message {
    edit_in("layers", control, phase, gesture, value)
}

/// An edit to a control of `panel`.
fn edit_in(panel: &str, control: &str, phase: Phase, gesture: u64, value: EditValue) -> Message {
    Message::Edit(Edit { panel: panel.into(), control: control.into(), phase, gesture, value })
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
        about: "Rows of items such as layers, top to bottom: tap to select, swipe to hide, long-press to rename, drag to reorder.",
        fields: "each row's `id` is the app's own and unique in the list; `depth` indents it (inside groups); `visible: null` means it can't be hidden; `reorderable` allows dragging.",
        sends: "`select`, `set_visible`, `rename` and (when reorderable) `move` edits, each one `commit`, naming rows by their `id`.",
        example: Node::ItemList(
            ItemList::new("layers", vec![Row::new(2, "Sky").subtitle("Pixel").visible(Some(true)).selected(true), Row::new(1, "Background").subtitle("Pixel").visible(Some(true))])
                .reorderable(true),
        ),
        edit: Some(edit("layers", Phase::Commit, 10, EditValue::Move { row: 1, target: 2, position: Position::Above })),
    });
    out
}

/// The catalogue as JSON: `{version, primitives: [{name, about, fields, sends, example, edit}]}`.
#[must_use]
pub fn catalogue_json() -> String {
    let catalogue = Catalogue { version: VERSION, primitives: examples() };
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
         button.\n\n",
    );
    let _ = write!(s, "```json\n{}\n```\n", serde_json::to_string_pretty(&published).unwrap_or_default());
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

    #[test]
    fn every_primitive_has_an_example() {
        let names: Vec<_> = examples().iter().map(|e| e.name).collect();
        for t in ["section", "number", "toggle", "choice", "item_list"] {
            assert!(names.contains(&t), "{t}");
        }
    }
}
