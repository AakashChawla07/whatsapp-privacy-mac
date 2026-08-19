import Foundation

public enum SettingsLoadResult: Equatable, Sendable {
    case defaults
    case loaded
    /// Stored data could not be decoded at all; defaults were used.
    case recoveredFromCorruption
}

public protocol SettingsStore: Sendable {
    func load() -> (PrivacySettings, SettingsLoadResult)
    func save(_ settings: PrivacySettings)
}

/// Persists settings as a single JSON blob. This, plus the permission-prompt flag,
/// is the only data the app ever persists (requirements §30.2).
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    public static let settingsKey = "settings.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> (PrivacySettings, SettingsLoadResult) {
        guard let data = defaults.data(forKey: Self.settingsKey) else {
            return (PrivacySettings(), .defaults)
        }
        guard let settings = try? JSONDecoder().decode(PrivacySettings.self, from: data) else {
            return (PrivacySettings(), .recoveredFromCorruption)
        }
        return (settings, .loaded)
    }

    public func save(_ settings: PrivacySettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.settingsKey)
    }
}

public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PrivacySettings?

    public init(_ settings: PrivacySettings? = nil) {
        self.stored = settings
    }

    public func load() -> (PrivacySettings, SettingsLoadResult) {
        lock.withLock { stored.map { ($0, .loaded) } ?? (PrivacySettings(), .defaults) }
    }

    public func save(_ settings: PrivacySettings) {
        lock.withLock { stored = settings }
    }
}
