// swift-tools-version: 6.0
import PackageDescription

// NorthResolver (docs/05, ADR-0009): fuses direction candidates into the true azimuth of the AR world's −Z axis and
// says which light the result earns. Pure Swift, no device APIs: reading the compass or a wall is the caller's job.
let package = Package(
    name: "NorthResolver",
    platforms: [.iOS("27.0"), .macOS("15.0")],  // iOS 27 per ADR-0011; macOS floor only so the local test host builds
    products: [.library(name: "NorthResolver", targets: ["NorthResolver"])],
    targets: [
        .target(name: "NorthResolver"),
        .testTarget(name: "NorthResolverTests", dependencies: ["NorthResolver"])
    ]
)
