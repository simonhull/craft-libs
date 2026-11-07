//! The app's menus, for the shell's native menu bar.

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use super::{CommandId, Shortcut, UiError};

/// The app's whole menu bar, left to right (wire kind 15, [`crate::Platform::set_menu`]).
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "MenuBarRepr")]
pub struct MenuBar {
    menus: Vec<Menu>,
}

impl MenuBar {
    /// A menu bar of `menus`.
    ///
    /// # Errors
    /// [`UiError::EmptyLabel`] for a menu, submenu or command without a title or label, and
    /// [`UiError::DuplicateCommand`] for a command that appears twice anywhere in the bar (the
    /// shell finds a command's state by its id).
    pub fn new(menus: Vec<Menu>) -> Result<Self, UiError> {
        let mut seen = HashSet::new();
        for menu in &menus {
            if menu.title.trim().is_empty() {
                return Err(UiError::EmptyLabel { context: "a menu".into() });
            }
            check(&menu.items, &menu.title, &mut seen)?;
        }
        Ok(Self { menus })
    }

    /// The menus, left to right.
    #[must_use]
    pub fn menus(&self) -> &[Menu] {
        &self.menus
    }
}

/// Labels are non-empty and command ids unique, in `items` and their submenus.
fn check<'a>(items: &'a [MenuEntry], within: &str, seen: &mut HashSet<&'a CommandId>) -> Result<(), UiError> {
    for item in items {
        match item {
            MenuEntry::Command(c) => {
                if c.label.trim().is_empty() {
                    return Err(UiError::EmptyLabel { context: format!("command `{}` in {within}", c.id) });
                }
                if !seen.insert(&c.id) {
                    return Err(UiError::DuplicateCommand { command: c.id.clone() });
                }
            }
            MenuEntry::Submenu(s) => {
                if s.label.trim().is_empty() {
                    return Err(UiError::EmptyLabel { context: format!("a submenu in {within}") });
                }
                check(&s.items, &s.label, seen)?;
            }
            MenuEntry::Separator => {}
        }
    }
    Ok(())
}

/// [`MenuBar`] as it arrives on the wire, before validation.
#[derive(Deserialize)]
struct MenuBarRepr {
    menus: Vec<Menu>,
}

impl TryFrom<MenuBarRepr> for MenuBar {
    type Error = UiError;

    fn try_from(r: MenuBarRepr) -> Result<Self, UiError> {
        Self::new(r.menus)
    }
}

/// One menu of the bar (File, Edit…).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Menu {
    title: String,
    items: Vec<MenuEntry>,
}

impl Menu {
    /// A menu titled `title`, its entries top to bottom.
    #[must_use]
    pub fn new(title: impl Into<String>, items: Vec<MenuEntry>) -> Self {
        Self { title: title.into(), items }
    }

    /// Its title.
    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    /// Its entries, top to bottom.
    #[must_use]
    pub fn items(&self) -> &[MenuEntry] {
        &self.items
    }
}

/// One entry of a menu.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum MenuEntry {
    /// One of the app's commands.
    Command(MenuCommand),
    /// A line between groups.
    Separator,
    /// A nested menu.
    Submenu(Submenu),
}

impl MenuEntry {
    /// A command entry.
    #[must_use]
    pub fn command(id: impl Into<CommandId>, label: impl Into<String>) -> MenuCommand {
        MenuCommand::new(id, label)
    }

    /// A submenu entry.
    #[must_use]
    pub fn submenu(label: impl Into<String>, items: Vec<MenuEntry>) -> Self {
        Self::Submenu(Submenu { label: label.into(), items })
    }
}

impl From<MenuCommand> for MenuEntry {
    fn from(command: MenuCommand) -> Self {
        Self::Command(command)
    }
}

/// A menu item that runs one of the app's commands.
///
/// Chosen from the menu it reaches the app as [`crate::CraftApp::command`]; with a shortcut, as
/// [`crate::CraftApp::shortcut`] instead, so the app's own key handling decides, as for the key.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MenuCommand {
    id: CommandId,
    label: String,
    shortcut: Option<Shortcut>,
    enabled: bool,
    checked: Option<bool>,
}

impl MenuCommand {
    /// An enabled command without a shortcut or a check mark.
    #[must_use]
    pub fn new(id: impl Into<CommandId>, label: impl Into<String>) -> Self {
        Self { id: id.into(), label: label.into(), shortcut: None, enabled: true, checked: None }
    }

