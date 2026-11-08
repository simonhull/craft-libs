//! A transport bar: where the playhead is in a span of frames, and buttons to play through them.
//!
//! [`Transport`] describes the bar; [`Playback`] is the clock an app plays it with.

use std::fmt;
use std::num::NonZeroU64;

use serde::{Deserialize, Serialize};

use super::{ControlId, UiError};

/// Frames per second: finite and above zero, and not necessarily whole (29.97).
#[derive(Clone, Copy, Debug, PartialEq, PartialOrd, Serialize, Deserialize)]
#[serde(try_from = "f64", into = "f64")]
pub struct Rate(f64);

impl Rate {
    /// A rate of `fps` frames per second.
    ///
    /// # Errors
    /// [`UiError::BadRate`] unless `fps` is finite and above zero.
    pub fn new(fps: f64) -> Result<Self, UiError> {
        if fps.is_finite() && fps > 0.0 { Ok(Self(fps)) } else { Err(UiError::BadRate) }
    }

    /// Frames per second.
    #[must_use]
    pub const fn get(self) -> f64 {
        self.0
    }
}

impl TryFrom<f64> for Rate {
    type Error = UiError;

    fn try_from(fps: f64) -> Result<Self, UiError> {
        Self::new(fps)
    }
}

impl From<Rate> for f64 {
    fn from(rate: Rate) -> Self {
        rate.0
    }
}

impl fmt::Display for Rate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

/// A span of frames, `start` inclusive and `end` exclusive, never empty: a transport's work area,
/// or what [`Playback`] loops over. `[start, end]` on the wire.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(try_from = "(u64, u64)", into = "(u64, u64)")]
pub struct FrameRange {
    start: u64,
    end: u64,
}

impl FrameRange {
    /// The frames from `start` up to, not including, `end`.
    ///
    /// # Errors
    /// [`UiError::EmptyFrameRange`] unless `start < end`.
    pub fn new(start: u64, end: u64) -> Result<Self, UiError> {
        if start < end { Ok(Self { start, end }) } else { Err(UiError::EmptyFrameRange { start, end }) }
    }

    /// The first frame.
    #[must_use]
    pub const fn start(self) -> u64 {
        self.start
    }

    /// The frame after the last.
    #[must_use]
    pub const fn end(self) -> u64 {
        self.end
    }

    /// How many frames it holds.
    #[must_use]
    pub const fn frames(self) -> NonZeroU64 {
        match NonZeroU64::new(self.end - self.start) {
            Some(frames) => frames,
            // `new` guarantees `start < end`.
            None => NonZeroU64::MIN,
        }
    }

    /// Whether `frame` is one of its frames.
    #[must_use]
    pub const fn contains(self, frame: u64) -> bool {
        self.start <= frame && frame < self.end
    }
}

impl TryFrom<(u64, u64)> for FrameRange {
    type Error = UiError;

    fn try_from((start, end): (u64, u64)) -> Result<Self, UiError> {
        Self::new(start, end)
    }
}

impl From<FrameRange> for (u64, u64) {
    fn from(range: FrameRange) -> Self {
        (range.start, range.end)
    }
}

/// How a [`Transport`] shows a time. Display only: positions and edits are always frames.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimeFormat {
    /// The frame, counted from 1, and how many there are: "12 / 30".
    #[default]
    Frames,
    /// Hours, minutes, seconds and frames at the transport's rate: "00:00:00:11".
    Timecode,
}

/// A transport bar: to start, step back, play or pause, step forward, to end, and a scrubber over
/// the frames with the work area shaded.
///
/// While it plays, the app moves its `position` each frame; the host sends the shell only the new
/// position (wire kind 17), not the whole panel, unless something else changed too.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(try_from = "TransportRepr")]
pub struct Transport {
    pub(super) id: ControlId,
    pub(super) position: u64,
    duration: NonZeroU64,
    rate: Rate,
    format: TimeFormat,
    playing: bool,
    range: Option<FrameRange>,
    enabled: bool,
}

