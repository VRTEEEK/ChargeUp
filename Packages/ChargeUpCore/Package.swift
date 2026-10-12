// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChargeUpCore",
    platforms: [
        .iOS(.v17),
        .visionOS(.v2),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ChargeUpCore", targets: ["ChargeUpCore"]),
    ],
    targets: [
        // The brief keeps Resources/ beside Sources/ rather than inside the
        // target folder, so the target root is the package root with Sources
        // narrowed explicitly and Tests excluded.
        .target(
            name: "ChargeUpCore",
            path: ".",
            exclude: ["Tests", "Package.swift"],
            sources: ["Sources/ChargeUpCore"],
            resources: [.copy("Resources/sequence.json")]
        ),
        .testTarget(
            name: "ChargeUpCoreTests",
            dependencies: ["ChargeUpCore"],
            path: "Tests/ChargeUpCoreTests"
        ),
    ]
)
