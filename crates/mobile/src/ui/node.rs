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
    /// A vertical rail at the canvas's leading edge, always on screen while the shell draws the
    /// rail ([`super::Feature::Rail`]): the app's tools ([`super::ToolPalette`]).
    Rail,
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
    /// included), rows are unique within their list, a list's own actions within the list, and a
    /// row's actions within their row.
    ///
    /// # Errors
    /// [`UiError::DuplicateControl`], [`UiError::DuplicateRow`], [`UiError::DuplicateListAction`] or
    /// [`UiError::DuplicateRowAction`] for the first repeat found.
    pub fn check(&self) -> Result<(), UiError> {
        fn walk<'a>(panel: &PanelId, nodes: &'a [Node], seen: &mut HashSet<&'a ControlId>) -> Result<(), UiError> {
            for node in nodes {
                let id = match node {
                    Node::Section(s) => &s.id,
                    Node::Number(n) => &n.id,
                    Node::Toggle(t) => &t.id,
                    Node::Choice(c) => &c.id,
                    Node::ItemList(l) => &l.id,
                    Node::ToolPalette(p) => &p.id,
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
                        let mut actions = HashSet::new();
                        if let Some(dup) = l.actions.iter().find(|a| !actions.insert(&a.id)) {
                            return Err(UiError::DuplicateListAction { list: id.clone(), action: dup.id.clone() });
                        }
                        for row in &l.rows {
                            let mut actions = HashSet::new();
                            if let Some(dup) = row.actions.iter().find(|a| !actions.insert(&a.id)) {
                                return Err(UiError::DuplicateRowAction { list: id.clone(), row: row.id, action: dup.id.clone() });
                            }
                        }
                    }
                    Node::Number(_) | Node::Toggle(_) | Node::Choice(_) | Node::ToolPalette(_) => {}
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
    /// The app's tools, for a rail.
    ToolPalette(super::ToolPalette),
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

/// An [`ItemAction`]'s id, the app's own (`close`, `delete`, `new_layer`): unique within its row,
/// or among its list's own actions.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ActionId(String);

id_newtype!(ActionId);

/// Something the user can do in an [`ItemList`], to one row or to the list itself.
///
/// - A row's ([`Row::actions`]: Close a document, Delete a layer): the shell offers it in the row's
///   context menu, and a destructive one as a swipe action too. Chosen, it sends
///   [`super::EditValue::Action`].
/// - The list's own ([`ItemList::actions`]: New Layer, New Group): the shell shows it as an icon
///   button in the list's footer. Chosen, it sends [`super::EditValue::ListAction`].
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemAction {
    id: ActionId,
    label: String,
    /// An SF Symbol name; Android maps it to a Material icon.
    #[serde(default)]
    icon: Option<String>,
    /// It destroys something (Close, Delete): the shell tints it red, and offers a row's as a swipe.
    #[serde(default)]
    destructive: bool,
}

impl ItemAction {
    /// A plain action without an icon: `id` is what the edit carries, `label` what the user sees
    /// (in a menu, or as a footer button's accessibility label and tooltip).
    #[must_use]
    pub fn new(id: impl Into<ActionId>, label: impl Into<String>) -> Self {
        Self { id: id.into(), label: label.into(), icon: None, destructive: false }
    }

    /// An SF Symbol beside the label (`xmark`, `trash`); a list's footer button shows it alone,
    /// and the label where there is none.
    #[must_use]
    pub fn icon(mut self, symbol: Option<impl Into<String>>) -> Self {
        self.icon = symbol.map(Into::into);
        self
    }

    /// It destroys something: tinted red, and a row's is a swipe action too.
    #[must_use]
    pub fn destructive(mut self, destructive: bool) -> Self {
        self.destructive = destructive;
        self
    }

    /// Its id.
    #[must_use]
    pub fn id(&self) -> &ActionId {
        &self.id
    }
}

/// Whether the user can rename a row (its context menu's Rename…, [`super::EditValue::Rename`]).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Rename {
    /// Rename… is offered (the default).
    #[default]
    Allowed,
    /// The row has no name of its own to change (an open document): no Rename….
    No,
}

impl Rename {
    #[expect(clippy::trivially_copy_pass_by_ref, reason = "serde's `skip_serializing_if` passes a reference")]
    fn is_allowed(&self) -> bool {
        *self == Self::Allowed
    }
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
    /// Left out of the JSON when there are none; missing means none.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    actions: Vec<ItemAction>,
    /// Left out of the JSON when allowed; missing means allowed.
    #[serde(default, skip_serializing_if = "Rename::is_allowed")]
    rename: Rename,
}

impl Row {
    /// A top-level, unselected row that can't be hidden. `id` is the app's own (a layer id).
    #[must_use]
    pub fn new(id: impl Into<RowId>, title: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            title: title.into(),
            subtitle: String::new(),
            depth: 0,
            visible: None,
            selected: false,
            actions: Vec::new(),
            rename: Rename::Allowed,
        }
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

    /// Whether the user can rename it ([`Rename::Allowed`] unless set).
    #[must_use]
    pub fn rename(mut self, rename: Rename) -> Self {
        self.rename = rename;
        self
    }

    /// What the user can do to the row, in menu order ([`ItemAction`]); ids unique in the row.
    #[must_use]
    pub fn actions(mut self, actions: Vec<ItemAction>) -> Self {
        self.actions = actions;
        self
    }
}

/// Rows of items, top to bottom, and what the user can do to the list itself.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemList {
    id: ControlId,
    rows: Vec<Row>,
    reorderable: bool,
    /// Left out of the JSON when there are none; missing means none.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    actions: Vec<ItemAction>,
}

