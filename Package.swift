// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "CapsAwake",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CapsAwakeDaemon", targets: ["CapsAwakeDaemon"]),],
    targets: [
        .target(name: "CapsAwakeCore", swiftSettings: [.swiftLanguageMode(.v6), .strictMemorySafety()]),

        .testTarget(name: "CapsAwakeCoreTests", dependencies: ["CapsAwakeCore"], swiftSettings: [.swiftLanguageMode(.v6)]),

        .target(name: "CapsAwakeIPC", dependencies: ["CapsAwakeCore"], swiftSettings: [.swiftLanguageMode(.v6)]),

        .target(
            name: "CapsAwakeSystem",
            dependencies: ["CapsAwakeCore", "CapsAwakeIPC"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]
        ),

        .testTarget(name: "CapsAwakeSystemTests", dependencies: ["CapsAwakeSystem", "CapsAwakeCore"], swiftSettings: [.swiftLanguageMode(.v6)]),

        .executableTarget(
            name: "CapsAwakeDaemon",
            dependencies: ["CapsAwakeCore", "CapsAwakeIPC", "CapsAwakeSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Security")]
        )
    ]
)
