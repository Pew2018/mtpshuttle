// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftMTP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SwiftMTP",
            targets: ["SwiftMTP"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SwiftMTP"
        ),
        .testTarget(
            name: "SwiftMTPTests",
            dependencies: ["SwiftMTP"]
        )
    ]
)
