// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TokenTown", platforms: [.macOS(.v14)], targets: [
    .executableTarget(name: "TokenTown", path: "Sources/TokenTown"),
    .testTarget(name: "TokenTownTests", dependencies: ["TokenTown"], path: "Tests/TokenTownTests",
               resources: [.copy("Fixtures/CodexFork"), .copy("Fixtures/CodexSubagent")])
])
