//! The tool palette a rail panel shows.

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use super::{CommandId, ControlId, PanelId, Shortcut, UiError};

/// A tool's id, the app's own (`brush`, `move`), unique in its palette.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ToolId(String);

id_newtype!(ToolId);

/// A tool's picture: an SF Symbol (Android maps it to a Material icon), and a letter for when the
/// platform has no such symbol. Without either, the shell shows the label's first letter.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Icon {
    symbol: Option<String>,
    letter: Option<char>,
}

impl Icon {
    /// An SF Symbol by name (`paintbrush.pointed`).
    #[must_use]
    pub fn symbol(name: impl Into<String>) -> Self {
        Self { symbol: Some(name.into()), letter: None }
    }

    /// Just a letter.
    #[must_use]
    pub fn letter(letter: char) -> Self {
        Self { symbol: None, letter: Some(letter) }
    }

    /// The letter shown when the symbol doesn't exist on the platform.
    #[must_use]
    pub fn or_letter(mut self, letter: char) -> Self {
        self.letter = Some(letter);
        self
    }
}

/// One tool of a [`ToolPalette`].
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Tool {
    id: ToolId,
    label: String,
    icon: Icon,
    shortcut: Option<Shortcut>,
}

impl Tool {
    /// A tool without a shortcut.
    #[must_use]
    pub fn new(id: impl Into<ToolId>, label: impl Into<String>, icon: Icon) -> Self {
        Self { id: id.into(), label: label.into(), icon, shortcut: None }
    }

    /// The key that picks it (shown in its tooltip and flyout).
    #[must_use]
    pub fn shortcut(mut self, shortcut: Option<Shortcut>) -> Self {
        self.shortcut = shortcut;
        self
    }

    /// Its id.
    #[must_use]
    pub fn id(&self) -> &ToolId {
        &self.id
    }
}

/// One place on the rail: its first tool shows (or the selected one, when it's in the slot), and
/// the rest are in its flyout.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolSlot {
    tools: Vec<Tool>,
}

impl ToolSlot {
    /// A slot of `tools`, the first shown.
    #[must_use]
    pub fn new(tools: Vec<Tool>) -> Self {
        Self { tools }
    }

    /// A slot of one tool.
    #[must_use]
    pub fn one(tool: Tool) -> Self {
        Self { tools: vec![tool] }
    }
}

/// The app's tools, as a rail beside the canvas: tapping one selects it, as an
/// [`EditValue::Choice`](super::EditValue::Choice) `commit` with the tool's id.
///
/// The selected tool's options: the app's Tool panel `options` when it has one, else the command
/// `fallback_options` (an app command that shows them its own way).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "ToolPaletteRepr")]
pub struct ToolPalette {
    pub(super) id: ControlId,
    slots: Vec<ToolSlot>,
    selected: ToolId,
    options: Option<PanelId>,
    fallback_options: Option<CommandId>,
}

impl ToolPalette {
    /// A palette of `slots`, top to bottom, with `selected` the current tool.
    ///
    /// # Errors
    /// [`UiError::EmptySlot`] for a slot without tools, [`UiError::EmptyLabel`] for a tool without a
    /// label (a screen reader reads it), [`UiError::DuplicateTool`] for a tool id
    /// that appears twice, and [`UiError::UnknownTool`] when `selected` isn't one of them.
    pub fn new(id: impl Into<ControlId>, slots: Vec<ToolSlot>, selected: impl Into<ToolId>) -> Result<Self, UiError> {
        let (id, selected) = (id.into(), selected.into());
        if slots.iter().any(|s| s.tools.is_empty()) {
            return Err(UiError::EmptySlot { palette: id });
        }
        if let Some(tool) = slots.iter().flat_map(|s| &s.tools).find(|t| t.label.trim().is_empty()) {
            return Err(UiError::EmptyLabel { context: format!("tool `{}` in palette `{id}`", tool.id) });
        }
        let mut seen = HashSet::new();
        if let Some(dup) = slots.iter().flat_map(|s| &s.tools).find(|t| !seen.insert(&t.id)) {
            return Err(UiError::DuplicateTool { palette: id, tool: dup.id.clone() });
        }
        if !seen.contains(&selected) {
            return Err(UiError::UnknownTool { palette: id, tool: selected });
        }
        Ok(Self { id, slots, selected, options: None, fallback_options: None })
    }

