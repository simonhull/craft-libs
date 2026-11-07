//! The primitives a panel is built from.

use std::ops::RangeInclusive;

use serde::{Deserialize, Serialize};

use super::UiError;

/// A panel's id, stable for the app's life ("layers", "brush").
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct PanelId(pub String);

/// A control's id, unique within its panel and stable across descriptions, so the shell keeps
/// focus and gestures on it.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ControlId(pub String);

impl From<&str> for PanelId {
    fn from(s: &str) -> Self {
        Self(s.to_owned())
    }
}

impl From<&str> for ControlId {
    fn from(s: &str) -> Self {
        Self(s.to_owned())
    }
}

/// How a panel is presented. The shell decides the details per platform and size.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PanelRole {
    /// Slides in from the edge beside the canvas (Layers).
    Inspector,
    /// A popover from its toolbar button (brush options).
    Tool,
}

/// A panel the app offers: what the toolbar shows for it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PanelInfo {
    /// Its id.
    pub id: PanelId,
    /// Its title.
    pub title: String,
    /// An SF Symbol name; Android maps it to a Material icon.
    pub icon: String,
    /// How it is presented.
    pub role: PanelRole,
}

/// One panel's contents.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Panel {
    id: PanelId,
    title: String,
    role: PanelRole,
    nodes: Vec<Node>,
}

impl Panel {
    /// A panel of `nodes`, top to bottom.
    #[must_use]
    pub fn new(id: impl Into<PanelId>, title: impl Into<String>, role: PanelRole, nodes: Vec<Node>) -> Self {
        Self { id: id.into(), title: title.into(), role, nodes }
    }

    /// Its id.
    #[must_use]
    pub fn id(&self) -> &PanelId {
        &self.id
    }
}

/// One primitive.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Node {
    /// A titled group.
    Section(Section),
    /// A continuous value.
    Number(Number),
    /// On or off.
    Toggle(Toggle),
    /// One of several.
    Choice(Choice),
    /// Rows of items (layers, tracks, pages).
    ItemList(ItemList),
}

/// A titled group of nodes.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Section {
    id: ControlId,
    title: String,
    collapsed: bool,
    children: Vec<Node>,
}

impl Section {
    /// An expanded section.
    #[must_use]
    pub fn new(id: &str, title: impl Into<String>, children: Vec<Node>) -> Self {
        Self { id: id.into(), title: title.into(), collapsed: false, children }
    }

    /// Start collapsed.
    #[must_use]
    pub fn collapsed(mut self, collapsed: bool) -> Self {
        self.collapsed = collapsed;
        self
    }
}

/// What a number measures; the shell formats it.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Unit {
    /// A plain number.
    #[default]
    None,
    /// A 0..=1 value shown as 0–100 %.
    Percent,
    /// Pixels.
    Pixels,
    /// Degrees.
    Degrees,
}

/// A continuous value in a range.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Number {
    id: ControlId,
    label: String,
    value: f64,
    min: f64,
    max: f64,
    step: Option<f64>,
    unit: Unit,
    enabled: bool,
}

impl Number {
    /// A number in `range`; `value` is clamped into it.
    ///
    /// # Errors
    /// [`UiError::EmptyRange`] if the range is empty or not finite.
    pub fn new(id: &str, label: impl Into<String>, range: RangeInclusive<f64>, value: f64) -> Result<Self, UiError> {
        let (min, max) = range.into_inner();
        if !(min.is_finite() && max.is_finite() && min <= max) {
            return Err(UiError::EmptyRange { id: id.to_owned() });
        }
        let value = if value.is_finite() { value.clamp(min, max) } else { min };
        Ok(Self { id: id.into(), label: label.into(), value, min, max, step: None, unit: Unit::None, enabled: true })
    }

    /// Its unit.
    #[must_use]
    pub fn unit(mut self, unit: Unit) -> Self {
        self.unit = unit;
        self
    }

    /// Snap to multiples of `step`.
    #[must_use]
    pub fn step(mut self, step: f64) -> Self {
        self.step = (step.is_finite() && step > 0.0).then_some(step);
        self
    }

    /// Greyed out when `false`.
    #[must_use]
    pub fn enabled(mut self, enabled: bool) -> Self {
        self.enabled = enabled;
        self
    }

    /// The (clamped) value.
    #[must_use]
    pub fn value(&self) -> f64 {
        self.value
    }
}

/// On or off.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Toggle {
    id: ControlId,
    label: String,
    value: bool,
    enabled: bool,
}

impl Toggle {
    /// An enabled toggle.
    #[must_use]
    pub fn new(id: &str, label: impl Into<String>, value: bool) -> Self {
        Self { id: id.into(), label: label.into(), value, enabled: true }
    }

    /// Greyed out when `false`.
    #[must_use]
    pub fn enabled(mut self, enabled: bool) -> Self {
        self.enabled = enabled;
        self
    }
}

/// One option of a [`Choice`].
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChoiceOption {
    id: String,
    label: String,
}

