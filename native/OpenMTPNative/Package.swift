// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenMTPNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "OpenMTPNative",
            targets: ["OpenMTPNative"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenMTPNative"
        )
    ]
)