    /// The selected tool's Tool panel, opened for its options; `None` when it has none.
    #[must_use]
    pub fn options(mut self, panel: Option<PanelId>) -> Self {
        self.options = panel;
        self
    }

    /// The command that shows the selected tool's options when there's no panel for them.
    #[must_use]
    pub fn fallback_options(mut self, command: Option<CommandId>) -> Self {
        self.fallback_options = command;
        self
    }

    /// The selected tool.
    #[must_use]
    pub fn selected(&self) -> &ToolId {
        &self.selected
    }
}

/// [`ToolPalette`] as it arrives on the wire, before validation.
#[derive(Deserialize)]
struct ToolPaletteRepr {
    id: ControlId,
    slots: Vec<ToolSlot>,
    selected: ToolId,
    options: Option<PanelId>,
    fallback_options: Option<CommandId>,
}

impl TryFrom<ToolPaletteRepr> for ToolPalette {
    type Error = UiError;

    fn try_from(r: ToolPaletteRepr) -> Result<Self, UiError> {
        Ok(Self::new(r.id, r.slots, r.selected)?.options(r.options).fallback_options(r.fallback_options))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ui::Node;
    use serde_json::json;

    fn brush() -> Tool {
        Tool::new("brush", "Brush", Icon::symbol("paintbrush.pointed").or_letter('B')).shortcut("B".parse().ok())
    }

    fn slots() -> Vec<ToolSlot> {
        vec![
            ToolSlot::one(Tool::new("move", "Move", Icon::symbol("arrow.up.and.down.and.arrow.left.and.right"))),
            ToolSlot::new(vec![brush(), Tool::new("pencil", "Pencil", Icon::letter('N'))]),
        ]
    }

    #[test]
    fn a_palette_serializes_as_documented() {
        let palette = ToolPalette::new("tools", slots(), "pencil").unwrap().options(Some("brush".into()));
        assert_eq!(
            serde_json::to_value(Node::ToolPalette(palette)).unwrap(),
            json!({"type": "tool_palette", "id": "tools", "slots": [
                {"tools": [{"id": "move", "label": "Move", "icon": {"symbol": "arrow.up.and.down.and.arrow.left.and.right", "letter": null}, "shortcut": null}]},
                {"tools": [
                    {"id": "brush", "label": "Brush", "icon": {"symbol": "paintbrush.pointed", "letter": "B"}, "shortcut": "B"},
                    {"id": "pencil", "label": "Pencil", "icon": {"symbol": null, "letter": "N"}, "shortcut": null}
                ]}
            ], "selected": "pencil", "options": "brush", "fallback_options": null})
        );
    }

    #[test]
    fn the_selected_tool_exists_and_ids_are_unique() {
        assert_eq!(ToolPalette::new("tools", slots(), "lasso").unwrap_err(), UiError::UnknownTool { palette: "tools".into(), tool: "lasso".into() });
        let mut twice = slots();
        twice.push(ToolSlot::one(brush()));
        assert_eq!(ToolPalette::new("tools", twice, "move").unwrap_err(), UiError::DuplicateTool { palette: "tools".into(), tool: "brush".into() });
        let mut empty = slots();
        empty.push(ToolSlot::new(vec![]));
        assert_eq!(ToolPalette::new("tools", empty, "move").unwrap_err(), UiError::EmptySlot { palette: "tools".into() });
        assert_eq!(ToolPalette::new("tools", slots(), "brush").unwrap().selected().as_str(), "brush");
        let unlabelled = vec![ToolSlot::one(Tool::new("move", " ", Icon::letter('V')))];
        assert!(matches!(ToolPalette::new("tools", unlabelled, "move").unwrap_err(), UiError::EmptyLabel { .. }));
    }

    #[test]
    fn a_palette_round_trips_and_deserializing_validates() {
        let palette = ToolPalette::new("tools", slots(), "move").unwrap().fallback_options(Some("window.toggle.optionsBar".into()));
        let json = serde_json::to_value(Node::ToolPalette(palette.clone())).unwrap();
        assert_eq!(serde_json::from_value::<Node>(json.clone()).unwrap(), Node::ToolPalette(palette));
        let mut bad = json;
        bad["selected"] = json!("lasso");
        assert!(serde_json::from_value::<Node>(bad).is_err());
    }
}
