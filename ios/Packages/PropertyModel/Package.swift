// swift-tools-version: 6.0
import PackageDescription

// PropertyModel is the Property graph from docs/15 (SwiftData, local first). iOS only.
let package = Package(
    name: "PropertyModel",
    defaultLocalization: "en",   // display names live here in English and zh-Hans (Localizable.xcstrings)
    platforms: [.iOS("27.0")],
    products: [.library(name: "PropertyModel", targets: ["PropertyModel"])],
    targets: [
        .target(name: "PropertyModel", resources: [.process("Localizable.xcstrings")]),
        .testTarget(name: "PropertyModelTests", dependencies: ["PropertyModel"])
    ]
)
