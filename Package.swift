// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "notchai",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "notchai", targets: ["Notchai"]),
        .executable(name: "notchai-hook", targets: ["notchai-hook"]),
    ],
    targets: [
        .target(name: "NotchaiCore", path: "Sources/NotchaiCore"),
        // Das Programm, das Claude Code und Codex als Hook aufrufen (siehe `HookClient`).
        .executableTarget(name: "notchai-hook", dependencies: ["NotchaiCore"], path: "Sources/notchai-hook"),
        .executableTarget(
            name: "Notchai",
            dependencies: ["NotchaiCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Hängt auch von `notchai-hook` ab, damit das Programm vor den Tests gebaut ist (`HookBinaryTests`).
        .testTarget(name: "NotchaiCoreTests", dependencies: ["NotchaiCore", "notchai-hook"],
                    resources: [.copy("Fixtures")]),
    ]
)
