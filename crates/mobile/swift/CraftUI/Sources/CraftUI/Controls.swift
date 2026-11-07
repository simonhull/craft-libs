import SwiftUI

/// A titled group the user can collapse. `collapsed` is only how it starts: after that it's the user's.
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

    var body: some View {
        let shown = hold.shown(app: value)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Button(Self.format(shown, unit)) {
                    typed = Self.format(shown, unit, withUnit: false)
                    typing = true
                }
                .monospacedDigit()
                .buttonStyle(.borderless)
                .accessibilityLabel(label)
                .accessibilityValue(Self.format(shown, unit))
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
            .accessibilityValue(Self.format(shown, unit))
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
        guard let n = Double(typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), n.isFinite else { return }
        let v = Self.snap(unit == .percent ? n / 100 : n, step: step, in: range)
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

    nonisolated static func format(_ v: Double, _ unit: CraftNode.Unit, withUnit: Bool = true) -> String {
        switch unit {
        case .percent: (v * 100).formatted(.number.precision(.fractionLength(0))) + (withUnit ? " %" : "")
        case .pixels: v.formatted(.number.precision(.fractionLength(0...1))) + (withUnit ? " px" : "")
        case .degrees: v.formatted(.number.precision(.fractionLength(0))) + (withUnit ? "°" : "")
        case .none: v.formatted(.number.precision(.fractionLength(0...2)))
        }
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
