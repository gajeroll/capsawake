// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "CapsAwake",
    platforms: [.macOS(.v14)],
    products: [],
    targets: [
        .target(name: "CapsAwakeCore", swiftSettings: [.swiftLanguageMode(.v6), .strictMemorySafety()]),

        .testTarget(name: "CapsAwakeCoreTests", dependencies: ["CapsAwakeCore"], swiftSettings: [.swiftLanguageMode(.v6)])
    ]
)
