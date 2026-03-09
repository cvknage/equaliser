// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EqualiserApp",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "EqualiserApp",
            path: "Sources",
            exclude: ["App/Info.plist"]
        ),
        .testTarget(
            name: "EqualiserAppTests",
            dependencies: ["EqualiserApp"],
            path: "Tests"
        )
    ]
)
