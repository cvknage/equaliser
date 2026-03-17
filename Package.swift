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
            path: "sources",
            exclude: ["app/Info.plist"]
        ),
        .testTarget(
            name: "EqualiserTests",
            dependencies: ["Equaliser"],
            path: "tests"
        )
    ]
)
