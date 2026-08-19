import Foundation

public enum ProtectionScope: String, Codable, Sendable, CaseIterable {
    /// Protect whenever WhatsApp's window is visible on screen (default; privacy first).
    case whileWhatsAppVisible
    /// Protect only while WhatsApp is the active application (literal requirements §49).
    case whileWhatsAppActive
}

public struct PrivacyTargets: Codable, Equatable, Sendable {
    public var previews: Bool
    public var names: Bool
    public var timestamps: Bool
    public var avatars: Bool

    public init(previews: Bool = true, names: Bool = false, timestamps: Bool = false, avatars: Bool = false) {
        self.previews = previews
        self.names = names
        self.timestamps = timestamps
        self.avatars = avatars
    }

    public var anyText: Bool { previews || names || timestamps }
    public var any: Bool { anyText || avatars }
}

public enum BlurStyle: String, Codable, Sendable, CaseIterable {
    case material, solid
}

public enum IntensityPreset: String, Sendable, CaseIterable, Identifiable {
    case low, medium, high

    public var id: String { rawValue }

    public var value: Double {
        switch self {
        case .low: 0.2
        case .medium: 0.5
        case .high: 0.85
        }
    }

    public init(nearest value: Double) {
        self = Self.allCases.min { abs($0.value - value) < abs($1.value - value) } ?? .medium
    }
}

public enum AppearanceOverride: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

public enum RevealMethod: String, Codable, Sendable, CaseIterable {
    case hover, click, hoverAndClick, optionHover, disabled

    public var revealsOnHover: Bool { self == .hover || self == .hoverAndClick || self == .optionHover }
}

public enum RevealTimeout: Codable, Hashable, Sendable {
    case untilPointerLeaves
    case seconds(Int)

    public static let choices: [RevealTimeout] = [.untilPointerLeaves, .seconds(2), .seconds(5), .seconds(10)]
}

public enum RevealScope: String, Codable, Sendable, CaseIterable {
    case previewOnly, wholeRow
}

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
}

/// A global shortcut expressed as a virtual key code (kVK_*) plus modifiers.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌘⇧B (requirements §48).
    public static let commandShiftB = KeyCombo(keyCode: 11, modifiers: [.command, .shift])

    /// Human-readable form in macOS modifier order, e.g. "⇧⌘B".
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    // ANSI virtual key codes.
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
    ]
}

public struct PrivacySettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = PrivacySettings.currentSchemaVersion

    // General
    public var protectionEnabled = true
    public var enableAutomaticallyOnLaunch = true
    public var launchAtLogin = false
    public var protectionScope: ProtectionScope = .whileWhatsAppVisible

    // Blur
    public var targets = PrivacyTargets()
    public var blurStyle: BlurStyle = .material
    /// 0 (low) ... 1 (high). Every value must still render text illegible.
    public var intensity: Double = IntensityPreset.medium.value
    public var overlayAppearance: AppearanceOverride = .system

    // Reveal
    public var revealMethod: RevealMethod = .hover
    public var revealTimeout: RevealTimeout = .untilPointerLeaves
    public var revealScope: RevealScope = .previewOnly

    // Advanced
    public var forceFallback = false
    public var showDebugOverlay = false
    public var diagnosticLogging = false
    public var toggleShortcut: KeyCombo? = .commandShiftB

    public init() {}

    public var intensityPreset: IntensityPreset {
        get { IntensityPreset(nearest: intensity) }
        set { intensity = newValue.value }
    }

    // Tolerant decoding: missing or unknown-valued keys fall back to defaults instead of
    // discarding the whole settings blob.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, protectionEnabled, enableAutomaticallyOnLaunch, launchAtLogin, protectionScope
        case targets, blurStyle, intensity, overlayAppearance
        case revealMethod, revealTimeout, revealScope
        case forceFallback, showDebugOverlay, diagnosticLogging, toggleShortcut
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PrivacySettings()

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }

        schemaVersion = value(.schemaVersion, d.schemaVersion)
        protectionEnabled = value(.protectionEnabled, d.protectionEnabled)
        enableAutomaticallyOnLaunch = value(.enableAutomaticallyOnLaunch, d.enableAutomaticallyOnLaunch)
        launchAtLogin = value(.launchAtLogin, d.launchAtLogin)
        protectionScope = value(.protectionScope, d.protectionScope)
        targets = value(.targets, d.targets)
        blurStyle = value(.blurStyle, d.blurStyle)
        intensity = min(1, max(0, value(.intensity, d.intensity)))
        overlayAppearance = value(.overlayAppearance, d.overlayAppearance)
        revealMethod = value(.revealMethod, d.revealMethod)
        revealTimeout = value(.revealTimeout, d.revealTimeout)
        revealScope = value(.revealScope, d.revealScope)
        forceFallback = value(.forceFallback, d.forceFallback)
        showDebugOverlay = value(.showDebugOverlay, d.showDebugOverlay)
        diagnosticLogging = value(.diagnosticLogging, d.diagnosticLogging)
        if c.contains(.toggleShortcut) {
            toggleShortcut = try? c.decodeIfPresent(KeyCombo.self, forKey: .toggleShortcut)
        } else {
            toggleShortcut = d.toggleShortcut
        }
        schemaVersion = PrivacySettings.currentSchemaVersion
    }
}
