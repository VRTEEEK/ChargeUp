// swift-tools-version: 6.0
// Reality Composer Pro package. Open Package.realitycomposerpro in Reality
// Composer Pro to add or replace assets; the app loads them by name.
import PackageDescription

let package = Package(
    name: "ChargeUpAssets",
    platforms: [
        .visionOS(.v2),
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ChargeUpAssets", targets: ["ChargeUpAssets"]),
    ],
    targets: [
        // Models live in ChargeUpAssets.rkassets (compiled by Reality Composer Pro's
        // tooling); PNGs the app must read as images live in Textures/ as plain resources.
        .target(
            name: "ChargeUpAssets",
            resources: [.copy("Textures")]
        ),
    ]
)
