// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "zispper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "zispper", targets: ["zispper"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "zispper",
            dependencies: [],
            resources: []
        ),
    ]
)
