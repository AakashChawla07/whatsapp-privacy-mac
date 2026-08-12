// swift-tools-version: 6.0
import PackageDescription

/// Phase 0 spike tools are throwaway investigation code; they compile in Swift 5 mode to keep
/// C-callback / run-loop glue simple. Product code stays in Swift 6 strict concurrency.
let spikeSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "WhatsAppPrivacyBlur",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WhatsAppPrivacyBlur", targets: ["WhatsAppPrivacyBlur"]),

        // Phase 0 spikes (see docs/spikes/README.md)
        .executable(name: "ax-dump", targets: ["AXDump"]),
        .executable(name: "ax-watch", targets: ["AXWatch"]),
        .executable(name: "window-list", targets: ["WindowList"]),
        .executable(name: "blur-lab", targets: ["BlurLab"]),
    ],
    targets: [
        // Pure logic: geometry, models, state machine, coverage planning, settings.
        // Must not import AppKit or ApplicationServices.
        .target(name: "PrivacyCore"),

        // Content-free structured logging.
        .target(name: "PrivacyLog", dependencies: ["PrivacyCore"]),

        // Composition root + menu bar / settings UI.
        .executableTarget(
            name: "WhatsAppPrivacyBlur",
            dependencies: ["PrivacyCore", "PrivacyLog"]
        ),

        .testTarget(name: "PrivacyCoreTests", dependencies: ["PrivacyCore"]),

        // MARK: Phase 0 spikes
        .target(name: "SpikeSupport", path: "Spikes/SpikeSupport", swiftSettings: spikeSettings),
        .executableTarget(name: "AXDump", dependencies: ["SpikeSupport"], path: "Spikes/AXDump", swiftSettings: spikeSettings),
        .executableTarget(name: "AXWatch", dependencies: ["SpikeSupport"], path: "Spikes/AXWatch", swiftSettings: spikeSettings),
        .executableTarget(name: "WindowList", dependencies: ["SpikeSupport"], path: "Spikes/WindowList", swiftSettings: spikeSettings),
        .executableTarget(name: "BlurLab", dependencies: ["SpikeSupport"], path: "Spikes/BlurLab", swiftSettings: spikeSettings),
    ]
)
