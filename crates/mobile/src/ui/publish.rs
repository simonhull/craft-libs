//! Which panels are on screen, and telling the shell when they changed.

use std::collections::BTreeMap;

use serde::Serialize;

use super::{Panel, PanelId, PanelInfo};

/// What the shell gets (wire kind 13): every panel the app offers, and the open ones described.
#[derive(Debug, PartialEq, Serialize)]
pub(super) struct Published {
    pub(super) panels: Vec<PanelInfo>,
    pub(super) open: BTreeMap<PanelId, Panel>,
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
        self.resend();
    }

    /// Send everything again with the next [`publish`](Self::publish), changed or not: an edit
    /// was rejected, and the shell's controls must show the app's values again.
    pub(crate) fn resend(&mut self) {
        self.sent = None;
    }

    /// Describe the open panels; the JSON to send if anything changed since the last call.
    ///
    /// A panel described under another id than asked for is dropped; one with duplicate ids is
    /// still published. Either is logged when what is sent changes, not every frame.
    pub(crate) fn publish(&mut self, panels: Vec<PanelInfo>, describe: impl Fn(&PanelId) -> Option<Panel>) -> Option<String> {
        let (now, problems) = self.describe(panels, describe);
        if self.sent.as_ref() == Some(&now) {
            return None;
        }
        for problem in &problems {
            log::warn!("craft-mobile: panels: {problem}");
        }
        let json = serde_json::to_string(&now).map_err(|e| log::error!("craft-mobile: panels: {e}")).ok();
        self.sent = Some(now);
        json
    }

    /// What to publish now, and what is wrong with it.
    fn describe(&self, panels: Vec<PanelInfo>, describe: impl Fn(&PanelId) -> Option<Panel>) -> (Published, Vec<String>) {
        let mut problems = Vec::new();
        let open = self
            .open
            .iter()
            .filter_map(|id| {
                let panel = describe(id)?;
                if panel.id() != id {
                    problems.push(format!("asked for `{id}`, got `{}`; dropped", panel.id()));
                    return None;
                }
                if let Err(e) = panel.check() {
                    problems.push(e.to_string());
                }
                Some((id.clone(), panel))
            })
            .collect();
        (Published { panels, open }, problems)
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
    fn problems_are_found_for_the_log() {
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
        let (_, problems) = s.describe(info(), twice);
        assert_eq!(problems.len(), 1, "{problems:?}");
        let (_, problems) = s.describe(info(), |_| Some(Panel::new("other", "O", PanelRole::Inspector, vec![])));
        assert!(problems.first().is_some_and(|p| p.contains("other")), "{problems:?}");
    }

    #[test]
    fn a_resend_sends_the_unchanged_panels_again() {
        let mut s = PanelsState::default();
        s.open(vec!["a".into()]);
        let first = s.publish(info(), describe(false));
        assert_eq!(s.publish(info(), describe(false)), None);
        s.resend();
        assert_eq!(s.publish(info(), describe(false)), first);
        assert_eq!(s.publish(info(), describe(false)), None);
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
