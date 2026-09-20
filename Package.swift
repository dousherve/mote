// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Mote",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mote", targets: ["Mote"])
    ],
    targets: [
        .executableTarget(
            name: "Mote",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Virtualization")
            ]
        ),
        .testTarget(
            name: "MoteTests",
            dependencies: ["Mote"]
        )
    ]
)
