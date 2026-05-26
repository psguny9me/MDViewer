// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDViewer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MDViewer",
            path: "Sources/MDViewer",
            resources: [.copy("Resources")]
        )
    ]
)
