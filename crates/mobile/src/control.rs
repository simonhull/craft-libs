//! What a native control sends: an app [`Action`], a native panel's [`ui::Message`], what the shell
//! draws, or a command or shortcut from its menus and rail.

use std::borrow::Cow;

use crate::{Action, ui};

/// One message from the shell's native controls, routed by its `action` tag.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Control {
    /// A command for the app (Undo, Save, one of its own).
    Action(Action),
    /// A native panel's edit, or which panels are open.
    Ui(ui::Message),
    /// The shell (re)started and draws these parts of the chrome: `{"action":"shell","features":[…]}`.
    Shell(ui::ShellFeatures),
    /// Run one of the app's commands as its menu item does: `{"action":"command","id":…}`, from a
    /// native menu, the rail or a Cancel button. One with `params` is an [`Action::Command`].
    Command(ui::CommandId),
    /// A shortcut chosen from a native menu, for the app's own key handling to decide:
    /// `{"action":"shortcut","keys":"Cmd+Z"}`.
    Shortcut(ui::Shortcut),
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
        #[derive(serde::Deserialize)]
        struct Shell {
            features: ui::ShellFeatures,
        }
        #[derive(serde::Deserialize)]
        struct Command {
            id: ui::CommandId,
            #[serde(default)]
            params: serde_json::Value,
        }
        #[derive(serde::Deserialize)]
        struct Shortcut {
            keys: ui::Shortcut,
        }
        let tag: Tag<'_> = serde_json::from_slice(json)?;
        match tag.action.as_ref() {
            "edit" | "open_panels" => serde_json::from_slice(json).map(Self::Ui),
            "shell" => serde_json::from_slice(json).map(|s: Shell| Self::Shell(s.features)),
            "shortcut" => serde_json::from_slice(json).map(|s: Shortcut| Self::Shortcut(s.keys)),
            "command" => {
                let command: Command = serde_json::from_slice(json)?;
                if command.params.is_null() {
                    Ok(Self::Command(command.id))
                } else {
                    Ok(Self::Action(Action::Command { id: command.id.to_string(), params: command.params }))
                }
            }
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
    fn the_shell_says_what_it_draws() {
        use ui::Feature;
        assert_eq!(
            parse(r#"{"action":"shell","features":["panels","menus","rail","status"]}"#),
            Ok(Control::Shell(ui::ShellFeatures::from(Feature::ALL)))
        );
        assert_eq!(parse(r#"{"action":"shell","features":[]}"#), Ok(Control::Shell(ui::ShellFeatures::none())));
        assert!(parse(r#"{"action":"shell"}"#).is_err());
    }

    /// A command without parameters is the menu's; with them, the app's [`Action::Command`] as before.
    #[test]
    fn commands_route_by_their_parameters() {
        let menu = Ok(Control::Command("edit.undo".into()));
        assert_eq!(parse(r#"{"action":"command","id":"edit.undo"}"#), menu);
        assert_eq!(parse(r#"{"action":"command","id":"edit.undo","params":null}"#), menu, "as CraftAction.command sends it");
        assert_eq!(
            parse(r#"{"action":"command","id":"file.new","params":{"width":800}}"#),
            Ok(Control::Action(Action::Command { id: "file.new".into(), params: serde_json::json!({"width": 800}) }))
        );
        assert!(parse(r#"{"action":"command"}"#).is_err());
    }

    #[test]
    fn a_shortcut_carries_its_keys() {
        assert_eq!(parse(r#"{"action":"shortcut","keys":"Shift+Cmd+Z"}"#), Ok(Control::Shortcut("Cmd+Shift+Z".parse().unwrap())));
        let e = parse(r#"{"action":"shortcut","keys":"Hyper+Z"}"#).unwrap_err();
        assert!(e.contains("Hyper+Z"), "{e}");
    }

    #[test]
    fn neither_is_an_error() {
        assert!(parse(r#"{"action":"format_disk"}"#).is_err());
        assert!(parse("not json").is_err());
    }
}
