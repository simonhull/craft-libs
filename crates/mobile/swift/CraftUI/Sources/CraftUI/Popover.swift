import SwiftUI

/// A tool panel's popover content: as tall as what it holds, up to what fits, and a popover even
/// where the window is compact (Slide Over, a narrow split), as a tool's options should be. Its
/// navigation bar has the system's Close button (Escape too), as an inspector panel's has
/// (``SwiftUICore/View/craftPanelCloseButton(_:)``).
///
/// ```swift
/// .popover(isPresented: $showsBrush) {
///     CraftPopover { CraftPanelView(panel: brush, send: send) }
/// }
/// ```
public struct CraftPopover<Content: View>: View {
    let content: Content
    /// The content's height as last measured; a guess until the first layout.
    @State private var height: CGFloat = 360
    @Environment(\.dismiss) private var dismiss

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        NavigationStack {
            content
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .scrollBounceBehavior(.basedOnSize)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                } action: { _, new in
                    height = new
                }
                .craftPanelCloseButton { dismiss() }
        }
        .frame(idealWidth: 340, idealHeight: min(max(height, 120), 640))
        .presentationCompactAdaptation(.popover)
    }
}

extension View {
    /// The system's Close button (an ✕ in glass) at the trailing end of a panel's navigation bar,
    /// as an inspector panel or a tool popover shows it: neither presentation draws one of its own
    /// in a regular-width window. Escape closes it too. Put it inside the panel's `NavigationStack`.
    ///
    /// ```swift
    /// .inspector(isPresented: $shows) {
    ///     NavigationStack {
    ///         CraftPanelView(panel: layers, send: send).craftPanelCloseButton { shows = false }
    ///     }
    /// }
    /// ```
    public func craftPanelCloseButton(_ close: @escaping () -> Void) -> some View {
        toolbar {
            // Not `.confirmationAction`, which draws it prominent, in the accent, as a Done button.
            ToolbarItem(placement: Self.closePlacement) {
                Button(role: .close, action: close)
                    .keyboardShortcut(.cancelAction)
                    .help("Close")
            }
        }
    }

    private static var closePlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarTrailing
        #else
            .automatic
        #endif
    }
}
