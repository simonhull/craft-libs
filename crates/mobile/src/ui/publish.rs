//! Which panels are on screen, and telling the shell when they changed.

use std::collections::BTreeMap;

use serde::Serialize;

use super::{ControlId, Panel, PanelId, PanelInfo};

/// What the shell gets (wire kind 13): every panel the app offers, and the open ones described.
#[derive(Debug, PartialEq, Serialize)]
pub(super) struct Published {
    pub(super) panels: Vec<PanelInfo>,
    pub(super) open: BTreeMap<PanelId, Panel>,
}

impl Published {
    /// Equal but for the transports' positions.
    fn same_but_positions(&self, other: &Self) -> bool {
        self.panels == other.panels
            && self.open.len() == other.open.len()
            && self.open.iter().zip(&other.open).all(|((a_id, a), (b_id, b))| a_id == b_id && a.same_but_positions(b))
    }

    /// Every open transport's position, panel by panel, top to bottom.
    fn positions(&self) -> Vec<LiveValue> {
        self.open
            .iter()
            .flat_map(|(panel, p)| {
                p.transports().into_iter().map(|t| LiveValue { panel: panel.clone(), control: t.id.clone(), position: t.position })
            })
            .collect()
    }
}

/// One transport's position (wire kind 17 sends a list of them).
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub(super) struct LiveValue {
    pub(super) panel: PanelId,
    pub(super) control: ControlId,
    pub(super) position: u64,
}

/// What to send the shell after a frame: each `None` when there's nothing new.
#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct Outgoing {
    /// The panels, described (wire kind 13).
    pub(crate) panels: Option<String>,
    /// The transports' positions that changed, alone (wire kind 17).
    pub(crate) live: Option<String>,
}

/// The open panels and what was last sent.
#[derive(Debug, Default)]
pub(crate) struct PanelsState {
    open: Vec<PanelId>,
    sent: Option<Published>,
    /// Each open transport's position as the shell last heard it, in [`Published::positions`]'s
    /// order: the same transports, in the same order, while only positions change.
    positions: Vec<LiveValue>,
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