impl Transport {
    /// A paused transport over `duration` frames at `rate`, its playhead at frame `position`
    /// (counted from 0), showing [`TimeFormat::Frames`], without a work area.
    ///
    /// # Errors
    /// [`UiError::NoFrames`] when `duration` is 0, [`UiError::FrameOutOfRange`] when `position`
    /// isn't below it.
    pub fn new(id: impl Into<ControlId>, position: u64, duration: u64, rate: Rate) -> Result<Self, UiError> {
        let id = id.into();
        let Some(duration) = NonZeroU64::new(duration) else {
            return Err(UiError::NoFrames { id });
        };
        if position >= duration.get() {
            return Err(UiError::FrameOutOfRange { id, frame: position, duration: duration.get() });
        }
        Ok(Self { id, position, duration, rate, format: TimeFormat::Frames, playing: false, range: None, enabled: true })
    }

    /// The work area (the loop region), shaded on the scrubber; `None` for none.
    ///
    /// # Errors
    /// [`UiError::RangeOutOfBounds`] when it ends past the last frame.
    pub fn range(mut self, range: Option<FrameRange>) -> Result<Self, UiError> {
        if let Some(r) = range
            && r.end() > self.duration.get()
        {
            return Err(UiError::RangeOutOfBounds { id: self.id, end: r.end(), duration: self.duration.get() });
        }
        self.range = range;
        Ok(self)
    }

    /// How it shows times ([`TimeFormat::Frames`] unless set).
    #[must_use]
    pub fn format(mut self, format: TimeFormat) -> Self {
        self.format = format;
        self
    }

    /// Playing: the play button shows Pause.
    #[must_use]
    pub fn playing(mut self, playing: bool) -> Self {
        self.playing = playing;
        self
    }

    /// Greyed out when `false`.
    #[must_use]
    pub fn enabled(mut self, enabled: bool) -> Self {
        self.enabled = enabled;
        self
    }

    /// The playhead's frame, counted from 0.
    #[must_use]
    pub fn position(&self) -> u64 {
        self.position
    }

    /// Equal but for the position: what decides whether the panel is described again or only the
    /// position is sent.
    pub(super) fn same_but_position(&self, other: &Self) -> bool {
        let Self { id, position: _, duration, rate, format, playing, range, enabled } = self;
        *id == other.id
            && *duration == other.duration
            && *rate == other.rate
            && *format == other.format
            && *playing == other.playing
            && *range == other.range
            && *enabled == other.enabled
    }
}

/// [`Transport`] as it arrives on the wire, before validation.
#[derive(Deserialize)]
struct TransportRepr {
    id: ControlId,
    position: u64,
    duration: u64,
    rate: Rate,
    #[serde(default)]
    format: TimeFormat,
    playing: bool,
    #[serde(default)]
    range: Option<FrameRange>,
    enabled: bool,
}

impl TryFrom<TransportRepr> for Transport {
    type Error = UiError;

    fn try_from(r: TransportRepr) -> Result<Self, UiError> {
        Ok(Self::new(r.id, r.position, r.duration, r.rate)?.range(r.range)?.format(r.format).playing(r.playing).enabled(r.enabled))
    }
}

/// A playback clock: which frame to show at a given time, so playback keeps time whatever the
/// frame rate of the UI.
///
/// Pure: the caller passes the time, in seconds from any fixed origin (a monotonic clock's), and
/// shows what [`tick`](Self::tick) returns. A slow UI skips frames rather than slowing playback;
/// past the end of the span it wraps to the start. Times that aren't numbers, or that go
/// backwards, never move the playhead.
///
/// ```
/// use craft_mobile::ui::{FrameRange, Playback, Rate};
/// # fn main() -> Result<(), craft_mobile::ui::UiError> {
/// let mut playback = Playback::new(Rate::new(24.0)?, FrameRange::new(0, 48)?);
/// assert_eq!(playback.start(10.0, 46), 46);
/// assert_eq!(playback.tick(10.01), None, "still frame 46");
/// assert_eq!(playback.tick(10.125), Some(1), "three frames on: 47, then round to 0 and 1");
/// # Ok(())
/// # }
/// ```
#[derive(Clone, Debug, PartialEq)]
pub struct Playback {
    rate: Rate,
    span: FrameRange,
    /// The frame shown: always in `span`.
    frame: u64,
    state: State,
}

/// Whether a [`Playback`] runs.
#[derive(Clone, Copy, Debug, PartialEq)]
enum State {
    Stopped,
    /// `since`: when `frame` started showing; `None` until a time that is a number arrives.
    Playing {
        since: Option<f64>,
    },
}

impl Playback {
    /// A stopped clock at `rate` that loops over `span`: a transport's work area, or all of its
    /// frames.
    #[must_use]
    pub fn new(rate: Rate, span: FrameRange) -> Self {
        Self { rate, span, frame: span.start(), state: State::Stopped }
    }

