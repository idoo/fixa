// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FixaKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "FixaKit", targets: ["FixaKit"]),
        .executable(name: "fixa-cli", targets: ["fixa-cli"]),
    ],
    targets: [
        .target(
            name: "FixaKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "fixa-cli",
            dependencies: ["FixaKit"]
        ),
        .testTarget(
            name: "FixaKitTests",
            dependencies: ["FixaKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
