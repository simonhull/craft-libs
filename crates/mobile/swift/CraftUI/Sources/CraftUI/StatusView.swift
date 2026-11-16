import SwiftUI

/// What the app is telling the user (wire kind 16, craft-mobile's `ui::Status`). A part this kit
/// can't read is left out; a tone it doesn't know is `info`.
public struct CraftStatus: Decodable, Equatable, Sendable {
    public struct Message: Decodable, Equatable, Sendable {
        public enum Tone: String, Decodable, Sendable {
            case info, error

            public init(from decoder: any Decoder) throws {
                self = try Tone(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .info
            }
        }

        public let text: String
        public let tone: Tone
        /// Which message this is (`Status::message_id`): a new id shows the same text again, and the
        /// same id with new text (a countdown) updates the toast on screen. 0 when the app doesn't say.
        public let id: UInt64

        public init(text: String, tone: Tone = .info, id: UInt64 = 0) {
            (self.text, self.tone, self.id) = (text, tone, id)
        }

        private enum Key: String, CodingKey { case text, tone, id }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            self = try Message(
                text: c.decode(String.self, forKey: .text), tone: c.decode(Tone.self, forKey: .tone),
                id: c.decodeIfPresent(UInt64.self, forKey: .id) ?? 0)
        }
    }

    public struct Progress: Decodable, Equatable, Sendable {
        public let label: String
        /// 0...1; `nil` while unknown.
        public let fraction: Double?
        /// The command that stops the job; `nil` when it can't be stopped.
        public let cancel: String?

        public init(label: String, fraction: Double? = nil, cancel: String? = nil) {
            (self.label, self.fraction, self.cancel) = (label, fraction, cancel)
        }
    }

    public let message: Message?
    public let progress: Progress?

    public init(message: Message? = nil, progress: Progress? = nil) {
        (self.message, self.progress) = (message, progress)
    }

    private enum Key: String, CodingKey { case message, progress }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        message = (try? c.decodeIfPresent(Message.self, forKey: .message)) ?? nil
        progress = (try? c.decodeIfPresent(Progress.self, forKey: .progress)) ?? nil
    }
}

/// The app's status over the canvas: a new message as a toast at the top that goes away by itself
/// (an error, tinted red, stays longer; a tap dismisses it), and a job's progress as a capsule with
/// Cancel at the bottom while it lasts. Cancel sends the job's command with `command`.
///
/// A message with an id keeps its toast while the id stands: new text (a countdown) changes it in
/// place, without animating it in again, and starts its time again. A new id is a new toast. A
/// message without an id is its text and tone.
public struct CraftStatusView: View {
    let status: CraftStatus
    let command: @MainActor (String) -> Void
    /// How far above the bottom edge the progress sits: clear of the shell's toolbar (and its
    /// transport bar, when it shows one).
    let bottomInset: CGFloat
    /// The message on screen; the same message arriving again doesn't show again.
    @State private var toast: CraftStatus.Message?
    @State private var dismissed: Identity?

    /// Which toast a message is (``identity(_:)``).
    enum Identity: Hashable {
        /// The app's id for it.
        case numbered(UInt64)
        /// No id: its text and tone.
        case unnumbered(String, CraftStatus.Message.Tone)
    }

    public init(status: CraftStatus, bottomInset: CGFloat = 90, command: @escaping @MainActor (String) -> Void) {
        (self.status, self.bottomInset, self.command) = (status, bottomInset, command)
    }

