// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacUpdaterCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacUpdaterCore", targets: ["MacUpdaterCore"])
    ],
    targets: [
        .target(name: "MacUpdaterCore")
    ]
)
