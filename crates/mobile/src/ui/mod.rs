//! Native panels, described in Rust and drawn by the shells.
//!
//! An app lists its panels ([`PanelInfo`]) and builds each one as a tree of [`Node`]s on request.
//! The nodes say *what* (a number, a choice, a list of rows), never *where*: the shell picks the
//! native control and placement for the platform. Changes come back as [`Edit`]s.
//! The JSON every node becomes is listed in `catalogue/ui.md`.

// mod catalogue;
mod edit;
mod node;
// mod publish;

// pub use catalogue::{catalogue_json, catalogue_markdown};
pub use edit::{Edit, EditValue, Message, Phase, Position};
pub use node::{Choice, ChoiceOption, ControlId, ItemList, Node, Number, Panel, PanelId, PanelInfo, PanelRole, Row, Section, Toggle, Unit};
// pub(crate) use publish::PanelsState;

/// A node that can't be built as asked.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum UiError {
    /// A number's range is empty or not finite.
    #[error("`{id}`: the range is empty or not finite")]
    EmptyRange {
        /// The control.
        id: String,
    },
    /// A choice's value isn't one of its options.
    #[error("`{id}`: `{value}` isn't one of the options")]
    UnknownOption {
        /// The control.
        id: String,
        /// The value given.
        value: String,
    },
}
