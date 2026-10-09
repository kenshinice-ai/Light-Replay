// swift-tools-version: 6.0
import PackageDescription

// GuideCore holds the rules the Guide layer must obey (ADR-0010): it never writes a number
// the tools did not give, and never states Unknown or glass-uncertain as certain.
// Pure Swift, no model calls: the regression check runs on macOS and in CI.
let package = Package(
    name: "GuideCore",
    platforms: [.iOS("27.0"), .macOS("15.0")],  // iOS 27 per ADR-0011; macOS floor only so the local test host builds
    products: [.library(name: "GuideCore", targets: ["GuideCore"])],
    targets: [
        .target(name: "GuideCore"),
        .testTarget(name: "GuideCoreTests", dependencies: ["GuideCore"])
    ]
)
