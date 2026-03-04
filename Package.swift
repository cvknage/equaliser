// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EqualizerApp",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "EqualizerApp",
            path: "Sources",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "EqualizerAppTests",
            dependencies: ["EqualizerApp"],
            path: "Tests"
        )
    ]
)
