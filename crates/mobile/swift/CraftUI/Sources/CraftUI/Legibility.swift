import SwiftUI

extension View {
    /// Liquid Glass for chrome that floats over the canvas (the rail, the transport bar, the status,
    /// the shell's toolbar), legible over whatever the canvas shows.
    ///
    /// Plain glass takes on what's behind it: in dark appearance over a white canvas it turns light
    /// grey, and white text and symbols on it fall to about 2:1. A wash of the appearance's
    /// background under the glass (black in dark, white in light) keeps text above 4.5:1 and
    /// symbols above 3:1 over a white, a black or a busy canvas, and the glass still shows its
    /// edges and what's behind it.
    func craftGlass(_ glass: Glass = .regular, in shape: some Shape) -> some View {
        modifier(CraftGlass(glass: glass, shape: shape))
    }
}

struct CraftGlass<S: Shape>: ViewModifier {
    let glass: Glass
    let shape: S
    @Environment(\.colorScheme) private var scheme

    /// The opacity of the wash under floating glass.
    static var wash: Double { 0.5 }

    func body(content: Content) -> some View {
        // A colour, not the `.background` style, which glass resolves to its own (clear) one.
        content
            .background((scheme == .dark ? Color.black : Color.white).opacity(Self.wash), in: shape)
            .glassEffect(glass, in: shape)
    }
}

extension ShapeStyle where Self == Color {
    /// Secondary text that still meets 4.5:1: the label's colour, a little faded. The system's
    /// secondary label is about 3.5:1 on white, and less on a tinted (selected) row.
    static var craftSecondaryText: Color { Color.primary.opacity(0.72) }
}
