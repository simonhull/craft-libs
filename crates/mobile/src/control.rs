//! What a native control sends: an app [`Action`] or a native panel's [`ui::Message`].

use std::borrow::Cow;

use crate::{Action, ui};

/// One message from the shell's native controls, routed by its `action` tag.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Control {
    /// A command for the app (Undo, Save, one of its own).
    Action(Action),
    /// A native panel's edit, or which panels are open.
    Ui(ui::Message),
}

impl Control {
    /// Parse the shell's JSON: the `action` tag says which kind it is, so a malformed one is
    /// reported against that kind.
    ///
    /// # Errors
    /// Why it isn't a control: not JSON, no `action` tag, an unknown action, or a known one
    /// with bad fields.
    pub(crate) fn parse(json: &[u8]) -> Result<Self, serde_json::Error> {
        #[derive(serde::Deserialize)]
        struct Tag<'a> {
            #[serde(borrow)]
            action: Cow<'a, str>,
        }
        let tag: Tag<'_> = serde_json::from_slice(json)?;
        match tag.action.as_ref() {
            "edit" | "open_panels" => serde_json::from_slice(json).map(Self::Ui),
            _ => serde_json::from_slice(json).map(Self::Action),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(json: &str) -> Result<Control, String> {
        Control::parse(json.as_bytes()).map_err(|e| e.to_string())
    }

    #[test]
    fn plain_actions_route_to_the_app() {
        assert_eq!(parse(r#"{"action":"undo"}"#), Ok(Control::Action(Action::Undo)));
    }

    #[test]
    fn every_panel_message_routes_to_the_panels() {
        let edit = r#"{"action":"edit","panel":"p","control":"c","phase":"commit","gesture":1,"value":{"kind":"toggle","value":true}}"#;
        assert!(matches!(parse(edit), Ok(Control::Ui(ui::Message::Edit(_)))), "{:?}", parse(edit));
        assert_eq!(parse(r#"{"action":"open_panels","open":["p"]}"#), Ok(Control::Ui(ui::Message::OpenPanels { open: vec!["p".into()] })));
    }

    /// A broken edit is reported as one, not as an unknown action.
    #[test]
    fn a_malformed_edit_says_what_is_wrong_with_it() {
        let e = parse(r#"{"action":"edit","panel":"p","control":"c","phase":"commit","gesture":1,"value":{"kind":"slider","value":1}}"#).unwrap_err();
        assert!(e.contains("slider") && !e.contains("unknown variant `edit`"), "{e}");
    }

    #[test]
    fn neither_is_an_error() {
        assert!(parse(r#"{"action":"format_disk"}"#).is_err());
        assert!(parse("not json").is_err());
    }
}
