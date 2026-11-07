import SwiftUI

/// A tool panel's popover content: as tall as what it holds, up to what fits, and a popover even
/// where the window is compact (Slide Over, a narrow split), as a tool's options should be.
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
        }
        .frame(idealWidth: 340, idealHeight: min(max(height, 120), 640))
        .presentationCompactAdaptation(.popover)
    }
}