impl ChoiceOption {
    /// An option: `id` is what edits carry, `label` what the user sees.
    #[must_use]
    pub fn new(id: impl Into<String>, label: impl Into<String>) -> Self {
        Self { id: id.into(), label: label.into() }
    }
}

/// One of several options.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Choice {
    id: ControlId,
    label: String,
    value: String,
    options: Vec<ChoiceOption>,
    enabled: bool,
}

impl Choice {
    /// A choice whose current `value` is one of `options`' ids.
    ///
    /// # Errors
    /// [`UiError::UnknownOption`] if `value` isn't among them.
    pub fn new(id: &str, label: impl Into<String>, value: &str, options: impl Into<Vec<ChoiceOption>>) -> Result<Self, UiError> {
        let options = options.into();
        if !options.iter().any(|o| o.id == value) {
            return Err(UiError::UnknownOption { id: id.to_owned(), value: value.to_owned() });
        }
        Ok(Self { id: id.into(), label: label.into(), value: value.to_owned(), options, enabled: true })
    }

    /// Greyed out when `false`.
    #[must_use]
    pub fn enabled(mut self, enabled: bool) -> Self {
        self.enabled = enabled;
        self
    }
}

/// One row of an [`ItemList`].
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Row {
    id: u64,
    title: String,
    subtitle: String,
    depth: u32,
    visible: Option<bool>,
    selected: bool,
}

impl Row {
    /// A top-level, unselected row that can't be hidden. `id` is the app's own (a layer id).
    #[must_use]
    pub fn new(id: u64, title: impl Into<String>) -> Self {
        Self { id, title: title.into(), subtitle: String::new(), depth: 0, visible: None, selected: false }
    }

    /// A second line ("Pixel", "Group").
    #[must_use]
    pub fn subtitle(mut self, subtitle: impl Into<String>) -> Self {
        self.subtitle = subtitle.into();
        self
    }

    /// Nesting depth (inside groups).
    #[must_use]
    pub fn depth(mut self, depth: u32) -> Self {
        self.depth = depth;
        self
    }

    /// `Some` when the row can be shown and hidden.
    #[must_use]
    pub fn visible(mut self, visible: Option<bool>) -> Self {
        self.visible = visible;
        self
    }

    /// Selected (or active).
    #[must_use]
    pub fn selected(mut self, selected: bool) -> Self {
        self.selected = selected;
        self
    }
}

/// Rows of items, top to bottom.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemList {
    id: ControlId,
    rows: Vec<Row>,
    reorderable: bool,
}

impl ItemList {
    /// A fixed-order list.
    #[must_use]
    pub fn new(id: &str, rows: Vec<Row>) -> Self {
        Self { id: id.into(), rows, reorderable: false }
    }

    /// Rows can be dragged to a new place ([`super::EditValue::Move`]).
    #[must_use]
    pub fn reorderable(mut self, reorderable: bool) -> Self {
        self.reorderable = reorderable;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_number_serializes_as_documented() {
        let n = Number::new("opacity", "Opacity", 0.0..=1.0, 0.5).unwrap().unit(Unit::Percent);
        assert_eq!(
            serde_json::to_value(Node::Number(n)).unwrap(),
            json!({"type": "number", "id": "opacity", "label": "Opacity", "value": 0.5, "min": 0.0, "max": 1.0, "step": null, "unit": "percent", "enabled": true})
        );
    }

    #[test]
    fn a_number_rejects_bad_ranges_and_clamps_its_value() {
        assert_eq!(Number::new("a", "A", 1.0..=0.0, 0.5).unwrap_err(), UiError::EmptyRange { id: "a".into() });
        assert_eq!(Number::new("a", "A", 0.0..=f64::NAN, 0.5).unwrap_err(), UiError::EmptyRange { id: "a".into() });
        assert!((Number::new("a", "A", 0.0..=1.0, 3.0).unwrap().value() - 1.0).abs() < f64::EPSILON);
    }

    #[test]
    fn a_choice_needs_its_value_among_the_options() {
        let opts = [ChoiceOption::new("normal", "Normal"), ChoiceOption::new("multiply", "Multiply")];
        assert!(Choice::new("blend", "Blend Mode", "multiply", opts.clone()).is_ok());
        assert_eq!(
            Choice::new("blend", "Blend Mode", "screen", opts).unwrap_err(),
            UiError::UnknownOption { id: "blend".into(), value: "screen".into() }
        );
    }

    #[test]
    fn nodes_round_trip() {
        let panel = Panel::new(
            "layers",
            "Layers",
            PanelRole::Inspector,
            vec![
                Node::Section(Section::new("props", "Layer", vec![Node::Toggle(Toggle::new("visible", "Visible", true))])),
                Node::ItemList(
                    ItemList::new("rows", vec![Row::new(7, "Background").subtitle("Pixel").visible(Some(true)).selected(true)]).reorderable(true),
                ),
            ],
        );
        let json = serde_json::to_string(&panel).unwrap();
        assert_eq!(serde_json::from_str::<Panel>(&json).unwrap(), panel);
    }
}
