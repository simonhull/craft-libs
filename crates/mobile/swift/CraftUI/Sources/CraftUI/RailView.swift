import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A tool's picture (craft-mobile's `ui::Icon`): an SF Symbol, and a letter for when the platform
/// has no such symbol.
public struct CraftToolIcon: Decodable, Equatable, Hashable, Sendable {
    public let symbol: String?
    public let letter: String?

    public init(symbol: String? = nil, letter: String? = nil) {
        (self.symbol, self.letter) = (symbol, letter)
    }

    /// What to draw.
    public enum Shown: Equatable, Sendable {
        case symbol(String)
        case letter(String)
    }

    /// The symbol when `exists` says the platform has it, else the letter, else the label's first
    /// letter (upper case).
    public func shown(label: String, exists: (String) -> Bool = CraftToolIcon.symbolExists) -> Shown {
        if let symbol, exists(symbol) { return .symbol(symbol) }
        if let letter, !letter.isEmpty { return .letter(letter) }
        return .letter(label.first.map { String($0).uppercased() } ?? "?")
    }

    /// Whether the platform has the SF Symbol `name`.
    public static func symbolExists(_ name: String) -> Bool {
        #if canImport(UIKit)
            UIImage(systemName: name) != nil
        #elseif canImport(AppKit)
            NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
            false
        #endif
    }
}

/// One tool of a palette (`ui::Tool`).
public struct CraftTool: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let icon: CraftToolIcon
    /// The portable form (`B`, `Shift+B`), shown beside the label.
    public let shortcut: String?

    public init(id: String, label: String, icon: CraftToolIcon, shortcut: String? = nil) {
        (self.id, self.label, self.icon, self.shortcut) = (id, label, icon, shortcut)
    }
}

/// One place on the rail (`ui::ToolSlot`): it shows the selected tool when it holds it, else its
/// first; the others are in its flyout.
public struct CraftToolSlot: Decodable, Equatable, Sendable {
    public let tools: [CraftTool]

    public init(tools: [CraftTool]) {
        self.tools = tools
    }

    private enum Key: String, CodingKey { case tools }

    /// A tool this kit can't read is left out of the slot.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        tools = try c.decode([Skippable<CraftTool>].self, forKey: .tools).compactMap(\.value)
    }

    /// The tool the slot shows while `selected` is the selected tool.
    public func shown(selected: String) -> CraftTool? {
        tools.first { $0.id == selected } ?? tools.first
    }
}

/// The app's tools (`ui::ToolPalette`), as the rail shows them.
public struct CraftToolPalette: Decodable, Equatable, Sendable {
    public let id: String
    public let slots: [CraftToolSlot]
    public let selected: String
    /// The app's Tool panel with the selected tool's options.
    public let options: String?
    /// The command that shows them when there's no panel.
    public let fallbackOptions: String?

    public init(id: String, slots: [CraftToolSlot], selected: String, options: String? = nil, fallbackOptions: String? = nil) {
        (self.id, self.slots, self.selected, self.options, self.fallbackOptions) = (id, slots, selected, options, fallbackOptions)
    }

    enum CodingKeys: String, CodingKey {
        case id, slots, selected, options
        case fallbackOptions = "fallback_options"
    }

    /// Lenient as the menus are: a slot or tool this kit can't read is left out (a slot left with
    /// no tools too); the rest of the rail still shows.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = try CraftToolPalette(
            id: c.decode(String.self, forKey: .id),
            slots: c.decode([Skippable<CraftToolSlot>].self, forKey: .slots).compactMap(\.value).filter { !$0.tools.isEmpty },
            selected: c.decode(String.self, forKey: .selected),
            options: (try? c.decodeIfPresent(String.self, forKey: .options)) ?? nil,
            fallbackOptions: (try? c.decodeIfPresent(String.self, forKey: .fallbackOptions)) ?? nil)
    }

    /// The same palette with another tool selected (as the app describes it after a pick).
    public func selecting(_ tool: String) -> CraftToolPalette {
        CraftToolPalette(id: id, slots: slots, selected: tool, options: options, fallbackOptions: fallbackOptions)
    }

    /// The palette without its options (in a panel, which has nowhere to open them).
    var withoutOptions: CraftToolPalette {
        CraftToolPalette(id: id, slots: slots, selected: selected)
    }

    /// How the selected tool's options open, if it has any.
    public var optionsRoute: CraftRailOptions? {
        if let options { return .panel(options) }
        return fallbackOptions.map(CraftRailOptions.command)
    }
}

/// How a tool's options open: the app's Tool panel as a popover from the rail, or an app command.
public enum CraftRailOptions: Equatable, Sendable {
    case panel(String)
    case command(String)
}

/// Taps on the rail's tools: a tap selects; a second tap on the same tool soon after (a double-tap)
/// opens its options. A tap on the tool already selected selects nothing new.
struct CraftRailTaps {
    /// How soon a second tap counts as a double-tap.
    static let interval: TimeInterval = 0.35

