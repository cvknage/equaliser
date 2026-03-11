// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Equaliser",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "Equaliser",
            path: "Sources",
            exclude: ["App/Info.plist"]
        ),
        .testTarget(
            name: "EqualiserTests",
            dependencies: ["Equaliser"],
            path: "Tests"
        )
    ]
)
