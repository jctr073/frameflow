// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MediaBrowser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MediaBrowser", targets: ["MediaBrowser"]),
        .executable(name: "MediaBrowserLogicTests", targets: ["MediaBrowserLogicTests"])
    ],
    targets: [
        .target(
            name: "MediaBrowserCore",
            path: "Sources/MediaBrowserCore"
        ),
        .executableTarget(
            name: "MediaBrowser",
            dependencies: ["MediaBrowserCore"],
            path: "Sources/MediaBrowser"
        ),
        .executableTarget(
            name: "MediaBrowserLogicTests",
            dependencies: ["MediaBrowserCore"],
            path: "Tests/MediaBrowserLogicTests"
        )
    ]
)
