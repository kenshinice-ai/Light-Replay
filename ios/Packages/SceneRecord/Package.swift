// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SceneRecord",
    platforms: [.iOS("27.0"), .macOS("15.0")],  // iOS 27 per ADR-0011; macOS floor only so the local test host builds
    products: [
        .library(name: "SceneRecord", targets: ["SceneRecord"]),
        .executable(name: "scene-record-check", targets: ["SceneRecordCheck"])
    ],
    dependencies: [.package(path: "../NorthResolver")],
    targets: [
        // NorthResolver is here for QualityEvaluator: the north light is worked out again from the candidates.
        .target(name: "SceneRecord", dependencies: ["NorthResolver"]),
        .executableTarget(name: "SceneRecordCheck", dependencies: ["SceneRecord"]),
        .testTarget(name: "SceneRecordTests", dependencies: ["SceneRecord"])
    ]
)
