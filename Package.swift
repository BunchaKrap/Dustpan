// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Dustpan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dustpan", targets: ["DustpanApp"]),
        .executable(name: "dustpan-cli", targets: ["DustpanCLI"]),
        .library(name: "DustpanCore", targets: ["DustpanCore"]),
    ],
    targets: [
        // Pure scanning / safety / deletion logic. No UI imports.
        .target(name: "DustpanCore"),
        // Visual system: colour tokens, outline glyphs and app icon artwork (SwiftUI/AppKit).
        .target(name: "DustpanDesign"),
        // SwiftUI app, packaged into Dustpan.app by bundle.sh.
        .executableTarget(name: "DustpanApp", dependencies: ["DustpanCore", "DustpanDesign"]),
        // Terminal harness: exercise the core without the UI (XCTest isn't available with CLT only).
        // Also renders the app icon set for bundle.sh.
        .executableTarget(name: "DustpanCLI", dependencies: ["DustpanCore", "DustpanDesign"]),
    ]
)
