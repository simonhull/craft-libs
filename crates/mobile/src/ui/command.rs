//! The app's commands and keyboard shortcuts, as native menus and the tool rail name them.

use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Serialize};

use super::UiError;

/// One of the app's commands, by the id its own menus use (`edit.undo`, `window.toggle.color`).
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct CommandId(String);

id_newtype!(CommandId);

/// A keyboard shortcut in the portable form the Craft apps write: modifiers, then one key, joined
/// by `+` (`Cmd+Shift+Z`, `Ctrl+Tab`, `F5`, `B`).
///
/// - Modifiers are `Ctrl`, `Cmd`, `Alt` and `Shift`. `Cmd` is ⌘ and `Ctrl` the real Control key:
///   ⌃Z and ⌘Z are different shortcuts.
/// - The key is one printable character (`Z`, `1`, `[`, `+` as in `Cmd++`), or a named key as
///   egui names it (`Enter`, `Escape`, `Tab`, `Space`, `Backspace`, `Delete`, `ArrowUp`, `F1`…).
///   Letters are kept upper case; a key named by one of egui's aliases (`Esc`, `Return`) is kept
///   under egui's canonical name ([`named_keys`]), so the shell only ever sees those.
///
/// It prints back in a fixed order, `Ctrl+Cmd+Alt+Shift+Key`, so equal shortcuts print the same.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct Shortcut {
    /// [`Modifier`] bits.
    held: u8,
    key: String,
}

/// A modifier key of a [`Shortcut`], in the order it prints.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Modifier {
    Ctrl,
    Cmd,
    Alt,
    Shift,
}

impl Modifier {
    const ALL: [Self; 4] = [Self::Ctrl, Self::Cmd, Self::Alt, Self::Shift];

    const fn name(self) -> &'static str {
        match self {
            Self::Ctrl => "Ctrl",
            Self::Cmd => "Cmd",
            Self::Alt => "Alt",
            Self::Shift => "Shift",
        }
    }

    const fn bit(self) -> u8 {
        1 << self as u8
    }
}

impl Shortcut {
    /// Parse the portable form; the same as [`str::parse`].
    ///
    /// # Errors
    /// [`UiError::BadShortcut`] for an unknown modifier or key, a repeated modifier, or anything
    /// but exactly one key.
    pub fn parse(text: &str) -> Result<Self, UiError> {
        let bad = || UiError::BadShortcut { shortcut: text.to_owned() };
        let mut held = 0;
        // `Cmd++` is ⌘ and the plus key: the key is what follows the last separator, or `+` when
        // the text ends in `++` (or is `+` alone).
        let (modifiers, key) = match text.strip_suffix("++") {
            Some(modifiers) => (Some(modifiers), "+"),
            None if text == "+" => (None, "+"),
            None => match text.rsplit_once('+') {
                Some((modifiers, key)) => (Some(modifiers), key),
                None => (None, text),
            },
        };
        for modifier in modifiers.into_iter().flat_map(|m| m.split('+')) {
            let bit = Modifier::ALL.into_iter().find(|m| m.name() == modifier).ok_or_else(bad)?.bit();
            if held & bit != 0 {
                return Err(bad());
            }
            held |= bit;
        }
        Ok(Self { held, key: key_name(key).ok_or_else(bad)? })
    }

    /// The key: one character (letters upper case) or egui's name for it (`Enter`, `F5`).
    #[must_use]
    pub fn key(&self) -> &str {
        &self.key
    }

    /// The modifiers held, as egui spells them: `command` and `mac_cmd` are ⌘, `ctrl` the Control key.
    #[must_use]
    pub fn modifiers(&self) -> egui::Modifiers {
        let cmd = self.holds(Modifier::Cmd);
        egui::Modifiers {
            alt: self.holds(Modifier::Alt),
            ctrl: self.holds(Modifier::Ctrl),
            shift: self.holds(Modifier::Shift),
            mac_cmd: cmd,
            command: cmd,
        }
    }

    const fn holds(&self, modifier: Modifier) -> bool {
        self.held & modifier.bit() != 0
    }
}

/// `key` as a shortcut keeps it, or `None` if it isn't one: a single printable character (a letter
/// upper-cased), or egui's canonical name for a key (any alias egui reads is accepted).
fn key_name(key: &str) -> Option<String> {
    let mut chars = key.chars();
    match (chars.next(), chars.next()) {
        (Some(c), None) if !c.is_whitespace() && !c.is_control() => Some(c.to_uppercase().collect()),
        // egui's own name for it, whichever alias was written (`Esc` is `Escape`).
        (Some(_), Some(_)) => egui::Key::from_name(key).map(canonical_name),
        _ => None,
    }
}

/// A key's name as a shortcut prints it: egui's, but arrows keep their `Arrow` (`ArrowUp`, as the
/// shells and egui's own event names spell them, not `Up`).
fn canonical_name(key: egui::Key) -> String {
    use egui::Key;
    match key {
        Key::ArrowUp | Key::ArrowDown | Key::ArrowLeft | Key::ArrowRight => format!("Arrow{}", key.name()),
        _ => key.name().to_owned(),
    }
}

/// Every named key a [`Shortcut`] prints, as egui names it: what a shell must understand besides
/// single characters.
#[must_use]
pub fn named_keys() -> Vec<String> {
    egui::Key::ALL.iter().map(|k| canonical_name(*k)).filter(|name| name.chars().count() > 1).collect()
}

