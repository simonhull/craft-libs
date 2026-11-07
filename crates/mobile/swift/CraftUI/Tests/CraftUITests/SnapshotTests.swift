#if os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import CraftUI

/// Renders panels as the iPad shows them and compares them with the PNGs in `Snapshots/`, which are
/// named for the iOS major version they were drawn on (another runtime draws differently, so it
/// records its own). A missing reference is recorded and the test fails until it's committed;
/// `TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test …` re-records them all (and fails, likewise).
/// Look at every image you record.
@MainActor @Suite struct SnapshotTests {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Snapshots")
    static let runtime = "ios\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"

    struct Variant: Sendable {
        let name: String
        let style: UIUserInterfaceStyle
        let type: DynamicTypeSize
        let height: CGFloat
    }

    static let variants = [
        Variant(name: "light", style: .light, type: .large, height: 720),
        Variant(name: "dark", style: .dark, type: .large, height: 720),
        Variant(name: "light-xxxl", style: .light, type: .xxxLarge, height: 820),
        Variant(name: "light-ax3", style: .light, type: .accessibility3, height: 1100),
    ]

    @available(iOS, deprecated: 26, message: "Renders in a scene-less window")
    @Test(arguments: [Fixtures.layers, Fixtures.brush])
    func panel(_ panel: CraftPanel) throws {
        for v in Self.variants {
            let view = NavigationStack { CraftPanelView(panel: panel, send: { _ in }) }.dynamicTypeSize(v.type)
            let png = try Self.render(view, style: v.style, size: CGSize(width: 375, height: v.height))
            try Self.check(png, "\(panel.id)-\(v.name)-\(Self.runtime)")
        }
    }