    /// Describe the open panels; the JSON to send for what changed since the last call.
    ///
    /// When only transports' positions changed (a transport playing), the panels aren't sent
    /// again: the positions that changed are, alone. Any other change sends the panels, positions
    /// included.
    ///
    /// A panel described under another id than asked for is dropped; one with duplicate ids is
    /// still published. Either is logged when what is sent changes, not every frame.
    pub(crate) fn publish(&mut self, panels: Vec<PanelInfo>, describe: impl Fn(&PanelId) -> Option<Panel>) -> Outgoing {
        let (now, problems) = self.describe(panels, describe);
        let positions = now.positions();
        if self.sent.as_ref().is_some_and(|sent| sent.same_but_positions(&now)) {
            let moved: Vec<&LiveValue> = positions.iter().zip(&self.positions).filter(|(now, heard)| now != heard).map(|(now, _)| now).collect();
            if moved.is_empty() {
                return Outgoing::default();
            }
            let live = serde_json::to_string(&moved).map_err(|e| log::error!("craft-mobile: live values: {e}")).ok();
            self.positions = positions;
            self.sent = Some(now);
            return Outgoing { panels: None, live };
        }
        for problem in &problems {
            log::warn!("craft-mobile: panels: {problem}");
        }
        let json = serde_json::to_string(&now).map_err(|e| log::error!("craft-mobile: panels: {e}")).ok();
        self.positions = positions;
        self.sent = Some(now);
        Outgoing { panels: json, live: None }
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
    use crate::ui::{FrameRange, Node, Panel, PanelInfo, PanelRole, Rate, Section, Toggle, Transport};
    use serde_json::json;

    fn info() -> Vec<PanelInfo> {
        vec![PanelInfo { id: "a".into(), title: "A".into(), icon: "square".into(), role: PanelRole::Inspector }]
    }

    fn describe(on: bool) -> impl Fn(&PanelId) -> Option<Panel> {
        move |id| (id.as_str() == "a").then(|| Panel::new("a", "A", PanelRole::Inspector, vec![Node::Toggle(Toggle::new("t", "T", on))]))
    }

    #[test]
    fn publishes_the_list_first_then_only_changes() {
        let mut s = PanelsState::default();
        let first = s.publish(info(), describe(false)).panels.unwrap();
        assert!(first.contains("\"panels\""), "{first}");
        assert!(!first.contains("\"t\""), "closed panels aren't described: {first}");
        assert_eq!(s.publish(info(), describe(false)).panels, None, "nothing changed");
        s.open(vec!["a".into()]);
        let opened = s.publish(info(), describe(false)).panels.unwrap();
        assert!(opened.contains("\"t\""), "{opened}");
        assert_eq!(s.publish(info(), describe(false)).panels, None);
        assert!(s.publish(info(), describe(true)).panels.is_some(), "a value changed");
    }

    #[test]
    fn unknown_open_ids_are_ignored() {
        let mut s = PanelsState::default();
        s.open(vec!["nope".into()]);
        let json = s.publish(info(), describe(false)).panels.unwrap();
        assert!(json.contains("\"open\":{}"), "{json}");
    }

    #[test]
    fn a_panel_under_another_id_is_dropped() {
        let mut s = PanelsState::default();
        s.open(vec!["a".into()]);
        let json = s.publish(info(), |_| Some(Panel::new("other", "O", PanelRole::Inspector, vec![]))).panels.unwrap();
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
        assert!(s.publish(info(), twice).panels.unwrap().contains("\"t\""));
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
        let first = s.publish(info(), describe(false)).panels;
        assert_eq!(s.publish(info(), describe(false)).panels, None);
        s.resend();
        assert_eq!(s.publish(info(), describe(false)).panels, first);
        assert_eq!(s.publish(info(), describe(false)).panels, None);
    }

    #[test]
    fn the_shell_reopening_gets_everything_again() {
        let mut s = PanelsState::default();
        s.open(vec!["a".into()]);
        assert!(s.publish(info(), describe(false)).panels.is_some());
        assert_eq!(s.publish(info(), describe(false)).panels, None);
        s.open(vec!["a".into()]);
        assert!(s.publish(info(), describe(false)).panels.is_some());
    }

    fn transport_info() -> Vec<PanelInfo> {
        vec![PanelInfo { id: "timeline".into(), title: "Timeline".into(), icon: "play".into(), role: PanelRole::Transport }]
    }

    fn transport(id: &str, position: u64, playing: bool) -> Node {
        let rate = Rate::new(24.0).unwrap();
        Node::Transport(Transport::new(id, position, 30, rate).unwrap().range(FrameRange::new(0, 24).ok()).unwrap().playing(playing))
    }

    /// A timeline panel: a transport, and another inside a section.
    fn timeline(main: u64, nested: u64, playing: bool) -> impl Fn(&PanelId) -> Option<Panel> {
        move |id| {
            (id.as_str() == "timeline").then(|| {
                let section = Node::Section(Section::new("more", "More", vec![transport("nested", nested, false)]));
                Panel::new("timeline", "Timeline", PanelRole::Transport, vec![transport("transport", main, playing), section])
            })
        }
    }

    fn opened() -> PanelsState {
        let mut s = PanelsState::default();
        s.open(vec!["timeline".into()]);
        s
    }

    fn live(json: Option<String>) -> serde_json::Value {
        serde_json::from_str(&json.unwrap()).unwrap()
    }

    /// Playing moves only the playhead: the panel isn't described again, only the position goes out.
    #[test]
    fn a_moving_playhead_goes_out_as_a_live_value() {
        let mut s = opened();
        let first = s.publish(transport_info(), timeline(0, 5, true));
        assert!(first.panels.is_some_and(|p| p.contains(r#""position":0"#)), "the description carries the position");
        assert_eq!(first.live, None, "the description said it already");
        let moved = s.publish(transport_info(), timeline(1, 5, true));
        assert_eq!(moved.panels, None, "nothing but the position changed");
        assert_eq!(live(moved.live), json!([{"panel": "timeline", "control": "transport", "position": 1}]));
        assert_eq!(s.publish(transport_info(), timeline(1, 5, true)), Outgoing::default(), "unchanged: nothing");
    }

    /// Only the transports that moved since the last send, each once, nested ones too.
    #[test]
    fn only_changed_positions_go_out() {
        let mut s = opened();
        let _ = s.publish(transport_info(), timeline(0, 5, true));
        let both = s.publish(transport_info(), timeline(1, 6, true));
        assert_eq!(
            live(both.live),
            json!([
                {"panel": "timeline", "control": "transport", "position": 1},
                {"panel": "timeline", "control": "nested", "position": 6}
            ])
        );
        let one = s.publish(transport_info(), timeline(1, 7, true));
        assert_eq!(live(one.live), json!([{"panel": "timeline", "control": "nested", "position": 7}]));
        let back = s.publish(transport_info(), timeline(0, 7, true));
        assert_eq!(live(back.live), json!([{"panel": "timeline", "control": "transport", "position": 0}]), "back to an old value is a change");
    }

    /// Anything else changing describes the panel again, with the positions as they are; the
    /// live values then count from that description.
    #[test]
    fn other_changes_describe_the_panel_with_its_position() {
        let mut s = opened();
        let _ = s.publish(transport_info(), timeline(0, 5, true));
        let paused = s.publish(transport_info(), timeline(3, 5, false));
        assert!(paused.panels.is_some_and(|p| p.contains(r#""position":3"#) && p.contains(r#""playing":false"#)));
        assert_eq!(paused.live, None, "the description carries the new position");
        assert_eq!(s.publish(transport_info(), timeline(3, 5, false)), Outgoing::default());
        s.resend();
        let again = s.publish(transport_info(), timeline(4, 5, false));
        assert!(again.panels.is_some_and(|p| p.contains(r#""position":4"#)), "a resend describes it whole");
        assert_eq!(again.live, None);
        s.open(vec!["timeline".into()]);
        assert!(s.publish(transport_info(), timeline(4, 5, false)).panels.is_some(), "a shell reopening gets everything");
    }

    /// The live-values message as the shell decodes it: entries of `{panel, control, position}`.
    #[test]
    fn live_values_serialize_as_documented() {
        let value = LiveValue { panel: "timeline".into(), control: "transport".into(), position: 12 };
        assert_eq!(serde_json::to_value([value]).unwrap(), json!([{"panel": "timeline", "control": "transport", "position": 12}]));
    }
}
