//! Native panels, described in Rust and drawn by the shells.
//!
//! An app lists its panels ([`PanelInfo`]) and builds each one as a tree of [`Node`]s on request.
//! The nodes say *what* (a number, a choice, a list of rows), never *where*: the shell picks the
//! native control and placement for the platform. Changes come back as [`Edit`]s.
//! The JSON every node becomes is listed in `catalogue/ui.md`.

/// A `u64` id newtype: plain on the wire, typed in Rust.
macro_rules! number_id {
    ($(#[$doc:meta])* $name:ident) => {
        $(#[$doc])*
        #[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, serde::Serialize, serde::Deserialize)]
        #[serde(transparent)]
        pub struct $name(u64);

        impl $name {
            /// The id as a number.
            #[must_use]
            pub const fn get(self) -> u64 {
                self.0
            }
        }

        impl From<u64> for $name {
            fn from(n: u64) -> Self {
                Self(n)
            }
        }

        impl From<$name> for u64 {
            fn from(id: $name) -> Self {
                id.0
            }
        }

        impl std::fmt::Display for $name {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                self.0.fmt(f)
            }
        }
    };
}

mod catalogue;
mod edit;
mod node;
mod publish;

pub use catalogue::{catalogue_json, catalogue_markdown};
pub use edit::{Edit, EditError, EditValue, GestureId, Message, Phase, Position, SelectMode};
pub use node::{
    Choice, ChoiceOption, ControlId, ItemList, Node, Number, Panel, PanelId, PanelInfo, PanelRole, Row, RowId, Scale, Section, Toggle, Unit,
};
pub(crate) use publish::PanelsState;
use publish::Published;

/// A node that can't be built as asked.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum UiError {
    /// A number's range is empty or not finite.
    #[error("`{id}`: the range is empty or not finite")]
    EmptyRange {
        /// The control.
        id: ControlId,
    },
    /// A number on a logarithmic scale has a range reaching zero or below.
    #[error("`{id}`: a logarithmic scale needs a minimum above zero")]
    LogScaleNeedsPositiveMin {
        /// The control.
        id: ControlId,
    },
    /// A choice's value isn't one of its options.
    #[error("`{id}`: `{value}` isn't one of the options")]
    UnknownOption {
        /// The control.
        id: ControlId,
        /// The value given.
        value: String,
    },
    /// Two options of a choice share an id.
    #[error("`{id}`: option `{option}` appears twice")]
    DuplicateOption {
        /// The control.
        id: ControlId,
        /// The repeated option id.
        option: String,
    },
    /// Two controls of a panel share an id.
    #[error("panel `{panel}`: control `{control}` appears twice")]
    DuplicateControl {
        /// The panel.
        panel: PanelId,
        /// The repeated control id.
        control: ControlId,
    },
    /// Two rows of a list share an id.
    #[error("list `{list}`: row {row} appears twice")]
    DuplicateRow {
        /// The list control.
        list: ControlId,
        /// The repeated row id.
        row: RowId,
    },
}
