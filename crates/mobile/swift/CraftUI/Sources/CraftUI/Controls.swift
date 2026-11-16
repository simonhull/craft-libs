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
                // A heading in the label's colour, not the grouped form's faint caption: it is
                // also a control, and on a popover's glass a secondary header is hard to read.
                // Colours, not `.primary`: in a header that level is already the faint one.
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .textCase(nil)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isHeader)
        }
    }
}

/// A value in a range: a slider, with the value beside it; tap the value to type one. The slider
/// moves through positions 0...1, spread over the range by `scale`; values (shown, typed, sent) are
/// in the number's own units.
struct CraftNumberView: View {
    let id: String
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let unit: CraftNode.Unit
    var scale: CraftNode.Scale = .linear
    let panel: String
    let send: @MainActor (CraftEdit) -> Void
    /// This control's own drag: it lives and dies with the view.
    @State private var hold = GestureHold()
    @State private var typing = false
    @State private var typed = ""
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.craftDescriptions) private var descriptions
    @Environment(\.isEnabled) private var isEnabled

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
                    Text(formatted)
                }
                .monospacedDigit()
                // The system's bordered capsule, in the label's colour: it reads as a field to tap,
                // and at full contrast on a popover's glass, where the accent didn't.
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(isEnabled ? .primary : .secondary)
                .frame(minHeight: 44)
                .contentShape(.rect)
                .accessibilityLabel(label)
                .accessibilityValue(formatted)
                .accessibilityHint("Type a value")
            }
            // A few steps are marked on the track (the system's ticks), each felt as the drag
            // crosses it; many would be a grey bar and a buzz.
            let ticks = Self.tickPositions(in: range, step: step, scale: scale)
            // The setter runs only for the user's own input, never when the app's value changes.
            Slider(
                value: Binding(
                    get: { Self.position(of: shown, in: range, scale: scale) },
                    set: { slide(to: Self.value(atPosition: $0, in: range, scale: scale)) }),
                in: 0...1,
                // Named below, once: a label here and the modifier's would be read together.
                label: { EmptyView() },
                ticks: { SliderTickContentForEach(ticks, id: \.self) { SliderTick($0) } },
                onEditingChanged: { editing in
                    if editing {
                        emit(hold.begin(from: value))
                    } else if let step = hold.commit() {
                        emit(step)
                    }
                }
            )
            .accessibilityLabel(label)
            .accessibilityValue(formatted)
            .sensoryFeedback(.selection, trigger: shown) { _, _ in hold.isDragging && !ticks.isEmpty }
        }
        // A new description, or a new value (a host that doesn't count descriptions): an ended
        // drag's value gives way to the app's.
        .onChange(of: descriptions) { hold.described() }
        .onChange(of: value) { hold.described() }
        // Re-described without this control, or the panel closed, mid-drag: put the value back.
        .onDisappear {
            if let step = hold.cancel() { emit(step) }
        }
        .alert(label, isPresented: $typing) {
            TextField(label, text: $typed)
            #if os(iOS)
                // The decimal pad has no minus key.
                .keyboardType(range.lowerBound < 0 ? .numbersAndPunctuation : .decimalPad)
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

    /// Where `v` sits on the slider, 0...1. On a log scale `v = min·(max/min)^t`; a range a log
    /// scale can't spread (`min <= 0`) is linear; an empty range is 0.
    nonisolated static func position(of v: Double, in range: ClosedRange<Double>, scale: CraftNode.Scale) -> Double {
        let (lo, hi) = (range.lowerBound, range.upperBound)
        guard hi > lo else { return 0 }
        let t = isLog(scale, range) ? log(v / lo) / log(hi / lo) : (v - lo) / (hi - lo)
        return t.isFinite ? min(max(t, 0), 1) : 0
    }

    /// The value at slider position `t` (kept in 0...1), before any step snaps it: the inverse of
    /// ``position(of:in:scale:)``.
    nonisolated static func value(atPosition t: Double, in range: ClosedRange<Double>, scale: CraftNode.Scale) -> Double {
        let (lo, hi) = (range.lowerBound, range.upperBound)
        let t = min(max(t.isFinite ? t : 0, 0), 1)
        let v = isLog(scale, range) ? lo * pow(hi / lo, t) : lo + t * (hi - lo)
        return min(max(v, lo), hi)
    }

    private nonisolated static func isLog(_ scale: CraftNode.Scale, _ range: ClosedRange<Double>) -> Bool {
        scale == .log && range.lowerBound > 0
    }

    /// The most steps a number's track marks.
    nonisolated static let maxTicks = 20

    /// Where a stepped number's steps sit on the slider (0...1), for its tick marks: none when
    /// it has no step, more than ``maxTicks`` of them, or a log scale (whose steps bunch up).
    nonisolated static func tickPositions(in range: ClosedRange<Double>, step: Double?, scale: CraftNode.Scale) -> [Double] {
        let (lo, hi) = (range.lowerBound, range.upperBound)
        guard let step, step.isFinite, step > 0, hi > lo, !isLog(scale, range) else { return [] }
        let first = (lo / step).rounded(.up)
        let last = (hi / step).rounded(.down)
        guard last >= first, last - first < Double(maxTicks) else { return [] }
        return stride(from: first, through: last, by: 1).map { (($0 * step) - lo) / (hi - lo) }
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

    /// A typed value: read strictly in `locale` (grouping only where the locale puts it), else as a
    /// plain `1234.5`, ignoring a typed unit; a percentage becomes 0...1. `nil` for anything else
    /// ("50abc", or "0,5" where a comma only groups), rather than a guess the user didn't mean.
    nonisolated static func parse(_ text: String, unit: CraftNode.Unit, locale: Locale = .current) -> Double? {
        let bare = ["%", "px", "°"]
            .reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
            .trimmingCharacters(in: .whitespaces)
        guard !bare.isEmpty, let n = strict(bare, locale: locale) ?? Double(bare), n.isFinite else { return nil }
        return unit == .percent ? n / 100 : n
    }

    /// `text` as a whole number in `locale`, its grouping in the right places, or `nil`.
    private nonisolated static func strict(_ text: String, locale: Locale) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        return formatter.number(from: text)?.doubleValue
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
            // The chosen option in the label's colour: the menu style's default grey falls under
            // 4.5:1 on glass.
            picker.pickerStyle(.menu).tint(.primary)
        }
    }
}
