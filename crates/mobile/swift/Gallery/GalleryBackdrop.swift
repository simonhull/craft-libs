import SwiftUI

/// What stands in for the canvas behind the detail, so the floating chrome (the rail, the transport
/// bar, the status) can be judged over what an app shows: a blank white or black document, or a
/// busy picture with bright and dark patches side by side. Kept between launches; `-backdrop white`
/// on the command line picks one.
enum GalleryBackdrop: String, CaseIterable, Identifiable {
    /// The system background, as the Gallery had it.
    case plain
    case white
    case black
    /// Saturated colour, white and black, and fine detail: the worst case for glass.
    case busy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain: "Plain"
        case .white: "White Canvas"
        case .black: "Black Canvas"
        case .busy: "Busy Picture"
        }
    }

    var symbol: String {
        switch self {
        case .plain: "rectangle"
        case .white: "sun.max"
        case .black: "moon"
        case .busy: "photo"
        }
    }
}

extension View {
    /// The backdrop behind this list, its own background hidden so the backdrop shows around the rows.
    func galleryBackdrop(_ backdrop: GalleryBackdrop) -> some View {
        scrollContentBackground(backdrop == .plain ? .automatic : .hidden)
            .background { GalleryBackdropView(backdrop: backdrop).ignoresSafeArea() }
    }
}

/// The toolbar's backdrop picker.
struct GalleryBackdropPicker: View {
    @Binding var backdrop: GalleryBackdrop

    var body: some View {
        Menu {
            Picker("Backdrop", selection: $backdrop) {
                ForEach(GalleryBackdrop.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
        } label: {
            Label("Backdrop", systemImage: backdrop.symbol)
        }
    }
}

struct GalleryBackdropView: View {
    let backdrop: GalleryBackdrop

    var body: some View {
        switch backdrop {
        case .plain: Color.clear
        case .white: Color.white
        case .black: Color.black
        case .busy: GalleryBusyPicture()
        }
    }
}

/// A made-up picture, drawn here (no image file to license): a mesh of saturated colour with white
/// and black patches, crossed by fine stripes and dots, so glass over it has bright, dark and
/// high-frequency detail behind it at once.
struct GalleryBusyPicture: View {
    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.45, 0.55], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                colors: [.white, .orange, .black, .cyan, .white, .indigo, .black, .yellow, .white])
            Canvas { context, size in
                // Thin diagonal stripes, alternately white and black, over the left half.
                var stripe = 0
                for x in stride(from: -size.height, to: size.width / 2, by: 9) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(path, with: .color(stripe.isMultiple(of: 2) ? .white : .black), lineWidth: 2)
                    stripe += 1
                }
                // A grid of dots in red and white over the right half.
                for x in stride(from: size.width / 2, to: size.width, by: 22) {
                    for y in stride(from: 0, to: size.height, by: 22) {
                        let even = (Int(x / 22) + Int(y / 22)).isMultiple(of: 2)
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 9, height: 9)), with: .color(even ? .red : .white))
                    }
                }
            }
            .opacity(0.55)
        }
        .accessibilityHidden(true)
    }
}
