//! The primitives a panel is built from.

use std::collections::HashSet;
use std::ops::RangeInclusive;

use serde::{Deserialize, Serialize};

use super::UiError;

/// A panel's id, stable for the app's life ("layers", "brush").
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct PanelId(String);

/// A control's id, unique within its panel and stable across descriptions, so the shell keeps
/// focus and gestures on it.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ControlId(String);

id_newtype!(PanelId);
id_newtype!(ControlId);

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

    /// Check the ids the shell relies on: controls are unique within the panel (sections
    /// included) and rows are unique within their list.
    ///
    /// # Errors
    /// [`UiError::DuplicateControl`] or [`UiError::DuplicateRow`] for the first repeat found.
    pub fn check(&self) -> Result<(), UiError> {
        fn walk<'a>(panel: &PanelId, nodes: &'a [Node], seen: &mut HashSet<&'a ControlId>) -> Result<(), UiError> {
            for node in nodes {
                let id = match node {
                    Node::Section(s) => &s.id,
                    Node::Number(n) => &n.id,
                    Node::Toggle(t) => &t.id,
                    Node::Choice(c) => &c.id,
                    Node::ItemList(l) => &l.id,
                };
                if !seen.insert(id) {
                    return Err(UiError::DuplicateControl { panel: panel.clone(), control: id.clone() });
                }
                match node {
                    Node::Section(s) => walk(panel, &s.children, seen)?,
                    Node::ItemList(l) => {
                        let mut rows = HashSet::new();
                        if let Some(dup) = l.rows.iter().find(|r| !rows.insert(r.id)) {
                            return Err(UiError::DuplicateRow { list: id.clone(), row: dup.id });
                        }
                    }
                    Node::Number(_) | Node::Toggle(_) | Node::Choice(_) => {}
                }
            }
            Ok(())
        }
        walk(&self.id, &self.nodes, &mut HashSet::new())
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
    pub fn new(id: impl Into<ControlId>, title: impl Into<String>, children: Vec<Node>) -> Self {
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

/// How a number's slider spreads its range.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Scale {
    /// Equal distances are equal differences.
    #[default]
    Linear,
    /// Equal distances are equal ratios, so a wide range (a brush of 1–5000 px) keeps room for
    /// its small values. Needs `min > 0`.
    Log,
}

impl Scale {
    #[expect(clippy::trivially_copy_pass_by_ref, reason = "serde's `skip_serializing_if` passes a reference")]
    fn is_linear(&self) -> bool {
        *self == Self::Linear
    }
}

/// A continuous value in a range.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(try_from = "NumberRepr")]
pub struct Number {
    id: ControlId,
    label: String,
    value: f64,
    min: f64,
    max: f64,
    step: Option<f64>,
    /// Left out of the JSON when linear.
    #[serde(skip_serializing_if = "Scale::is_linear")]
    scale: Scale,
    unit: Unit,
    enabled: bool,
}

impl Number {
    /// A number in `range`; `value` is clamped into it (a non-finite `value` becomes `min`).
    ///
    /// # Errors
    /// [`UiError::EmptyRange`] if the range is empty or not finite.
    pub fn new(id: impl Into<ControlId>, label: impl Into<String>, range: RangeInclusive<f64>, value: f64) -> Result<Self, UiError> {
        let id = id.into();
        let (min, max) = range.into_inner();
        if !(min.is_finite() && max.is_finite() && min <= max) {
            return Err(UiError::EmptyRange { id });
        }
        let value = if value.is_finite() { value.clamp(min, max) } else { min };
        Ok(Self { id, label: label.into(), value, min, max, step: None, scale: Scale::Linear, unit: Unit::None, enabled: true })
    }

    /// How the slider spreads the range ([`Scale::Linear`] unless set). The value and the edits
    /// stay in the number's own units either way.
    ///
    /// # Errors
    /// [`UiError::LogScaleNeedsPositiveMin`] for [`Scale::Log`] when `min <= 0`.
    pub fn scale(mut self, scale: Scale) -> Result<Self, UiError> {
        if scale == Scale::Log && self.min <= 0.0 {
            return Err(UiError::LogScaleNeedsPositiveMin { id: self.id });
        }
        self.scale = scale;
        Ok(self)
    }

