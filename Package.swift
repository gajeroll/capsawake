// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CapsAwake",
    platforms: [
        .macOS(.v14),
    ],
    // CapsAwakeCore is deliberately not a product. Publishing it would make every
    // `public` declaration in it an API commitment to external consumers, and its surface is
    // public only because the app's other targets are separate modules.
    products: [
        .executable(name: "CapsAwake", targets: ["CapsAwake"]),
        .executable(name: "CapsAwakeDaemon", targets: ["CapsAwakeDaemon"]),
    ],
    targets: [
        .target(
            name: "CapsAwakeCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .strictMemorySafety(),
            ]
        ),
        .target(
            name: "CapsAwakeIPC",
            dependencies: ["CapsAwakeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CapsAwakeSystem",
            dependencies: ["CapsAwakeCore", "CapsAwakeIPC"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]
        ),
        .target(
            name: "CapsAwakeUI",
            dependencies: ["CapsAwakeCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .executableTarget(
            name: "CapsAwakeDaemon",
            dependencies: ["CapsAwakeCore", "CapsAwakeIPC", "CapsAwakeSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "CapsAwake",
            dependencies: [
                "CapsAwakeCore",
                "CapsAwakeIPC",
                "CapsAwakeSystem",
                "CapsAwakeUI",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "CapsAwakeCoreTests",
            dependencies: ["CapsAwakeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CapsAwakeSystemTests",
            dependencies: ["CapsAwakeSystem", "CapsAwakeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Depending on an executable target is allowed, and `@testable import` reaches
        // its internals, so the app's own wiring does not have to go untested to stay
        // where it belongs.
        .testTarget(
            name: "CapsAwakeAppTests",
            dependencies: ["CapsAwake", "CapsAwakeCore", "CapsAwakeSystem"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
