// swift-tools-version:5.9
// This file is provided for reference only.
// The actual package dependencies are managed via Xcode's Swift Package Manager integration.

import PackageDescription

let package = Package(
    name: "NAM Reamp Lab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NAM Reamp Lab",
            targets: ["NAM Reamp Lab"]),
    ],
    dependencies: [
        // PythonKit for Python integration
        .package(url: "https://github.com/pvieito/PythonKit.git", from: "0.3.1"),
    ],
    targets: [
        .target(
            name: "NAM Reamp Lab",
            dependencies: ["PythonKit"]),
    ]
)