    /// Its unit.
    #[must_use]
    pub fn unit(mut self, unit: Unit) -> Self {
        self.unit = unit;
        self
    }

    /// Snap to multiples of `step`; a non-positive or non-finite step is ignored.
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

/// [`Number`] as it arrives on the wire, before validation.
#[derive(Deserialize)]
struct NumberRepr {
    id: ControlId,
    label: String,
    value: f64,
    min: f64,
    max: f64,
    step: Option<f64>,
    #[serde(default)]
    scale: Scale,
    unit: Unit,
    enabled: bool,
}

impl TryFrom<NumberRepr> for Number {
    type Error = UiError;

    fn try_from(r: NumberRepr) -> Result<Self, UiError> {
        let mut n = Self::new(r.id, r.label, r.min..=r.max, r.value)?.scale(r.scale)?.unit(r.unit).enabled(r.enabled);
        if let Some(step) = r.step {
            n = n.step(step);
        }
        Ok(n)
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
    pub fn new(id: impl Into<ControlId>, label: impl Into<String>, value: bool) -> Self {
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
#[serde(try_from = "ChoiceRepr")]
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
    /// [`UiError::UnknownOption`] if `value` isn't among them, [`UiError::DuplicateOption`] if two options share an id.
    pub fn new(id: impl Into<ControlId>, label: impl Into<String>, value: &str, options: impl Into<Vec<ChoiceOption>>) -> Result<Self, UiError> {
        let id = id.into();
        let options = options.into();
        let mut seen = HashSet::new();
        if let Some(dup) = options.iter().find(|o| !seen.insert(o.id.as_str())) {
            return Err(UiError::DuplicateOption { id, option: dup.id.clone() });
        }
        if !options.iter().any(|o| o.id == value) {
            return Err(UiError::UnknownOption { id, value: value.to_owned() });
        }
        Ok(Self { id, label: label.into(), value: value.to_owned(), options, enabled: true })
    }

    /// Greyed out when `false`.
    #[must_use]
    pub fn enabled(mut self, enabled: bool) -> Self {
        self.enabled = enabled;
        self
    }
}

/// [`Choice`] as it arrives on the wire, before validation.
#[derive(Deserialize)]
struct ChoiceRepr {
    id: ControlId,
    label: String,
    value: String,
    options: Vec<ChoiceOption>,
    enabled: bool,
}

impl TryFrom<ChoiceRepr> for Choice {
    type Error = UiError;

    fn try_from(r: ChoiceRepr) -> Result<Self, UiError> {
        Ok(Self::new(r.id, r.label, &r.value, r.options)?.enabled(r.enabled))
    }
}

number_id! {
    /// A row's id: the app's own (a layer id), unique within its list.
    RowId
}

/// One row of an [`ItemList`].
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Row {
    id: RowId,
    title: String,
    subtitle: String,
    depth: u32,
    visible: Option<bool>,
    selected: bool,
}

impl Row {
    /// A top-level, unselected row that can't be hidden. `id` is the app's own (a layer id).
    #[must_use]
    pub fn new(id: impl Into<RowId>, title: impl Into<String>) -> Self {
        Self { id: id.into(), title: title.into(), subtitle: String::new(), depth: 0, visible: None, selected: false }
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
    pub fn new(id: impl Into<ControlId>, rows: Vec<Row>) -> Self {
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
    fn a_log_number_says_so_and_a_linear_one_says_nothing() {
        let size = Number::new("size", "Size", 1.0..=5000.0, 24.0).unwrap().step(1.0).unit(Unit::Pixels).scale(Scale::Log).unwrap();
        assert_eq!(
            serde_json::to_value(Node::Number(size)).unwrap(),
            json!({"type": "number", "id": "size", "label": "Size", "value": 24.0, "min": 1.0, "max": 5000.0, "step": 1.0, "scale": "log", "unit": "pixels", "enabled": true})
        );
        let linear = Number::new("a", "A", 1.0..=2.0, 1.0).unwrap().scale(Scale::Linear).unwrap();
        assert!(serde_json::to_value(Node::Number(linear)).unwrap().get("scale").is_none(), "linear is the default, left out");
    }

    #[test]
    fn a_log_scale_needs_a_positive_range() {
        for range in [0.0..=10.0, -5.0..=10.0] {
            assert_eq!(
                Number::new("a", "A", range, 1.0).unwrap().scale(Scale::Log).unwrap_err(),
                UiError::LogScaleNeedsPositiveMin { id: "a".into() }
            );
        }
        assert!(Number::new("a", "A", 0.0..=10.0, 1.0).unwrap().scale(Scale::Linear).is_ok());
        assert!(Number::new("a", "A", 0.01..=10.0, 1.0).unwrap().scale(Scale::Log).is_ok());
    }

    #[test]
    fn deserializing_a_scale_validates_it_and_defaults_to_linear() {
        let number = |extra: serde_json::Value| {
            let mut n = json!({"type": "number", "id": "a", "label": "A", "value": 1.0, "min": 0.0, "max": 10.0, "step": null, "unit": "none", "enabled": true});
            if let (Some(n), Some(extra)) = (n.as_object_mut(), extra.as_object()) {
                n.extend(extra.clone());
            }
            serde_json::from_value::<Node>(n)
        };
        assert_eq!(number(json!({})).unwrap(), Node::Number(Number::new("a", "A", 0.0..=10.0, 1.0).unwrap()));
        assert!(number(json!({"scale": "log"})).is_err(), "min 0 can't be logarithmic");
        assert!(number(json!({"scale": "log", "min": 1.0})).is_ok());
        assert!(number(json!({"scale": "spiral", "min": 1.0})).is_err());
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
    fn a_choice_rejects_duplicate_options() {
        let opts = [ChoiceOption::new("a", "A"), ChoiceOption::new("a", "Again")];
        assert_eq!(Choice::new("c", "C", "a", opts).unwrap_err(), UiError::DuplicateOption { id: "c".into(), option: "a".into() });
    }

    #[test]
    fn deserializing_validates() {
        let bad =
            json!({"type": "number", "id": "a", "label": "A", "value": 0.5, "min": 1.0, "max": 0.0, "step": null, "unit": "none", "enabled": true});
        assert!(serde_json::from_value::<Node>(bad).is_err());
        let bad = json!({"type": "choice", "id": "c", "label": "C", "value": "z", "options": [{"id": "a", "label": "A"}], "enabled": true});
        assert!(serde_json::from_value::<Node>(bad).is_err());
    }

    #[test]
    fn check_finds_duplicate_controls_and_rows() {
        let toggle = |id| Node::Toggle(Toggle::new(id, "T", true));
        let dup = Panel::new("p", "P", PanelRole::Tool, vec![toggle("t"), Node::Section(Section::new("s", "S", vec![toggle("t")]))]);
        assert_eq!(dup.check().unwrap_err(), UiError::DuplicateControl { panel: "p".into(), control: "t".into() });
        let rows = Panel::new("p", "P", PanelRole::Tool, vec![Node::ItemList(ItemList::new("l", vec![Row::new(1, "a"), Row::new(1, "b")]))]);
        assert_eq!(rows.check().unwrap_err(), UiError::DuplicateRow { list: "l".into(), row: 1.into() });
        assert!(Panel::new("p", "P", PanelRole::Tool, vec![toggle("a"), toggle("b")]).check().is_ok());
    }

    #[test]
    fn row_ids_are_plain_numbers_and_errors_name_typed_ids() {
        assert_eq!(serde_json::to_value(Row::new(7, "a")).unwrap()["id"], json!(7));
        assert_eq!(RowId::from(7).get(), 7);
        assert_eq!(RowId::from(7).to_string(), "7");
        let rows = Panel::new("p", "P", PanelRole::Tool, vec![Node::ItemList(ItemList::new("l", vec![Row::new(1, "a"), Row::new(1, "b")]))]);
        assert_eq!(rows.check().unwrap_err(), UiError::DuplicateRow { list: ControlId::from("l"), row: RowId::from(1) });
        let dup = Panel::new("p", "P", PanelRole::Tool, vec![Node::Toggle(Toggle::new("t", "T", true)), Node::Toggle(Toggle::new("t", "T", true))]);
        assert_eq!(dup.check().unwrap_err(), UiError::DuplicateControl { panel: PanelId::from("p"), control: ControlId::from("t") });
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
