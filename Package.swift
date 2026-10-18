// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Kaleido",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything that does not need a window or a GPU: settings, photo library, bookmarks, shuffle.
        .target(name: "KaleidoCore", path: "Sources/KaleidoCore"),
        .executableTarget(name: "Kaleido", dependencies: ["KaleidoCore"], path: "Sources/Kaleido"),
        .testTarget(name: "KaleidoCoreTests", dependencies: ["KaleidoCore"], path: "Tests/KaleidoCoreTests"),
    ]
)
