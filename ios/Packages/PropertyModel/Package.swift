// swift-tools-version: 6.0
import PackageDescription

// PropertyModel is the Property graph from docs/15 (SwiftData, local first). iOS only.
let package = Package(
    name: "PropertyModel",
    platforms: [.iOS("27.0")],
    products: [.library(name: "PropertyModel", targets: ["PropertyModel"])],
    targets: [
        .target(name: "PropertyModel"),
        .testTarget(name: "PropertyModelTests", dependencies: ["PropertyModel"])
    ]
)
