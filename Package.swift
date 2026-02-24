// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Zispper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Zispper", targets: ["Zispper"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Zispper",
            dependencies: [],
            resources: []
        ),
    ]
)