    enum Outcome: Equatable { case select, options, nothing }

    private var last: (tool: String, at: Date)?

    mutating func tap(_ tool: String, selected: String, at now: Date) -> Outcome {
        if let last, last.tool == tool, now.timeIntervalSince(last.at) <= Self.interval {
            self.last = nil
            return .options
        }
        last = (tool, now)
        return tool == selected ? .nothing : .select
    }
}

/// The rail: the app's tools in a column of Liquid Glass at the canvas's leading edge (or a row,
/// in a panel). Tap a tool to select it (a `choice` edit, `commit`); long-press a slot with more
/// tools (marked in its corner) for its flyout; double-tap a tool, or the options button, for the
/// selected tool's options: `optionsPanel` is set to its Tool panel, shown as a popover from the
/// button with `optionsContent`, or the fallback command is sent with `command`.
public struct CraftRailView<Options: View>: View {
    let palette: CraftToolPalette
    let panel: String
    let axis: Axis
    let send: @MainActor (CraftEdit) -> Void
    let command: @MainActor (String) -> Void
    @Binding var optionsPanel: String?
    let optionsContent: (String) -> Options
    @State private var taps = CraftRailTaps()
    /// A tool double-tapped before the app described it selected: its options open once it has,
    /// so they are that tool's and not the previous one's.
    @State private var pendingOptions: String?

    public init(
        palette: CraftToolPalette, panel: String, axis: Axis = .vertical, send: @escaping @MainActor (CraftEdit) -> Void,
        command: @escaping @MainActor (String) -> Void, optionsPanel: Binding<String?>, @ViewBuilder optionsContent: @escaping (String) -> Options
    ) {
        (self.palette, self.panel, self.axis, self.send, self.command) = (palette, panel, axis, send, command)
        _optionsPanel = optionsPanel
        self.optionsContent = optionsContent
    }

    public var body: some View {
        let stack = axis == .vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        stack {
            // The tools scroll when they don't fit (an iPad in landscape); the options button stays.
            ViewThatFits(in: axis == .vertical ? .vertical : .horizontal) {
                tools(stack)
                ScrollViewReader { proxy in
                    ScrollView(axis == .vertical ? .vertical : .horizontal) { tools(stack) }
                        .scrollIndicators(.hidden)
                        .scrollEdgeEffectStyle(.soft, for: axis == .vertical ? .vertical : .horizontal)
                        .onChange(of: palette.selected, initial: true) { _, _ in
                            // A tool picked by its shortcut scrolls into view.
                            guard let slot = Self.slotIndex(of: palette.selected, in: palette) else { return }
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(slot) }
                        }
                }
            }
            if let route = palette.optionsRoute {
                Divider().frame(width: axis == .vertical ? 32 : nil, height: axis == .horizontal ? 32 : nil)
                Button { open(route) } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tool Options")
                .popover(isPresented: Binding(get: { optionsPanel != nil }, set: { if !$0 { optionsPanel = nil } })) {
                    if let id = optionsPanel { CraftPopover { optionsContent(id) } }
                }
            }
        }
        .padding(6)
        .glassEffect(.regular, in: .capsule)
        .onChange(of: palette) { _, palette in
            guard let tool = pendingOptions, palette.selected == tool else { return }
            pendingOptions = nil
            palette.optionsRoute.map(open)
        }
    }

    private func tools(_ stack: AnyLayout) -> some View {
        stack {
            ForEach(Array(palette.slots.enumerated()), id: \.offset) { index, slot in
                if let tool = slot.shown(selected: palette.selected) {
                    CraftRailSlot(slot: slot, tool: tool, selected: palette.selected, tap: tap).id(index)
                }
            }
        }
    }

    /// Where `tool` sits on the rail: the index of the slot that holds it.
    nonisolated static func slotIndex(of tool: String, in palette: CraftToolPalette) -> Int? {
        palette.slots.firstIndex { $0.tools.contains { $0.id == tool } }
    }

    private func tap(_ tool: String) {
        pendingOptions = nil
        switch taps.tap(tool, selected: palette.selected, at: .now) {
        case .select: select(tool)
        case .options:
            switch Self.optionsNow(for: tool, in: palette) {
            case let .some(route): open(route)
            case .none where tool != palette.selected: pendingOptions = tool
            case .none: break
            }
        case .nothing: break
        }
    }

    /// The options a double-tap on `tool` opens now: only the selected tool's are in the palette, so
    /// a tool the app hasn't described as selected yet must wait for it.
    nonisolated static func optionsNow(for tool: String, in palette: CraftToolPalette) -> CraftRailOptions? {
        tool == palette.selected ? palette.optionsRoute : nil
    }

    private func select(_ tool: String) {
        send(CraftEdit(panel: panel, control: palette.id, phase: .commit, gesture: GestureID.next(), value: .choice(tool)))
    }

    private func open(_ route: CraftRailOptions) {
        switch route {
        case let .panel(id): optionsPanel = optionsPanel == id ? nil : id
        case let .command(id): command(id)
        }
    }
}

