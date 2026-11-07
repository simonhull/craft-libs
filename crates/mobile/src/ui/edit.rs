//! What the shell sends back from native panels.

use serde::{Deserialize, Serialize};

use super::{ControlId, PanelId, RowId};

/// Where a gesture is.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    /// A drag started: open one undo step.
    Begin,
    /// A new value while dragging: preview it, in the same step.
    Change,
    /// The final value: close the step. A tap or a pick sends this alone.
    Commit,
    /// The gesture was abandoned: put back the value from before `Begin`.
    Cancel,
}

/// Above or below a target row.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Position {
    /// Above it.
    Above,
    /// Below it.
    Below,
}

/// The value an edit carries, by the kind of control.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub enum EditValue {
    /// A [`super::Number`]'s value.
    Number(f64),
    /// A [`super::Toggle`]'s value.
    Toggle(bool),
    /// A [`super::Choice`]'s option id.
    Choice(String),
    /// A row was tapped.
    Select {
        /// The row's id.
        row: RowId,
    },
    /// A row's eye was toggled.
    SetVisible {
        /// The row's id.
        row: RowId,
        /// Shown.
        visible: bool,
    },
    /// A row was renamed.
    Rename {
        /// The row's id.
        row: RowId,
        /// Its new name.
        name: String,
    },
    /// A row was dragged next to another.
    Move {
        /// The row moved.
        row: RowId,
        /// The row it was dropped on.
        target: RowId,
        /// Above or below that row.
        position: Position,
    },
}

number_id! {
    /// A gesture's number: every edit of one drag carries the same one, and no two gestures of a
    /// shell's life share one (apps key undo coalescing on it).
    GestureId
}

/// Why an app couldn't apply an [`Edit`]: a message for the log, and a reason to send the panel
/// again so its control shows the app's value.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
#[error("{0}")]
pub struct EditError(String);

impl EditError {
    /// The message.
    #[must_use]
    pub fn message(&self) -> &str {
        &self.0
    }
}

impl From<String> for EditError {
    fn from(message: String) -> Self {
        Self(message)
    }
}

impl From<&str> for EditError {
    fn from(message: &str) -> Self {
        Self(message.to_owned())
    }
}

/// One change from a native panel.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Edit {
    /// The panel.
    pub panel: PanelId,
    /// The control within it.
    pub control: ControlId,
    /// Where the gesture is.
    pub phase: Phase,
    /// Unique per gesture: every edit of one drag carries the same number (apps key undo
    /// coalescing on it).
    pub gesture: GestureId,
    /// The value.
    pub value: EditValue,
}

/// A message from the shell's native panels (as opposed to a [`crate::Action`]).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum Message {
    /// A control changed.
    Edit(Edit),
    /// These panels are on screen now; only they are described.
    OpenPanels {
        /// Their ids.
        open: Vec<PanelId>,
    },
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn an_edit_parses_from_the_shell() {
        let m: Message = serde_json::from_value(json!({
            "action": "edit", "panel": "layers", "control": "opacity", "phase": "change", "gesture": 3,
            "value": {"kind": "number", "value": 0.25}
        }))
        .unwrap();
        assert_eq!(
            m,
            Message::Edit(Edit {
                panel: "layers".into(),
                control: "opacity".into(),
                phase: Phase::Change,
                gesture: 3.into(),
                value: EditValue::Number(0.25)
            })
        );
    }

    #[test]
    fn row_edits_parse() {
        let v: EditValue = serde_json::from_value(json!({"kind": "move", "value": {"row": 4, "target": 9, "position": "below"}})).unwrap();
        assert_eq!(v, EditValue::Move { row: 4.into(), target: 9.into(), position: Position::Below });
        let v: EditValue = serde_json::from_value(json!({"kind": "rename", "value": {"row": 4, "name": "Sky"}})).unwrap();
        assert_eq!(v, EditValue::Rename { row: 4.into(), name: "Sky".into() });
    }

    /// Exactly what the Swift `CraftEdit` encodes for a row's eye.
    #[test]
    fn craft_ui_row_edits_parse() {
        let m: Message = serde_json::from_str(r#"{"action":"edit","panel":"layers","control":"rows","phase":"commit","gesture":1,"value":{"kind":"set_visible","value":{"row":2,"visible":false}}}"#).unwrap();
        let Message::Edit(edit) = m else { panic!("not an edit: {m:?}") };
        assert_eq!(edit.value, EditValue::SetVisible { row: 2.into(), visible: false });
        let m: Message = serde_json::from_str(r#"{"action":"edit","panel":"layers","control":"rows","phase":"commit","gesture":2,"value":{"kind":"move","value":{"row":4,"target":9,"position":"below"}}}"#).unwrap();
        let Message::Edit(edit) = m else { panic!("not an edit: {m:?}") };
        assert_eq!(edit.value, EditValue::Move { row: 4.into(), target: 9.into(), position: Position::Below });
    }

    #[test]
    fn the_shell_says_which_panels_are_open() {
        let m: Message = serde_json::from_value(json!({"action": "open_panels", "open": ["layers"]})).unwrap();
        assert_eq!(m, Message::OpenPanels { open: vec!["layers".into()] });
    }

    /// The newtypes are plain numbers on the wire.
    #[test]
    fn gestures_and_rows_are_plain_numbers() {
        let edit = Edit {
            panel: "layers".into(),
            control: "rows".into(),
            phase: Phase::Commit,
            gesture: GestureId::from(5),
            value: EditValue::SetVisible { row: RowId::from(9), visible: true },
        };
        let json = serde_json::to_value(&edit).unwrap();
        assert_eq!(json["gesture"], json!(5));
        assert_eq!(json["value"]["value"]["row"], json!(9));
        assert_eq!(serde_json::from_value::<Edit>(json).unwrap(), edit);
        assert_eq!(GestureId::from(5).get(), 5);
        assert_eq!(GestureId::from(5).to_string(), "5");
    }

    #[test]
    fn an_edit_error_is_its_message() {
        assert_eq!(EditError::from("no layer").to_string(), "no layer");
        assert_eq!(EditError::from(String::from("no layer")), EditError::from("no layer"));
        assert_eq!(EditError::from("no layer").message(), "no layer");
    }

    #[test]
    fn plain_actions_are_not_messages() {
        assert!(serde_json::from_value::<Message>(json!({"action": "undo"})).is_err());
    }
}
