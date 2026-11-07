// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CraftUI",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "CraftUI", targets: ["CraftUI"])],
    targets: [
        .target(name: "CraftUI"),
        .testTarget(name: "CraftUITests", dependencies: ["CraftUI"], resources: [.copy("Fixtures")]),
    ]
)