/// One slot: its shown tool, tinted while selected; a slot with more tools opens its flyout on a
/// long press, and says so with a mark in its corner.
struct CraftRailSlot: View {
    let slot: CraftToolSlot
    let tool: CraftTool
    let selected: String
    let tap: (String) -> Void
    /// The flyout as a list, for VoiceOver's More Tools action (a menu can't be opened in code).
    @State private var listingTools = false

    var body: some View {
        let isSelected = tool.id == selected
        Group {
            if slot.tools.count > 1 {
                Menu {
                    ForEach(slot.tools) { other in
                        Button { tap(other.id) } label: {
                            if other.id == selected {
                                Label(other.label, systemImage: "checkmark")
                            } else {
                                Text(other.label)
                            }
                            if let keys = Self.glyphs(other) { Text(keys) }
                        }
                    }
                } label: {
                    face(isSelected).overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 6))
                            .rotationEffect(.degrees(45))
                            .opacity(0.7)
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                    .modifier(SelectedForeground(selected: isSelected))
                } primaryAction: {
                    tap(tool.id)
                }
                .menuStyle(.button)
                .menuOrder(.fixed)
                .buttonStyle(.plain)
                .confirmationDialog("Tools", isPresented: $listingTools) {
                    ForEach(slot.tools) { other in
                        Button(other.label) { tap(other.id) }
                    }
                }
            } else {
                Button { tap(tool.id) } label: { face(isSelected).modifier(SelectedForeground(selected: isSelected)) }
                    .buttonStyle(.plain)
            }
        }
        // One element per slot, a button named for its tool: a menu with a primary action is a
        // button inside a button, and the inner one would be an unnamed element of its own.
        .accessibilityRepresentation {
            Button(tool.label) { tap(tool.id) }
        }
        .accessibilityHint(Self.hint(tool, more: slot.tools.count > 1))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            if slot.tools.count > 1 {
                Button("More tools") { listingTools = true }
            }
        }
        .help(Self.glyphs(tool).map { "\(tool.label) (\($0))" } ?? tool.label)
    }

    /// The tool's shortcut as the kit shows every shortcut (`⇧B`).
    nonisolated static func glyphs(_ tool: CraftTool) -> String? {
        tool.shortcut.flatMap(CraftShortcut.init).map(\.glyphs)
    }

    /// What VoiceOver says after the label: the shortcut, and that the slot has more tools.
    nonisolated static func hint(_ tool: CraftTool, more: Bool) -> String {
        [glyphs(tool).map { "Shortcut \($0)." }, more ? "More tools in the actions." : nil].compactMap { $0 }.joined(separator: " ")
    }

    private func face(_ isSelected: Bool) -> some View {
        // Unselected, the glass picks the colour that reads over what's behind it.
        CraftToolFace(icon: tool.icon.shown(label: tool.label))
            .frame(width: 44, height: 44)
            .background(isSelected ? Color.accentColor : Color.clear, in: .circle)
            .contentShape(.circle)
    }
}

/// White on the accent while selected; otherwise the inherited style.
private struct SelectedForeground: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        if selected { content.foregroundStyle(.white) } else { content }
    }
}

/// A tool's symbol, or its letter in the same place.
struct CraftToolFace: View {
    let icon: CraftToolIcon.Shown

    var body: some View {
        switch icon {
        case let .symbol(name): Image(systemName: name).font(.title3)
        case let .letter(letter): Text(letter).font(.title3.weight(.semibold).monospaced())
        }
    }
}

#if DEBUG
extension CraftToolPalette {
    /// Move; Brush with Pencil in its flyout (Brush selected); Smudge as a letter; options in the
    /// Brush panel. As the catalogue's example.
    static let preview = CraftToolPalette(
        id: "palette",
        slots: [
            CraftToolSlot(tools: [CraftTool(id: "move", label: "Move", icon: CraftToolIcon(symbol: "arrow.up.and.down.and.arrow.left.and.right", letter: "V"), shortcut: "V")]),
            CraftToolSlot(tools: [
                CraftTool(id: "brush", label: "Brush", icon: CraftToolIcon(symbol: "paintbrush.pointed", letter: "B"), shortcut: "B"),
                CraftTool(id: "pencil", label: "Pencil", icon: CraftToolIcon(symbol: "pencil", letter: "N"), shortcut: "N"),
            ]),
            CraftToolSlot(tools: [CraftTool(id: "smudge", label: "Smudge", icon: CraftToolIcon(letter: "S"))]),
        ],
        selected: "brush", options: "brush", fallbackOptions: "window.toggle.optionsBar")
}

#Preview("Rail") {
    CraftRailView(palette: .preview, panel: "tools", send: { print($0) }, command: { print($0) }, optionsPanel: .constant(nil)) { _ in EmptyView() }
        .padding()
}
#endif
