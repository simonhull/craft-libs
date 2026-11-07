//! Which panels are on screen, and telling the shell when they changed.

use std::collections::BTreeMap;

use serde::Serialize;

use super::{Panel, PanelId, PanelInfo};

/// What the shell gets (wire kind 13): every panel the app offers, and the open ones described.
#[derive(Debug, PartialEq, Serialize)]
struct Published {
    panels: Vec<PanelInfo>,
    open: BTreeMap<PanelId, Panel>,
}

/// The open panels and what was last sent.
#[derive(Debug, Default)]
pub(crate) struct PanelsState {
    open: Vec<PanelId>,
    sent: Option<Published>,
}

impl PanelsState {
    /// The shell's panels on screen now. The shell starts afresh whenever it says this, so the
    /// next [`publish`](Self::publish) sends everything again.
    pub(crate) fn open(&mut self, open: Vec<PanelId>) {
        self.open = open;
        self.sent = None;
    }

    /// Describe the open panels; the JSON to send if anything changed since the last call.
    ///
    /// A panel described under another id than asked for is dropped; one with duplicate ids is
    /// still published, with a warning.
    pub(crate) fn publish(&mut self, panels: Vec<PanelInfo>, describe: impl Fn(&PanelId) -> Option<Panel>) -> Option<String> {
        let open = self
            .open
            .iter()
            .filter_map(|id| {
                let panel = describe(id)?;
                if panel.id() != id {
                    log::warn!("craft-mobile: panels: asked for `{id}`, got `{}`; dropped", panel.id());
                    return None;
                }
                if let Err(e) = panel.check() {
                    log::warn!("craft-mobile: panels: {e}");
                }
                Some((id.clone(), panel))
            })
            .collect();
        let now = Published { panels, open };
        if self.sent.as_ref() == Some(&now) {
            return None;
        }
        let json = serde_json::to_string(&now).map_err(|e| log::error!("craft-mobile: panels: {e}")).ok();
        self.sent = Some(now);
        json
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ui::{Node, Panel, PanelInfo, PanelRole, Toggle};

    fn info() -> Vec<PanelInfo> {
        vec![PanelInfo { id: "a".into(), title: "A".into(), icon: "square".into(), role: PanelRole::Inspector }]
    }

    fn describe(on: bool) -> impl Fn(&PanelId) -> Option<Panel> {
        move |id| (id.0 == "a").then(|| Panel::new("a", "A", PanelRole::Inspector, vec![Node::Toggle(Toggle::new("t", "T", on))]))
    }

    #[test]
    fn publishes_the_list_first_then_only_changes() {
        let mut s = PanelsState::default();
        let first = s.publish(info(), describe(false)).unwrap();
        assert!(first.contains("\"panels\""), "{first}");
        assert!(!first.contains("\"t\""), "closed panels aren't described: {first}");
        assert_eq!(s.publish(info(), describe(false)), None, "nothing changed");
        s.open(vec!["a".into()]);
        let opened = s.publish(info(), describe(false)).unwrap();
        assert!(opened.contains("\"t\""), "{opened}");
        assert_eq!(s.publish(info(), describe(false)), None);
        assert!(s.publish(info(), describe(true)).is_some(), "a value changed");
    }

    #[test]
    fn unknown_open_ids_are_ignored() {
        let mut s = PanelsState::default();
        s.open(vec!["nope".into()]);
        let json = s.publish(info(), describe(false)).unwrap();
        assert!(json.contains("\"open\":{}"), "{json}");
    }

    #[test]
    fn a_panel_under_another_id_is_dropped() {
        let mut s = PanelsState::default();
        s.open(vec!["a".into()]);
        let json = s.publish(info(), |_| Some(Panel::new("other", "O", PanelRole::Inspector, vec![]))).unwrap();
        assert!(json.contains("\"open\":{}"), "{json}");
    }

    #[test]
    fn duplicate_ids_still_publish() {
        let mut s = PanelsState::default();
        s.open(vec!["a".into()]);
        let twice = |_: &PanelId| {
            Some(Panel::new(
                "a",
                "A",
                PanelRole::Inspector,
                vec![Node::Toggle(Toggle::new("t", "T", true)), Node::Toggle(Toggle::new("t", "T", true))],
            ))
        };
        assert!(s.publish(info(), twice).unwrap().contains("\"t\""));
    }

    #[test]
    fn the_shell_reopening_gets_everything_again() {
        let mut s = PanelsState::default();
        s.open(vec!["a".into()]);
        assert!(s.publish(info(), describe(false)).is_some());
        assert_eq!(s.publish(info(), describe(false)), None);
        s.open(vec!["a".into()]);
        assert!(s.publish(info(), describe(false)).is_some());
    }
}