impl ItemList {
    /// A fixed-order list.
    #[must_use]
    pub fn new(id: impl Into<ControlId>, rows: Vec<Row>) -> Self {
        Self { id: id.into(), rows, reorderable: false, actions: Vec::new() }
    }

    /// What the user can do to the list rather than to one row (New Layer, New Group), in footer
    /// order ([`ItemAction`]); ids unique among them.
    #[must_use]
    pub fn actions(mut self, actions: Vec<ItemAction>) -> Self {
        self.actions = actions;
        self
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

    /// A row's actions are on the wire as listed; a row without any leaves them out, and one from an
    /// older app (no `actions`) has none.
    #[test]
    fn row_actions_serialize_and_default_to_none() {
        let row = Row::new(3, "a.psd")
            .actions(vec![ItemAction::new("close", "Close").icon(Some("xmark")).destructive(true), ItemAction::new("duplicate", "Duplicate")]);
        assert_eq!(
            serde_json::to_value(&row).unwrap()["actions"],
            json!([
                {"id": "close", "label": "Close", "icon": "xmark", "destructive": true},
                {"id": "duplicate", "label": "Duplicate", "icon": null, "destructive": false}
            ])
        );
        assert!(serde_json::to_value(Row::new(3, "a")).unwrap().get("actions").is_none(), "none, left out");
        let old: Row =
            serde_json::from_value(json!({"id": 3, "title": "a", "subtitle": "", "depth": 0, "visible": null, "selected": false})).unwrap();
        assert_eq!(old, Row::new(3, "a"));
        let partial: Row = serde_json::from_value(
            json!({"id": 3, "title": "a", "subtitle": "", "depth": 0, "visible": null, "selected": false, "actions": [{"id": "close", "label": "Close"}]}),
        )
        .unwrap();
        assert_eq!(partial, Row::new(3, "a").actions(vec![ItemAction::new("close", "Close")]), "icon and destructive are optional");
        assert_eq!(ItemAction::new("close", "Close").id().as_str(), "close");
    }

    /// A row is renamable unless it says otherwise; the JSON says so only for one that isn't, and a
    /// row from an older app (no `rename`) is renamable.
    #[test]
    fn a_row_can_refuse_renaming() {
        assert_eq!(Rename::default(), Rename::Allowed);
        let fixed = Row::new(3, "a.psd").rename(Rename::No);
        assert_eq!(serde_json::to_value(&fixed).unwrap()["rename"], json!("no"));
        assert!(serde_json::to_value(Row::new(3, "a")).unwrap().get("rename").is_none(), "allowed, left out");
        let old: Row =
            serde_json::from_value(json!({"id": 3, "title": "a", "subtitle": "", "depth": 0, "visible": null, "selected": false})).unwrap();
        assert_eq!(old, Row::new(3, "a").rename(Rename::Allowed));
        let back: Row = serde_json::from_value(serde_json::to_value(&fixed).unwrap()).unwrap();
        assert_eq!(back, fixed);
    }

    #[test]
    fn check_finds_duplicate_row_actions() {
        let twice = vec![ItemAction::new("close", "Close"), ItemAction::new("close", "Close Again")];
        let panel = Panel::new("p", "P", PanelRole::Inspector, vec![Node::ItemList(ItemList::new("l", vec![Row::new(1, "a").actions(twice)]))]);
        assert_eq!(panel.check().unwrap_err(), UiError::DuplicateRowAction { list: "l".into(), row: 1.into(), action: "close".into() });
    }

    /// A list's own actions are on the wire as listed; a list without any leaves them out, and one
    /// from an older app (no `actions`) has none.
    #[test]
    fn list_actions_serialize_and_default_to_none() {
        let list = ItemList::new("rows", vec![Row::new(1, "a")])
            .actions(vec![ItemAction::new("new_layer", "New Layer").icon(Some("plus")), ItemAction::new("new_group", "New Group")]);
        assert_eq!(
            serde_json::to_value(Node::ItemList(list.clone())).unwrap()["actions"],
            json!([
                {"id": "new_layer", "label": "New Layer", "icon": "plus", "destructive": false},
                {"id": "new_group", "label": "New Group", "icon": null, "destructive": false}
            ])
        );
        let back: Node = serde_json::from_value(serde_json::to_value(Node::ItemList(list.clone())).unwrap()).unwrap();
        assert_eq!(back, Node::ItemList(list));
        let plain = ItemList::new("rows", vec![]);
        assert!(serde_json::to_value(Node::ItemList(plain.clone())).unwrap().get("actions").is_none(), "none, left out");
        let old: Node = serde_json::from_value(json!({"type": "item_list", "id": "rows", "rows": [], "reorderable": false})).unwrap();
        assert_eq!(old, Node::ItemList(plain));
    }

    #[test]
    fn check_finds_duplicate_list_actions() {
        let twice = vec![ItemAction::new("new", "New"), ItemAction::new("new", "New Again")];
        let panel = Panel::new("p", "P", PanelRole::Inspector, vec![Node::ItemList(ItemList::new("l", vec![]).actions(twice))]);
        assert_eq!(panel.check().unwrap_err(), UiError::DuplicateListAction { list: "l".into(), action: "new".into() });
        let distinct = vec![ItemAction::new("new", "New")];
        let row = Row::new(1, "a").actions(vec![ItemAction::new("new", "New")]);
        let ok = Panel::new("p", "P", PanelRole::Inspector, vec![Node::ItemList(ItemList::new("l", vec![row]).actions(distinct))]);
        assert!(ok.check().is_ok(), "a row's action may share an id with the list's: they send different edits");
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
                    ItemList::new(
                        "rows",
                        vec![
                            Row::new(7, "Background")
                                .subtitle("Pixel")
                                .visible(Some(true))
                                .selected(true)
                                .actions(vec![ItemAction::new("delete", "Delete").icon(Some("trash")).destructive(true)]),
                        ],
                    )
                    .reorderable(true),
                ),
            ],
        );
        let json = serde_json::to_string(&panel).unwrap();
        assert_eq!(serde_json::from_str::<Panel>(&json).unwrap(), panel);
    }
}
