// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Mote",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mote", targets: ["MoteCLI"])
    ],
    targets: [
        .executableTarget(
            name: "MoteCLI",
            linkerSettings: [.linkedFramework("Virtualization")]
        ),
        .testTarget(
            name: "MoteCLITests",
            dependencies: ["MoteCLI"]
        )
    ]
)
