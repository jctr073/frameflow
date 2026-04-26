// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MediaBrowser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MediaBrowser", targets: ["MediaBrowser"])
    ],
    targets: [
        .executableTarget(
            name: "MediaBrowser",
            path: "Sources/MediaBrowser",
            exclude: ["crash.log"]
        )
    ]
)
