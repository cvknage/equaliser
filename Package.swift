// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Equaliser",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // Swift Atomics for thread-safe atomic operations in real-time audio
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Equaliser",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "src",
            exclude: ["app/Info.plist"]
        ),
        .testTarget(
            name: "EqualiserTests",
            dependencies: ["Equaliser"],
            path: "tests"
        )
    ]
)
