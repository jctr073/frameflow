// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Frameflow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Frameflow", targets: ["Frameflow"]),
        .executable(name: "FrameflowLogicTests", targets: ["FrameflowLogicTests"])
    ],
    targets: [
        .target(
            name: "FrameflowCore",
            path: "Sources/FrameflowCore"
        ),
        .executableTarget(
            name: "Frameflow",
            dependencies: ["FrameflowCore"],
            path: "Sources/Frameflow"
        ),
        .executableTarget(
            name: "FrameflowLogicTests",
            dependencies: ["FrameflowCore"],
            path: "Tests/FrameflowLogicTests"
        )
    ]
)
