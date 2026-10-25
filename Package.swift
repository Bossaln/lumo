// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "lumo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lumo", targets: ["Lumo"]),
        .executable(name: "lumo-hook", targets: ["lumo-hook"]),
        .executable(name: "lumo-welcome", targets: ["lumo-welcome"]),
    ],
    targets: [
        .target(name: "LumoCore", path: "Sources/LumoCore"),
        // Das Programm, das Claude Code und Codex als Hook aufrufen (siehe `HookClient`).
        .executableTarget(name: "lumo-hook", dependencies: ["LumoCore"], path: "Sources/lumo-hook"),
        // Der fahrende GT-R nach `brew install` und `brew upgrade` (siehe `InstallGreeting`).
        .executableTarget(name: "lumo-welcome", dependencies: ["LumoCore"], path: "Sources/lumo-welcome"),
        .executableTarget(
            name: "Lumo",
            dependencies: ["LumoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Hängt auch von `lumo-hook` ab, damit das Programm vor den Tests gebaut ist (`HookBinaryTests`).
        .testTarget(name: "LumoCoreTests", dependencies: ["LumoCore", "lumo-hook"],
                    resources: [.copy("Fixtures")]),
    ]
)
