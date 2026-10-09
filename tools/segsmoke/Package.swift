// swift-tools-version: 6.0
import PackageDescription

// Experiment 0 of the Light Replay plan (docs/07 §5a): what Vision's seeded segmentation returns for a point in the
// sky. A Mac command-line tool; nothing in the app depends on it.
let package = Package(
    name: "segsmoke",
    platforms: [.macOS("27.0")],
    targets: [.executableTarget(name: "segsmoke")]
)
