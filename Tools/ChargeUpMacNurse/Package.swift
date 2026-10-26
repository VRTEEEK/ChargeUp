// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChargeUpMacNurse",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/ChargeUpCore"),
    ],
    targets: [
        .executableTarget(
            name: "ChargeUpMacNurse",
            dependencies: [.product(name: "ChargeUpCore", package: "ChargeUpCore")]
        ),
    ]
)
