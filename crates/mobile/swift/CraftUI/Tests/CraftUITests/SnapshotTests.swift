#if os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import CraftUI

/// Renders panels as the iPad shows them and compares with the PNGs in `Snapshots/`. A missing
/// reference is recorded; `RECORD_SNAPSHOTS=1` re-records them all. Look at every image you record.
@MainActor @Suite struct SnapshotTests {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Snapshots")
    static let size = CGSize(width: 375, height: 720)

    struct Variant { let name: String; let style: UIUserInterfaceStyle; let type: DynamicTypeSize }
    static let variants = [
        Variant(name: "light", style: .light, type: .large),
        Variant(name: "dark", style: .dark, type: .large),
        Variant(name: "light-xxxl", style: .light, type: .xxxLarge),
    ]

    @Test(arguments: [Fixtures.layers, Fixtures.brush])
    func panel(_ panel: CraftPanel) throws {
        for v in Self.variants {
            let view = NavigationStack { CraftPanelView(panel: panel, send: { _ in }) }.dynamicTypeSize(v.type)
            try Self.check(view, style: v.style, "\(panel.id)-\(v.name)")
        }
    }

    /// `ImageRenderer` doesn't draw `Form` (a UIKit collection view), and a test bundle without a host app
    /// has no render server for `drawHierarchy`, so host the view and render its layers on the CPU.
    static func check(_ view: some View, style: UIUserInterfaceStyle, _ name: String) throws {
        let host = UIHostingController(rootView: view)
        // Without a window the hosting view never draws. There is no scene in a test bundle, hence `UIWindow()`.
        let window = UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        defer { window.isHidden = true }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let png = try #require(UIGraphicsImageRenderer(size: size, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }.pngData())

        let url = dir.appending(path: "\(name).png")
        if ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil || !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try png.write(to: url)
            return
        }
        let reference = try Data(contentsOf: url)
        #expect(png == reference, "\(name) changed: rerun with RECORD_SNAPSHOTS=1 if intended, and look at the image")
    }
}

enum Fixtures {
    /// The catalogue's examples as a Layers inspector, with a section and a node this kit doesn't know.
    static let layers = CraftPanel.previewLayers
    static let brush = CraftPanel.previewBrush
}
#endif