    public var body: some View {
        VStack {
            if let toast {
                CraftStatusToast(message: toast)
                    // A new message is a new view, animated in; new text for the same one isn't.
                    .id(Self.identity(toast))
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    .onTapGesture { dismiss() }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(Self.duration(toast.tone)))
                        if !Task.isCancelled { dismiss() }
                    }
            }
            Spacer(minLength: 0)
            if let progress = status.progress {
                CraftProgressCapsule(progress: progress, command: command)
                    // Above the shell's toolbar.
                    .padding(.bottom, bottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: toast.map(Self.identity))
        .animation(.easeOut(duration: 0.25), value: status.progress)
        .onChange(of: status.message, initial: true) { _, message in
            // Cleared, the same message may come back as news.
            if message == nil { dismissed = nil }
            let old = toast.map(Self.identity)
            toast = Self.shown(message, dismissed: dismissed)
            // A toast isn't focused, so VoiceOver says a new one; new text for the same one (a
            // countdown) it doesn't, as it isn't news.
            if let toast, let announcement = Self.announcement(toast, replacing: old) {
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
    }

    private func dismiss() {
        dismissed = toast.map(Self.identity)
        toast = nil
    }

    /// How long a toast stays: an error long enough to read twice.
    nonisolated static func duration(_ tone: CraftStatus.Message.Tone) -> Double {
        tone == .error ? 6 : 3
    }

    /// Which toast `message` is: its id when it has one, so new text updates the toast on screen;
    /// otherwise its text and tone.
    nonisolated static func identity(_ message: CraftStatus.Message) -> Identity {
        message.id == 0 ? .unnumbered(message.text, message.tone) : .numbered(message.id)
    }

    /// What VoiceOver says when `message` shows where the toast `old` was: its text (an error
    /// says so) when it is a new toast; nothing when it is the same one with new text.
    nonisolated static func announcement(_ message: CraftStatus.Message, replacing old: Identity?) -> String? {
        guard identity(message) != old else { return nil }
        return message.tone == .error ? "Error: \(message.text)" : message.text
    }

    /// The toast for the status's `message`: none once that message was dismissed (it timed out or
    /// was tapped away), whatever its text says since, so only a new one shows.
    nonisolated static func shown(_ message: CraftStatus.Message?, dismissed: Identity?) -> CraftStatus.Message? {
        guard let message, identity(message) != dismissed else { return nil }
        return message
    }
}

/// One message as a glass capsule; an error is tinted red and says so to VoiceOver.
struct CraftStatusToast: View {
    let message: CraftStatus.Message

    var body: some View {
        let error = message.tone == .error
        Label(message.text, systemImage: error ? "exclamationmark.triangle.fill" : "info.circle.fill")
            .font(.callout.weight(.medium))
            .lineLimit(3)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // A red wash over plain glass: a tinted glass (`.regular.tint`) draws as an opaque white
            // sheet when rendered off screen, which the snapshot tests do.
            .background(error ? Color.red.opacity(0.45) : Color.clear, in: .capsule)
            .craftGlass(in: .capsule)
            .accessibilityLabel(error ? "Error: \(message.text)" : message.text)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// A job in progress: its label, a bar (spinning while its length is unknown), and Cancel when it
/// can be stopped.
struct CraftProgressCapsule: View {
    let progress: CraftStatus.Progress
    let command: @MainActor (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let fraction = progress.fraction {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.label).font(.callout.weight(.medium))
                    ProgressView(value: min(max(fraction, 0), 1))
                        .frame(width: 180)
                }
            } else {
                ProgressView()
                Text(progress.label).font(.callout.weight(.medium))
            }
            if let cancel = progress.cancel {
                // In the label's colour: the accent on the glass's wash falls under 4.5:1 in light.
                Button("Cancel", role: .cancel) { command(cancel) }
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(.primary)
                    .frame(minHeight: 44)
                    .accessibilityHint("Stops \(progress.label)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .craftGlass(in: .capsule)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
extension CraftStatus {
    /// The catalogue's example: an error and an export with Cancel.
    static let preview = CraftStatus(
        message: Message(text: "Couldn't open b.psd: not a Photoshop file", tone: .error, id: 7),
        progress: Progress(label: "Exporting a.png", fraction: 0.4, cancel: "job.cancel"))
}

#Preview("Status") {
    CraftStatusView(status: .preview) { print($0) }
}
#endif
