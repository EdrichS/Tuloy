// swift-tools-version: 6.0
import PackageDescription

// Builds and tests Tuloy from Terminal, no Xcode project needed:
//   swift test    runs the tests
//   make app      builds build/Tuloy.app
let package = Package(
    name: "Tuloy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tuloy", path: "Tuloy"),
        .testTarget(name: "TuloyTests", dependencies: ["Tuloy"]),
    ]
)
