//! What the app is telling the user, for the shell's native status.

use serde::{Deserialize, Serialize};

use super::CommandId;

/// The app's status (wire kind 16, [`crate::Platform::set_status`]): a message, and the progress of
/// a long job. The shell shows a message as a toast when it changes, and progress while it lasts.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Status {
    message: Option<StatusMessage>,
    progress: Option<Progress>,
}

impl Status {
    /// Nothing to say.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Say `text` ("Saved a.psd"). Empty text says nothing.
    #[must_use]
    pub fn info(self, text: impl Into<String>) -> Self {
        self.with_message(text.into(), Tone::Info)
    }

    /// Say that something went wrong ("Couldn't open b.psd"). Empty text says nothing.
    #[must_use]
    pub fn error(self, text: impl Into<String>) -> Self {
        self.with_message(text.into(), Tone::Error)
    }

    fn with_message(mut self, text: String, tone: Tone) -> Self {
        self.message = (!text.trim().is_empty()).then_some(StatusMessage { text, tone, id: 0 });
        self
    }

    /// Number the message, so the same text said again shows again: give each new message a new
    /// id (a counter of the app's), and keep it while the message stands. New text with the same id
    /// (a countdown: "retrying in 3 s", "in 2 s") updates the message on screen in place, and a
    /// message dismissed stays so. Without one (0), a message shows when its text or tone changes.
    #[must_use]
    pub fn message_id(mut self, id: u64) -> Self {
        if let Some(message) = &mut self.message {
            message.id = id;
        }
        self
    }

    /// A job in progress.
    #[must_use]
    pub fn progress(mut self, progress: Progress) -> Self {
        self.progress = Some(progress);
        self
    }

    /// The message, if any.
    #[must_use]
    pub fn message(&self) -> Option<&StatusMessage> {
        self.message.as_ref()
    }
}

/// A message of the [`Status`].
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StatusMessage {
    text: String,
    tone: Tone,
    /// Tells the same text said again apart from it still being said: the shell shows a new id as
    /// a new message, and new text with the same id as that message updated. 0 when left out: then
    /// new text or tone is a new message.
    #[serde(default)]
    id: u64,
}

impl StatusMessage {
    /// What it says.
    #[must_use]
    pub fn text(&self) -> &str {
        &self.text
    }

    /// Its id ([`Status::message_id`]).
    #[must_use]
    pub fn id(&self) -> u64 {
        self.id
    }

    /// Whether it reports a failure.
    #[must_use]
    pub fn tone(&self) -> Tone {
        self.tone
    }
}

/// What kind of message it is; the shell tints an error.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Tone {
    /// News: it worked, it's done.
    #[default]
    Info,
    /// Something went wrong.
    Error,
}

/// A long job: what it is, how far along, and how to stop it.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Progress {
    label: String,
    fraction: Option<f64>,
    cancel: Option<CommandId>,
}

impl Progress {
    /// A job of unknown length ("Exporting a.png").
    #[must_use]
    pub fn new(label: impl Into<String>) -> Self {
        Self { label: label.into(), fraction: None, cancel: None }
    }

    /// How much is done, 0..=1 (clamped); a value that isn't a number means unknown.
    #[must_use]
    pub fn fraction(mut self, fraction: f64) -> Self {
        self.fraction = fraction.is_finite().then(|| fraction.clamp(0.0, 1.0));
        self
    }

    /// The command that stops it: the shell shows a Cancel button that runs it.
    #[must_use]
    pub fn cancel(mut self, command: impl Into<CommandId>) -> Self {
        self.cancel = Some(command.into());
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_status_serializes_as_documented() {
        let status = Status::new().error("Couldn't open b.psd").progress(Progress::new("Exporting a.png").fraction(0.25).cancel("job.cancel"));
        assert_eq!(
            serde_json::to_value(&status).unwrap(),
            json!({"message": {"text": "Couldn't open b.psd", "tone": "error", "id": 0}, "progress": {"label": "Exporting a.png", "fraction": 0.25, "cancel": "job.cancel"}})
        );
        assert_eq!(serde_json::to_value(Status::new()).unwrap(), json!({"message": null, "progress": null}));
    }

    #[test]
    fn empty_text_says_nothing_and_fractions_stay_in_range() {
        assert_eq!(Status::new().info("  "), Status::new());
        assert_eq!(Status::new().info("Saved").message().map(StatusMessage::tone), Some(Tone::Info));
        assert_eq!(Status::new().info("Saved").message().map(StatusMessage::text), Some("Saved"));
        let fraction = |f: f64| serde_json::to_value(Progress::new("p").fraction(f)).unwrap()["fraction"].clone();
        assert_eq!(fraction(1.5), json!(1.0));
        assert_eq!(fraction(-1.0), json!(0.0));
        assert_eq!(fraction(f64::NAN), json!(null));
    }

    /// Two saves say "Saved" twice: a new id makes the second a new message; older apps send none.
    #[test]
    fn a_message_id_tells_repeats_apart() {
        let first = Status::new().info("Saved").message_id(1);
        let second = Status::new().info("Saved").message_id(2);
        assert_ne!(first, second);
        assert_eq!(second.message().map(StatusMessage::id), Some(2));
        assert_eq!(Status::new().message_id(3), Status::new(), "no message, nothing to number");
        let old: Status = serde_json::from_value(json!({"message": {"text": "Saved", "tone": "info"}, "progress": null})).unwrap();
        assert_eq!(old, Status::new().info("Saved"));
    }

    #[test]
    fn a_status_round_trips() {
        let status = Status::new().info("Saved a.psd").progress(Progress::new("Exporting"));
        let json = serde_json::to_string(&status).unwrap();
        assert_eq!(serde_json::from_str::<Status>(&json).unwrap(), status);
    }
}
