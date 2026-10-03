// swift-tools-version: 6.0
import PackageDescription

// SunEngine (docs/06): solar position, sky visibility grid, direct-sun bands. Pure Swift, no device APIs, so it runs
// under `swift test` on the Mac as well as in the app.
let package = Package(
    name: "SunEngine",
    platforms: [.iOS("27.0"), .macOS("15.0")],  // iOS 27 per ADR-0011; macOS floor only so the local test host builds
    products: [.library(name: "SunEngine", targets: ["SunEngine"])],
    targets: [
        .target(name: "SunEngine"),
        .testTarget(name: "SunEngineTests", dependencies: ["SunEngine"])
    ]
)