    /// Its keyboard shortcut, shown in the menu and pressed on a hardware keyboard.
    #[must_use]
    pub fn shortcut(mut self, shortcut: Option<Shortcut>) -> Self {
        self.shortcut = shortcut;
        self
    }

    /// Greyed out when `false`.
    #[must_use]
    pub fn enabled(mut self, enabled: bool) -> Self {
        self.enabled = enabled;
        self
    }

    /// `Some` for an item with a check mark (on or off), `None` for a plain one.
    #[must_use]
    pub fn checked(mut self, checked: Option<bool>) -> Self {
        self.checked = checked;
        self
    }

    /// Its command.
    #[must_use]
    pub fn id(&self) -> &CommandId {
        &self.id
    }
}

/// A nested menu.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Submenu {
    label: String,
    items: Vec<MenuEntry>,
}

impl Submenu {
    /// Its label.
    #[must_use]
    pub fn label(&self) -> &str {
        &self.label
    }

    /// Its entries, top to bottom.
    #[must_use]
    pub fn items(&self) -> &[MenuEntry] {
        &self.items
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn edit_menu() -> Menu {
        Menu::new(
            "Edit",
            vec![
                MenuEntry::command("edit.undo", "Undo").shortcut("Cmd+Z".parse().ok()).enabled(false).into(),
                MenuEntry::Separator,
                MenuEntry::submenu("Transform", vec![MenuEntry::command("edit.flip", "Flip").into()]),
                MenuEntry::command("view.rulers", "Rulers").checked(Some(true)).into(),
            ],
        )
    }

    #[test]
    fn a_menu_bar_serializes_as_documented() {
        let bar = MenuBar::new(vec![edit_menu()]).unwrap();
        assert_eq!(
            serde_json::to_value(&bar).unwrap(),
            json!({"menus": [{"title": "Edit", "items": [
                {"type": "command", "id": "edit.undo", "label": "Undo", "shortcut": "Cmd+Z", "enabled": false, "checked": null},
                {"type": "separator"},
                {"type": "submenu", "label": "Transform", "items": [
                    {"type": "command", "id": "edit.flip", "label": "Flip", "shortcut": null, "enabled": true, "checked": null}
                ]},
                {"type": "command", "id": "view.rulers", "label": "Rulers", "shortcut": null, "enabled": true, "checked": true}
            ]}]})
        );
    }

    #[test]
    fn a_menu_bar_round_trips() {
        let bar = MenuBar::new(vec![edit_menu(), Menu::new("File", vec![MenuEntry::command("file.save", "Save").into()])]).unwrap();
        let json = serde_json::to_string(&bar).unwrap();
        assert_eq!(serde_json::from_str::<MenuBar>(&json).unwrap(), bar);
        assert_eq!(bar.menus().len(), 2);
    }

    #[test]
    fn command_ids_are_unique_in_the_whole_bar() {
        let again = Menu::new("Image", vec![MenuEntry::submenu("More", vec![MenuEntry::command("edit.flip", "Flip again").into()])]);
        assert_eq!(MenuBar::new(vec![edit_menu(), again]).unwrap_err(), UiError::DuplicateCommand { command: "edit.flip".into() });
    }

    #[test]
    fn labels_are_not_empty() {
        let empty = |menu: Menu| MenuBar::new(vec![menu]).unwrap_err();
        assert!(matches!(empty(Menu::new(" ", vec![])), UiError::EmptyLabel { .. }));
        assert!(matches!(empty(Menu::new("Edit", vec![MenuEntry::command("a", "").into()])), UiError::EmptyLabel { .. }));
        assert!(matches!(empty(Menu::new("Edit", vec![MenuEntry::submenu("", vec![])])), UiError::EmptyLabel { .. }));
    }

    #[test]
    fn deserializing_validates() {
        let dup = json!({"menus": [{"title": "Edit", "items": [
            {"type": "command", "id": "a", "label": "A", "shortcut": null, "enabled": true, "checked": null},
            {"type": "command", "id": "a", "label": "A", "shortcut": null, "enabled": true, "checked": null}
        ]}]});
        assert!(serde_json::from_value::<MenuBar>(dup).is_err());
        let bad_shortcut = json!({"menus": [{"title": "Edit", "items": [
            {"type": "command", "id": "a", "label": "A", "shortcut": "Hyper+A", "enabled": true, "checked": null}
        ]}]});
        assert!(serde_json::from_value::<MenuBar>(bad_shortcut).is_err());
    }
}
