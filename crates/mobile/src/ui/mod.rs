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

/// Text-id newtype conveniences: `as_str`, `From<&str>`, `From<String>`, `AsRef<str>`, `Display`.
macro_rules! id_newtype {
    ($name:ident) => {
        impl $name {
            /// The id as text.
            #[must_use]
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl From<&str> for $name {
            fn from(s: &str) -> Self {
                Self(s.to_owned())
            }
        }

        impl From<String> for $name {
            fn from(s: String) -> Self {
                Self(s)
            }
        }

        impl AsRef<str> for $name {
            fn as_ref(&self) -> &str {
                &self.0
            }
        }

        impl std::fmt::Display for $name {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str(&self.0)
            }
        }
    };
}

mod catalogue;
mod command;
mod edit;
mod menu;
mod node;
mod publish;
mod rail;
mod shell;
mod status;

pub use catalogue::{catalogue_json, catalogue_markdown};
pub use command::{CommandId, Shortcut, named_keys};
pub use edit::{Edit, EditError, EditValue, GestureId, Message, Phase, Position, SelectMode};
pub use menu::{Menu, MenuBar, MenuCommand, MenuEntry, MenuRole, Submenu};
pub use node::{
    ActionId, Choice, ChoiceOption, ControlId, ItemList, Node, Number, Panel, PanelId, PanelInfo, PanelRole, Row, RowAction, RowId, Scale, Section,
    Toggle, Unit,
};
pub(crate) use publish::PanelsState;
use publish::Published;
pub use rail::{Icon, Tool, ToolId, ToolPalette, ToolSlot};
pub use shell::{Feature, ShellFeatures, UnknownFeature};
pub use status::{Progress, Status, StatusMessage, Tone};

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
    /// Two actions of a row share an id.
    #[error("list `{list}`: row {row} has action `{action}` twice")]
    DuplicateRowAction {
        /// The list control.
        list: ControlId,
        /// The row.
        row: RowId,
        /// The repeated action id.
        action: ActionId,
    },
    /// A shortcut that isn't in the portable form (`Cmd+Shift+Z`).
    #[error("`{shortcut}` isn't a shortcut: modifiers (Ctrl, Cmd, Alt, Shift), then one key, joined by `+`")]
    BadShortcut {
        /// The text given.
        shortcut: String,
    },
    /// A menu, submenu or command without a title or label.
    #[error("{context} has no label")]
    EmptyLabel {
        /// Which one.
        context: String,
    },
    /// A command appears twice in the menu bar.
    #[error("command `{command}` appears twice in the menus")]
    DuplicateCommand {
        /// The repeated command.
        command: CommandId,
    },
    /// A tool palette has a slot without tools.
    #[error("palette `{palette}`: a slot has no tools")]
    EmptySlot {
        /// The palette.
        palette: ControlId,
    },
    /// Two tools of a palette share an id.
    #[error("palette `{palette}`: tool `{tool}` appears twice")]
    DuplicateTool {
        /// The palette.
        palette: ControlId,
        /// The repeated tool.
        tool: ToolId,
    },
    /// A palette's selected tool isn't one of its tools.
    #[error("palette `{palette}`: the selected tool `{tool}` isn't one of its tools")]
    UnknownTool {
        /// The palette.
        palette: ControlId,
        /// The tool given.
        tool: ToolId,
    },
}
