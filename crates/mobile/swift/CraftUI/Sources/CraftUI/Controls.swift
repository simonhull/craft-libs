import SwiftUI

/// A titled group the user can collapse. `collapsed` is only how it starts: after the section first
/// appears, collapsing is the user's, and it resets to `collapsed` when the panel's views are built
/// again (the panel closed and reopened).
struct CraftSectionView<Content: View>: View {
    let title: String
    @State private var expanded: Bool
    let content: Content

    init(title: String, collapsed: Bool, @ViewBuilder content: () -> Content) {
        self.title = title
        _expanded = State(initialValue: !collapsed)
        self.content = content()
    }

    // `Section(isExpanded:)` draws no disclosure control in a grouped form on iOS, so the header is the button.
    var body: some View {
        Section {
            if expanded { content }
        } header: {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isHeader)
        }
    }
}

/// A value in a range: a slider, with the value beside it; tap the value to type one.
struct CraftNumberView: View {
    let id: String
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let unit: CraftNode.Unit
    let panel: String
    let send: @MainActor (CraftEdit) -> Void
    /// This control's own drag: it lives and dies with the view.
    @State private var hold = GestureHold()
    @State private var typing = false
    @State private var typed = ""
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shown = hold.shown(app: value)
        let formatted = Self.format(shown, unit, locale: locale)
        // At accessibility sizes the label and value don't fit side by side: stack them.
        let header = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
        VStack(alignment: .leading, spacing: 4) {
            header {
                // The button and the slider both say the label: VoiceOver needn't read it a third time.
                Text(label).accessibilityHidden(true)
                Spacer(minLength: 0)
                Button {
                    typed = Self.format(shown, unit, withUnit: false, locale: locale)
                    typing = true
                } label: {
                    Text(formatted).frame(minHeight: 44).contentShape(Rectangle())
                }
                .monospacedDigit()
                .buttonStyle(.borderless)
                .accessibilityLabel(label)
                .accessibilityValue(formatted)
                .accessibilityHint("Type a value")
            }
            // The setter runs only for the user's own input, never when the app's value changes.
            Slider(value: Binding(get: { shown }, set: slide), in: range) { editing in
                if editing {
                    emit(hold.begin(from: value))
                } else if let step = hold.commit() {
                    emit(step)
                }
            }
            .accessibilityLabel(label)
            .accessibilityValue(formatted)
        }
        // Re-described without this control, or the panel closed, mid-drag: put the value back.
        .onDisappear {
            if let step = hold.cancel() { emit(step) }
        }
        .alert(label, isPresented: $typing) {
            TextField(label, text: $typed)
            #if os(iOS)
                .keyboardType(.decimalPad)
            #endif
            Button("Cancel", role: .cancel) {}
            Button("Set") { typedValue() }
        }
    }

    private func slide(to raw: Double) {
        let new = Self.snap(raw, step: step, in: range)
        if hold.isDragging {
            if new != hold.shown(app: value), let step = hold.change(to: new) { emit(step) }
        } else if new != value {
            // Not a drag (VoiceOver adjust, keyboard): one complete edit.
            send(CraftEdit(panel: panel, control: id, phase: .commit, gesture: GestureID.next(), value: .number(new)))
        }
    }

    private func typedValue() {
        guard let n = Self.parse(typed, unit: unit, locale: locale) else { return }
        let v = Self.snap(n, step: step, in: range)
        send(CraftEdit(panel: panel, control: id, phase: .commit, gesture: GestureID.next(), value: .number(v)))
    }

    private func emit(_ s: GestureHold.Step) {
        send(CraftEdit(panel: panel, control: id, phase: s.phase, gesture: s.gesture, value: .number(s.value)))
    }

    /// `v` snapped to a multiple of `step` (as the app's `Number::step` means it) and kept in `range`.
    nonisolated static func snap(_ v: Double, step: Double?, in range: ClosedRange<Double>) -> Double {
        let snapped = step.flatMap { $0.isFinite && $0 > 0 ? $0 * (v / $0).rounded() : nil } ?? v
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    /// The value as shown, in `locale`, never grouped (so it can fill the typing field and parse back).
    nonisolated static func format(_ v: Double, _ unit: CraftNode.Unit, withUnit: Bool = true, locale: Locale = .current) -> String {
        func number(_ x: Double, _ digits: ClosedRange<Int>) -> String {
            x.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(locale))
        }
        return switch unit {
        case .percent: number(v * 100, 0...0) + (withUnit ? " %" : "")
        case .pixels: number(v, 0...1) + (withUnit ? " px" : "")
        case .degrees: number(v, 0...0) + (withUnit ? "°" : "")
        case .none: number(v, 0...2)
        }
    }

    /// A typed value: read in `locale` (then as plain `1234.5`), ignoring a typed unit; a percentage
    /// becomes 0...1. `nil` if it isn't a finite number.
    nonisolated static func parse(_ text: String, unit: CraftNode.Unit, locale: Locale = .current) -> Double? {
        let bare = ["%", "px", "°"]
            .reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
            .trimmingCharacters(in: .whitespaces)
        guard !bare.isEmpty,
              let n = (try? Double(bare, format: .number.locale(locale))) ?? Double(bare),
              n.isFinite else { return nil }
        return unit == .percent ? n / 100 : n
    }
}

/// On or off: a switch.
struct CraftToggleView: View {
    let id: String
    let label: String
    let value: Bool
    let panel: String
    let send: @MainActor (CraftEdit) -> Void

    var body: some View {
        // The setter runs only when the user flips the switch.
        Toggle(label, isOn: Binding(get: { value }, set: { new in
            guard new != value else { return }
            send(CraftEdit(panel: panel, control: id, phase: .commit, gesture: GestureID.next(), value: .toggle(new)))
        }))
    }
}

/// One of several options: segmented for up to 4, a menu for more.
struct CraftChoiceView: View {
    let id: String
    let label: String
    let value: String
    let options: [CraftChoiceOption]
    let panel: String
    let send: @MainActor (CraftEdit) -> Void

    var body: some View {
        // The setter runs only when the user picks; picking the current option sends nothing.
        let binding = Binding(get: { value }, set: { (new: String) in
            guard new != value else { return }
            send(CraftEdit(panel: panel, control: id, phase: .commit, gesture: GestureID.next(), value: .choice(new)))
        })
        let picker = Picker(label, selection: binding) {
            ForEach(options) { Text($0.label).tag($0.id) }
        }
        if options.count <= 4 {
            // A segmented picker draws no label of its own: show it above (VoiceOver still reads the picker's).
            VStack(alignment: .leading, spacing: 6) {
                Text(label).accessibilityHidden(true)
                picker.pickerStyle(.segmented).labelsHidden()
            }
        } else {
            picker.pickerStyle(.menu)
        }
    }
}