/// Texts and what [`Shortcut::parse`] makes of them (`None`: refused), for the shells' parsers to be
/// tested against (the catalogue carries them).
pub(crate) const PARSE_CASES: &[(&str, Option<&str>)] = &[
    ("Cmd+Shift+Z", Some("Cmd+Shift+Z")),
    ("Shift+Cmd+z", Some("Cmd+Shift+Z")),
    ("Cmd+Ctrl+M", Some("Ctrl+Cmd+M")),
    ("Ctrl+Tab", Some("Ctrl+Tab")),
    ("Alt+ArrowUp", Some("Alt+ArrowUp")),
    ("F5", Some("F5")),
    ("B", Some("B")),
    ("b", Some("B")),
    ("Cmd++", Some("Cmd++")),
    ("+", Some("+")),
    ("Cmd+-", Some("Cmd+-")),
    ("Cmd+[", Some("Cmd+[")),
    ("Cmd+Enter", Some("Cmd+Enter")),
    ("", None),
    ("Cmd+", None),
    ("+Z", None),
    ("++Z", None),
    ("Cmd++Z", None),
    ("Cmd+Cmd+Z", None),
    ("Command+Z", None),
    ("cmd+Z", None),
    ("Cmd+Z+X", None),
    ("Cmd+Nope", None),
    ("Cmd+ ", None),
    ("Cmd+\n", None),
];

impl FromStr for Shortcut {
    type Err = UiError;

    fn from_str(text: &str) -> Result<Self, UiError> {
        Self::parse(text)
    }
}

impl TryFrom<String> for Shortcut {
    type Error = UiError;

    fn try_from(text: String) -> Result<Self, UiError> {
        Self::parse(&text)
    }
}

impl From<Shortcut> for String {
    fn from(shortcut: Shortcut) -> Self {
        shortcut.to_string()
    }
}

impl fmt::Display for Shortcut {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for modifier in Modifier::ALL.into_iter().filter(|m| self.holds(*m)) {
            write!(f, "{}+", modifier.name())?;
        }
        f.write_str(&self.key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn round_trip(text: &str) -> String {
        Shortcut::parse(text).map_or_else(|e| e.to_string(), |s| s.to_string())
    }

    #[test]
    fn shortcuts_print_back_as_written() {
        for text in ["Cmd+Shift+Z", "Cmd+Z", "Ctrl+Tab", "F5", "B", "Cmd++", "+", "Cmd+-", "Alt+[", "Ctrl+Cmd+Alt+Shift+ArrowUp", "Cmd+Enter"] {
            assert_eq!(round_trip(text), text);
        }
    }

    #[test]
    fn modifiers_print_in_a_fixed_order_and_letters_upper_case() {
        assert_eq!(round_trip("Shift+Cmd+z"), "Cmd+Shift+Z");
        assert_eq!(round_trip("Cmd+Ctrl+M"), "Ctrl+Cmd+M");
        assert_eq!(Shortcut::parse("Shift+Cmd+Z").unwrap(), Shortcut::parse("Cmd+Shift+Z").unwrap());
    }

    #[test]
    fn ctrl_and_cmd_stay_apart() {
        let ctrl = Shortcut::parse("Ctrl+Z").unwrap();
        let cmd = Shortcut::parse("Cmd+Z").unwrap();
        assert_ne!(ctrl, cmd);
        assert!(ctrl.modifiers().ctrl && !ctrl.modifiers().command && !ctrl.modifiers().mac_cmd);
        assert!(cmd.modifiers().command && cmd.modifiers().mac_cmd && !cmd.modifiers().ctrl);
        assert_eq!(cmd.key(), "Z");
    }

    #[test]
    fn bad_shortcuts_are_refused() {
        for text in ["", "Cmd+", "Cmd+Cmd+Z", "Command+Z", "Cmd+Z+X", "Cmd+Nope", "Cmd+ ", "cmd+Z", "Cmd+\n", "++Z"] {
            assert_eq!(Shortcut::parse(text).unwrap_err(), UiError::BadShortcut { shortcut: text.to_owned() }, "{text:?}");
        }
    }

    /// The cases the catalogue gives the shells, which their parsers must agree with.
    #[test]
    fn the_shared_parse_cases_hold() {
        for (text, expected) in PARSE_CASES {
            assert_eq!(Shortcut::parse(text).ok().map(|s| s.to_string()).as_deref(), *expected, "{text:?}");
        }
    }

    #[test]
    fn aliases_print_as_eguis_canonical_names() {
        assert_eq!(round_trip("Cmd+Esc"), "Cmd+Escape");
        assert_eq!(round_trip("Return"), "Enter");
        assert_eq!(round_trip("Up"), "ArrowUp");
        let names = named_keys();
        for name in ["Escape", "F5", "ArrowUp", "Enter", "Minus"] {
            assert!(names.iter().any(|n| n == name), "{name}");
        }
        assert!(!names.iter().any(|n| n == "A"), "single characters aren't named keys");
        for name in &names {
            assert_eq!(&round_trip(name), name, "a canonical name prints as itself");
        }
    }

    #[test]
    fn a_shortcut_is_a_string_on_the_wire() {
        let s: Shortcut = "Cmd+Shift+Z".parse().unwrap();
        assert_eq!(serde_json::to_value(&s).unwrap(), json!("Cmd+Shift+Z"));
        assert_eq!(serde_json::from_value::<Shortcut>(json!("Shift+Cmd+Z")).unwrap(), s);
        assert!(serde_json::from_value::<Shortcut>(json!("Hyper+Z")).is_err());
    }

    #[test]
    fn a_command_id_is_its_text() {
        let id = CommandId::from("edit.undo");
        assert_eq!(id.as_str(), "edit.undo");
        assert_eq!(id.to_string(), "edit.undo");
        assert_eq!(serde_json::to_value(&id).unwrap(), json!("edit.undo"));
    }
}