    /// Play from frame `from` at time `now`, or from the start of the span when `from` is outside
    /// it; starting while playing starts afresh. Returns the frame to show now.
    pub fn start(&mut self, now: f64, from: u64) -> u64 {
        self.frame = if self.span.contains(from) { from } else { self.span.start() };
        self.state = State::Playing { since: now.is_finite().then_some(now) };
        self.frame
    }

    /// Stop, holding the frame.
    pub fn stop(&mut self) {
        self.state = State::Stopped;
    }

    /// Whether it plays.
    #[must_use]
    pub fn is_playing(&self) -> bool {
        matches!(self.state, State::Playing { .. })
    }

    /// The frame shown.
    #[must_use]
    pub fn frame(&self) -> u64 {
        self.frame
    }

    /// The frame to show at `now`, when it differs from the one shown: as many frames on as the
    /// time since the last allows (never more), wrapped into the span. `None` while stopped, while
    /// on the same frame, and for a time that isn't a number or is earlier than the last (the clock
    /// then counts on from `now`).
    pub fn tick(&mut self, now: f64) -> Option<u64> {
        let State::Playing { since } = &mut self.state else {
            return None;
        };
        if !now.is_finite() {
            return None;
        }
        let Some(then) = *since else {
            *since = Some(now);
            return None;
        };
        let whole = ((now - then) * self.rate.get()).floor();
        // Backwards, or too far apart to count: hold the frame and count from now.
        if !(whole.is_finite() && whole >= 0.0) {
            *since = Some(now);
            return None;
        }
        if whole < 1.0 {
            return None;
        }
        // The frames' remainder of time stays, so irregular ticks never drift.
        *since = Some(then + whole / self.rate.get());
        #[expect(clippy::cast_possible_truncation, clippy::cast_sign_loss, reason = "finite and at least 1; a float-to-int cast saturates")]
        let steps = whole as u64;
        let next = self.advance(steps);
        let changed = next != self.frame;
        self.frame = next;
        changed.then_some(next)
    }

    /// Seconds from `now` until the frame shown changes: when to [`tick`](Self::tick) next, so a
    /// UI can sleep between frames rather than redraw at the display's rate. Ask after ticking.
    ///
    /// `0.0` when a new frame is already due (`now` is on or past the boundary and hasn't been
    /// ticked). A whole period while the clock has no start yet, for a time that isn't a number, or
    /// one earlier than the last (the next tick counts on from it). `None` while stopped, and for a
    /// span of one frame, which never changes.
    ///
    /// Exact but for float rounding, which may put the boundary a hair later: a caller that must
    /// never draw a frame late wakes a little early.
    ///
    /// ```
    /// use craft_mobile::ui::{FrameRange, Playback, Rate};
    /// # fn main() -> Result<(), craft_mobile::ui::UiError> {
    /// let mut playback = Playback::new(Rate::new(4.0)?, FrameRange::new(0, 8)?);
    /// assert_eq!(playback.next_due(0.0), None, "stopped");
    /// playback.start(10.0, 0);
    /// assert_eq!(playback.next_due(10.125), Some(0.125), "frame 1 shows at 10.25");
    /// assert_eq!(playback.next_due(10.25), Some(0.0), "due now");
    /// # Ok(())
    /// # }
    /// ```
    #[must_use]
    pub fn next_due(&self, now: f64) -> Option<f64> {
        let State::Playing { since } = self.state else {
            return None;
        };
        if self.span.frames().get() == 1 {
            return None;
        }
        let period = self.rate.get().recip();
        let Some(then) = since.filter(|_| now.is_finite()) else {
            return Some(period);
        };
        // In frames, as `tick` counts them, so the two agree on where the boundary is.
        let elapsed = (now - then) * self.rate.get();
        if !(elapsed.is_finite() && elapsed >= 0.0) {
            return Some(period);
        }
        Some(if elapsed >= 1.0 { 0.0 } else { (1.0 - elapsed) * period })
    }

