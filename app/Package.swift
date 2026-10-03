// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Classeur",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Classeur", path: "Sources/Classeur"),
        .testTarget(name: "ClasseurTests", dependencies: ["Classeur"], path: "Tests/ClasseurTests"),
    ]
)