    /// The rail as the shell shows it, over a mid-grey canvas: Brush selected, its slot marked for
    /// the flyout, Smudge as a letter, and the options button.
    @available(iOS, deprecated: 26, message: "Renders in a scene-less window")
    @Test func rail() throws {
        for v in Self.variants.prefix(2) {
            let view = CraftRailView(palette: .preview, panel: "tools", send: { _ in }, command: { _ in }, optionsPanel: .constant(nil)) { _ in EmptyView() }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color(white: 0.5))
            let png = try Self.render(view, style: v.style, size: CGSize(width: 100, height: 320))
            try Self.check(png, "rail-\(v.name)-\(Self.runtime)")
        }
    }

    /// A message, an error, and a job with Cancel, as the status shows them over the canvas.
    @available(iOS, deprecated: 26, message: "Renders in a scene-less window")
    @Test func status() throws {
        let preview = CraftStatus.preview
        for v in Self.variants.prefix(2) {
            let view = VStack(spacing: 16) {
                CraftStatusToast(message: .init(text: "Saved a.psd"))
                if let error = preview.message { CraftStatusToast(message: error) }
                if let progress = preview.progress { CraftProgressCapsule(progress: progress, command: { _ in }) }
                CraftProgressCapsule(progress: .init(label: "Opening b.psd"), command: { _ in })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.5))
            let png = try Self.render(view, style: v.style, size: CGSize(width: 420, height: 560))
            try Self.check(png, "status-\(v.name)-\(Self.runtime)")
        }
    }

    /// The comparison must catch a one-value change: the Layers panel with Opacity at 50 % instead
    /// of 80 %, or with one row renamed (text alone, a few hundred pixels), is not its reference.
    @available(iOS, deprecated: 26, message: "Renders in a scene-less window")
    @Test func aChangedValueIsReported() throws {
        let opacity = Fixtures.layers.nodes.map { node -> CraftNode in
            guard case let .number(id, label, _, min, max, step, unit, enabled, scale) = node, id == "opacity" else { return node }
            return .number(id: id, label: label, value: 0.5, min: min, max: max, step: step, unit: unit, enabled: enabled, scale: scale)
        }
        let renamed = Fixtures.layers.nodes.map { node -> CraftNode in
            guard case let .itemList(id, rows, reorderable) = node else { return node }
            let renamedRows = rows.map { $0.id == 2 ? CraftRow(id: 2, title: "Sea", subtitle: $0.subtitle, depth: $0.depth, visible: $0.visible, selected: $0.selected) : $0 }
            return .itemList(id: id, rows: renamedRows, reorderable: reorderable)
        }
        let v = try #require(Self.variants.first)
        let url = Self.dir.appending(path: "layers-\(v.name)-\(Self.runtime).png")
        let reference = try #require(Bitmap(png: try Data(contentsOf: url)))
        for nodes in [opacity, renamed] {
            let changed = CraftPanel(id: "layers", title: "Layers", role: .inspector, nodes: nodes)
            let view = NavigationStack { CraftPanelView(panel: changed, send: { _ in }) }.dynamicTypeSize(v.type)
            let actual = try #require(Bitmap(png: try Self.render(view, style: v.style, size: CGSize(width: 375, height: v.height))))
            let differing = actual.compare(with: reference, tolerance: Self.channelTolerance).differing
            print("CHANGED \(differing) px")
            #expect(differing > Self.pixelTolerance, "a changed value must not pass as noise (\(differing) px)")
        }
    }

    // MARK: Rendering

    /// `ImageRenderer` doesn't draw `Form` (a UIKit collection view), and a test bundle without a host
    /// app has no render server for `drawHierarchy`, so host the view in a window and draw its layers.
    /// Renders until two frames in a row match, so the image doesn't depend on a guessed delay.
    @available(iOS, deprecated: 26, message: "Hosts the view in a scene-less window")
    static func render(_ view: some View, style: UIUserInterfaceStyle, size: CGSize) throws -> Data {
        let window = sceneLessWindow()
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        defer { window.isHidden = true }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var last: Data?
        for _ in 0..<60 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            window.layoutIfNeeded()
            let png = try #require(renderer.image { window.layer.render(in: $0.cgContext) }.pngData())
            if png == last { return png }
            last = png
        }
        Issue.record("the view never settled")
        return try #require(last)
    }

    @available(iOS, deprecated: 26, message: "A test bundle has no window scene, so the window can't be given one")
    private static func sceneLessWindow() -> UIWindow {
        UIWindow()
    }

    // MARK: Comparing

    /// At most this many pixels may differ, each by more than `channelTolerance`. Two renders on one
    /// runtime match exactly (0 px, measured); this allows a little antialiasing wobble between
    /// machines, far below what one changed value moves (see `aChangedValueIsReported`).
    static let pixelTolerance = 50
    static let channelTolerance: UInt8 = 2

    static func check(_ png: Data, _ name: String) throws {
        let url = dir.appending(path: "\(name).png")
        let record = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil
        if record || !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try png.write(to: url)
            Issue.record("recorded \(name).png: look at it, commit it, and run again")
            return
        }
        let reference = try #require(Bitmap(png: try Data(contentsOf: url)), "\(name).png doesn't decode")
        let actual = try #require(Bitmap(png: png))
        guard actual.width == reference.width, actual.height == reference.height else {
            Attachment.record(png, named: "\(name)-actual.png")
            Issue.record("\(name) is \(actual.width)×\(actual.height), the reference \(reference.width)×\(reference.height)")
            return
        }
        let (differing, diff) = actual.compare(with: reference, tolerance: channelTolerance)
        if differing > pixelTolerance {
            let share = Double(differing) / Double(actual.width * actual.height)
            Attachment.record(png, named: "\(name)-actual.png")
            if let diff { Attachment.record(diff, named: "\(name)-diff.png") }
            Issue.record("\(name) changed (\(differing) px, \((share * 100).formatted(.number.precision(.fractionLength(3)))) %): rerun with TEST_RUNNER_RECORD_SNAPSHOTS=1 if intended, and look at the image")
        }
    }
}

/// An image as 8-bit RGBA, for comparing.
struct Bitmap {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    init?(png: Data) {
        guard let image = UIImage(data: png)?.cgImage else { return nil }
        let (width, height) = (image.width, image.height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        (self.width, self.height, self.rgba) = (width, height, rgba)
    }

    /// How many pixels differ by more than `tolerance` in any channel, and a PNG marking them in red
    /// over a faded copy of `reference`.
    func compare(with reference: Bitmap, tolerance: UInt8) -> (differing: Int, diff: Data?) {
        var differing = 0
        var marked = reference.rgba
        for start in stride(from: 0, to: rgba.count, by: 4) {
            let range = start..<(start + 4)
            let changed = zip(rgba[range], reference.rgba[range]).contains { a, b in
                (a > b ? a - b : b - a) > tolerance
            }
            if changed {
                differing += 1
                marked.replaceSubrange(range, with: [255, 0, 0, 255])
            } else {
                for i in range.dropLast() { marked[i] = 128 + marked[i] / 2 }
            }
        }
        return (differing, Self.png(marked, width: width, height: height))
    }

    private static func png(_ rgba: [UInt8], width: Int, height: Int) -> Data? {
        var bytes = rgba
        let image = bytes.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return image.flatMap { UIImage(cgImage: $0).pngData() }
    }
}

enum Fixtures {
    /// The catalogue's examples as a Layers inspector, with a section, a hidden row and a node this
    /// kit doesn't know.
    static let layers = CraftPanel.previewLayers
    /// Stepped and disabled numbers, a menu choice and a collapsed section.
    static let brush = CraftPanel.previewBrush
}
#endif