    /// The frame `steps` on from the one shown, wrapped into the span, without overflowing.
    fn advance(&self, steps: u64) -> u64 {
        let len = self.span.frames().get();
        let offset = self.frame - self.span.start();
        let step = steps % len;
        let room = len - step;
        let offset = if offset >= room { offset - room } else { offset + step };
        self.span.start() + offset
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ui::{Node, UiError};
    use serde_json::json;

    fn rate(fps: f64) -> Rate {
        Rate::new(fps).unwrap()
    }

    #[test]
    fn a_rate_is_finite_and_above_zero() {
        for bad in [0.0, -24.0, f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            assert_eq!(Rate::new(bad), Err(UiError::BadRate), "{bad}");
        }
        assert!((rate(29.97).get() - 29.97).abs() < f64::EPSILON);
        assert_eq!(Rate::try_from(24.0), Ok(rate(24.0)));
        assert!((f64::from(rate(24.0)) - 24.0).abs() < f64::EPSILON);
        assert_eq!(rate(29.97).to_string(), "29.97");
        assert!(serde_json::from_value::<Rate>(json!(0.0)).is_err());
        assert_eq!(serde_json::to_value(rate(25.0)).unwrap(), json!(25.0));
    }

    #[test]
    fn a_frame_range_is_not_empty() {
        assert_eq!(FrameRange::new(4, 4), Err(UiError::EmptyFrameRange { start: 4, end: 4 }));
        assert_eq!(FrameRange::new(5, 4), Err(UiError::EmptyFrameRange { start: 5, end: 4 }));
        let range = FrameRange::new(2, 6).unwrap();
        assert_eq!((range.start(), range.end(), range.frames().get()), (2, 6, 4));
        assert!(range.contains(2) && range.contains(5));
        assert!(!range.contains(1) && !range.contains(6), "start inclusive, end exclusive");
        assert_eq!(serde_json::to_value(range).unwrap(), json!([2, 6]));
        assert_eq!(serde_json::from_value::<FrameRange>(json!([2, 6])).unwrap(), range);
        assert!(serde_json::from_value::<FrameRange>(json!([6, 2])).is_err());
    }

    #[test]
    fn a_transport_validates_its_frames() {
        assert_eq!(Transport::new("t", 0, 0, rate(24.0)).unwrap_err(), UiError::NoFrames { id: "t".into() });
        assert_eq!(Transport::new("t", 30, 30, rate(24.0)).unwrap_err(), UiError::FrameOutOfRange { id: "t".into(), frame: 30, duration: 30 });
        let t = Transport::new("t", 29, 30, rate(24.0)).unwrap();
        assert_eq!(t.position(), 29);
        assert_eq!(t.clone().range(FrameRange::new(10, 31).ok()).unwrap_err(), UiError::RangeOutOfBounds { id: "t".into(), end: 31, duration: 30 });
        assert!(t.clone().range(FrameRange::new(10, 30).ok()).is_ok(), "the range may end at the last frame");
        assert!(t.range(None).is_ok());
    }

    #[test]
    fn a_transport_serializes_as_documented() {
        let t = Transport::new("transport", 11, 30, rate(24.0))
            .unwrap()
            .range(FrameRange::new(0, 24).ok())
            .unwrap()
            .format(TimeFormat::Timecode)
            .playing(true);
        assert_eq!(
            serde_json::to_value(Node::Transport(t)).unwrap(),
            json!({"type": "transport", "id": "transport", "position": 11, "duration": 30, "rate": 24.0, "format": "timecode", "playing": true, "range": [0, 24], "enabled": true})
        );
        let plain = Transport::new("transport", 0, 1, rate(29.97)).unwrap().enabled(false);
        assert_eq!(
            serde_json::to_value(Node::Transport(plain)).unwrap(),
            json!({"type": "transport", "id": "transport", "position": 0, "duration": 1, "rate": 29.97, "format": "frames", "playing": false, "range": null, "enabled": false})
        );
    }

    #[test]
    fn a_transport_round_trips_and_deserializing_validates() {
        let t = Transport::new("transport", 3, 10, rate(12.0)).unwrap().range(FrameRange::new(2, 8).ok()).unwrap();
        let json = serde_json::to_value(Node::Transport(t.clone())).unwrap();
        assert_eq!(serde_json::from_value::<Node>(json.clone()).unwrap(), Node::Transport(t.clone()));
        for (field, bad) in
            [("position", json!(10)), ("duration", json!(0)), ("rate", json!(0.0)), ("range", json!([2, 11])), ("range", json!([5, 5]))]
        {
            let mut bad_json = json.clone();
            bad_json[field] = bad.clone();
            assert!(serde_json::from_value::<Node>(bad_json).is_err(), "{field}: {bad}");
        }
        let mut lenient = json;
        if let Some(fields) = lenient.as_object_mut() {
            fields.remove("format");
            fields.remove("range");
        }
        let expected = Transport::new("transport", 3, 10, rate(12.0)).unwrap();
        assert_eq!(serde_json::from_value::<Node>(lenient).unwrap(), Node::Transport(expected), "format and range may be left out");
    }

    /// 4 fps keeps every time below exact in binary.
    fn playback(span: (u64, u64)) -> Playback {
        Playback::new(rate(4.0), FrameRange::new(span.0, span.1).unwrap())
    }

    #[test]
    fn playback_steps_one_frame_per_period() {
        let mut p = playback((0, 30));
        assert!(!p.is_playing());
        assert_eq!(p.tick(1.0), None, "stopped");
        assert_eq!(p.start(10.0, 0), 0);
        assert!(p.is_playing());
        assert_eq!(p.tick(10.0), None, "no time has passed");
        assert_eq!(p.tick(10.125), None, "half a frame");
        assert_eq!(p.tick(10.25), Some(1));
        assert_eq!(p.tick(10.375), None, "still frame 1");
        assert_eq!(p.tick(10.5), Some(2));
        assert_eq!(p.frame(), 2);
    }

    #[test]
    fn playback_catches_up_rather_than_slowing_down() {
        let mut p = playback((0, 30));
        p.start(0.0, 0);
        assert_eq!(p.tick(1.0), Some(4), "a slow frame skips frames 1–3");
        // Irregular ticks keep the remainder: the frame is always the elapsed time's.
        let mut shown = 4;
        for (now, frame) in [(1.1, 4), (1.3, 5), (1.45, 5), (1.9, 7), (2.05, 8), (2.6, 10), (3.33, 13)] {
            if let Some(f) = p.tick(now) {
                shown = f;
            }
            assert_eq!(shown, frame, "at {now}");
        }
    }

    #[test]
    fn playback_wraps_within_the_whole_duration() {
        let mut p = playback((0, 5));
        p.start(0.0, 3);
        assert_eq!(p.tick(0.25), Some(4));
        assert_eq!(p.tick(0.5), Some(0), "past the last frame, back to the first");
        assert_eq!(p.tick(3.0), None, "ten frames later: twice round, on frame 0 again");
        assert_eq!(p.frame(), 0);
        assert_eq!(p.tick(3.25), Some(1));
    }

    #[test]
    fn playback_wraps_within_a_range() {
        let mut p = playback((10, 14));
        assert_eq!(p.start(0.0, 12), 12);
        assert_eq!(p.tick(1.25), Some(13), "five frames on: 12 → 13 → 10 → 11 → 12 → 13");
        assert_eq!(p.tick(1.5), Some(10));
        let mut outside = playback((10, 14));
        assert_eq!(outside.start(0.0, 20), 10, "from outside the range, it starts at the range");
        assert_eq!(outside.start(0.0, 3), 10);
        assert_eq!(outside.tick(0.25), Some(11));
    }

    #[test]
    fn a_one_frame_span_never_changes() {
        let mut p = playback((7, 8));
        p.start(0.0, 7);
        assert_eq!(p.tick(100.0), None);
        assert_eq!(p.frame(), 7);
    }

    #[test]
    fn stopping_holds_the_frame_and_starting_again_counts_from_then() {
        let mut p = playback((0, 30));
        p.start(0.0, 0);
        assert_eq!(p.tick(0.5), Some(2));
        p.stop();
        assert!(!p.is_playing());
        assert_eq!(p.tick(5.0), None);
        assert_eq!(p.frame(), 2, "stopped where it was");
        assert_eq!(p.start(60.0, p.frame()), 2);
        assert_eq!(p.tick(60.0), None, "the time stopped doesn't count");
        assert_eq!(p.tick(60.25), Some(3));
        assert_eq!(p.start(60.25, 9), 9, "starting while playing starts afresh");
        assert_eq!(p.tick(60.5), Some(10));
    }

    #[test]
    fn bad_time_never_moves_the_playhead() {
        let mut p = playback((0, 30));
        p.start(f64::NAN, 0);
        assert!(p.is_playing());
        assert_eq!(p.tick(f64::NAN), None);
        assert_eq!(p.tick(f64::INFINITY), None);
        assert_eq!(p.tick(2.0), None, "the first good time is the start");
        assert_eq!(p.tick(2.25), Some(1));
        assert_eq!(p.tick(1.0), None, "time went backwards: hold the frame");
        assert_eq!(p.tick(1.25), Some(2), "and count from there");
        assert_eq!(p.tick(f64::NEG_INFINITY), None);
        assert_eq!(p.frame(), 2);
    }

    /// Seconds equal to within rounding.
    fn due(actual: Option<f64>, expected: f64) -> bool {
        actual.is_some_and(|d| (d - expected).abs() < 1e-9)
    }

    #[test]
    fn next_due_is_none_while_stopped() {
        let mut p = playback((0, 30));
        assert_eq!(p.next_due(1.0), None, "never started");
        p.start(0.0, 0);
        p.stop();
        assert_eq!(p.next_due(0.1), None, "stopped");
    }

    #[test]
    fn next_due_counts_down_to_the_next_frame() {
        let mut p = playback((0, 30));
        p.start(10.0, 0);
        assert!(due(p.next_due(10.0), 0.25), "just started: a whole period");
        assert!(due(p.next_due(10.125), 0.125), "half way through the period");
        assert!(due(p.next_due(10.2), 0.05));
        assert_eq!(p.tick(10.2), None, "and the frame hasn't changed yet");
    }

    #[test]
    fn next_due_on_a_boundary_is_now_until_ticked() {
        let mut p = playback((0, 30));
        p.start(10.0, 0);
        assert_eq!(p.next_due(10.25), Some(0.0), "frame 1 is due now");
        assert_eq!(p.next_due(11.0), Some(0.0), "overdue is due now too");
        assert_eq!(p.tick(10.25), Some(1));
        assert!(due(p.next_due(10.25), 0.25), "shown: the next is a whole period on");
    }

    #[test]
    fn next_due_after_a_catch_up_keeps_the_remainder() {
        let mut p = playback((0, 30));
        p.start(0.0, 0);
        assert_eq!(p.tick(1.1), Some(4), "a slow frame skips ahead");
        assert!(due(p.next_due(1.1), 0.15), "frame 5 is due at 1.25, not a period after the tick");
    }

    #[test]
    fn ticking_when_due_always_moves_the_playhead() {
        let mut p = Playback::new(rate(23.976), FrameRange::new(0, 1000).unwrap());
        let mut now = 3.7;
        p.start(now, 0);
        for frame in 1..200 {
            now += p.next_due(now).unwrap();
            // Rounding may land a hair short of the boundary: then it is due again at once.
            let shown = p.tick(now).or_else(|| {
                assert!(p.next_due(now).unwrap() < 1e-9, "only a hair short, at frame {frame}");
                p.tick(now + 1e-9)
            });
            assert_eq!(shown, Some(frame), "at {now}");
        }
    }

    #[test]
    fn next_due_with_a_bad_or_backwards_time_is_a_period() {
        let mut p = playback((0, 30));
        p.start(f64::NAN, 0);
        assert!(due(p.next_due(2.0), 0.25), "no start time yet: the first good tick starts the clock");
        assert!(due(p.next_due(f64::NAN), 0.25), "a time that isn't a number");
        assert!(due(p.next_due(f64::INFINITY), 0.25));
        p.start(10.0, 0);
        assert!(due(p.next_due(9.0), 0.25), "backwards: the clock counts on from then");
        p.start(-f64::MAX, 0);
        assert!(due(p.next_due(f64::MAX), 0.25), "too far apart to count, as tick");
        assert_eq!(p.tick(f64::MAX), None, "which holds the frame and counts from then");
    }

    #[test]
    fn a_one_frame_span_is_never_due() {
        let mut p = playback((7, 8));
        p.start(0.0, 7);
        assert_eq!(p.next_due(0.5), None, "the frame never changes");
    }

    #[test]
    fn huge_jumps_stay_in_the_span() {
        let mut p = playback((10, 17));
        p.start(-1e300, 12);
        assert!(p.tick(1e300).is_none_or(|f| (10..17).contains(&f)), "an infinite elapsed time");
        let mut p = playback((10, 17));
        p.start(0.0, 12);
        assert!(p.tick(1e300).is_some_and(|f| (10..17).contains(&f)));
        assert!((10..17).contains(&p.frame()));
        let mut long = Playback::new(rate(1.0), FrameRange::new(0, u64::MAX).unwrap());
        long.start(0.0, u64::MAX - 1);
        assert_eq!(long.tick(3.0), Some(2), "MAX - 1 is the last frame: 0, 1, 2; without overflowing");
    }
}
