// swift-tools-version: 6.0
import PackageDescription

// CaptureCore records an ARKit session into a capture-first SceneRecord (docs/03, docs/04).
// iOS only: ARKit has no macOS host, so its tests run through the app's xcodebuild test scheme.
let package = Package(
    name: "CaptureCore",
    platforms: [.iOS("27.0")],
    products: [.library(name: "CaptureCore", targets: ["CaptureCore"])],
    dependencies: [.package(path: "../SceneRecord")],
    targets: [
        .target(name: "CaptureCore", dependencies: ["SceneRecord"]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore", "SceneRecord"])
    ]
)
