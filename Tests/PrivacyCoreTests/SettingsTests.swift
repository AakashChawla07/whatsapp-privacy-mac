import Foundation
import Testing
@testable import PrivacyCore

@Suite("Settings")
struct SettingsTests {
    @Test func defaultsMatchRequirements() {
        let s = PrivacySettings()
        #expect(s.protectionEnabled)
        #expect(s.targets == PrivacyTargets(previews: true, names: false, timestamps: false, avatars: false))
        #expect(s.intensityPreset == .medium)
        #expect(s.revealMethod == .hover)
        #expect(s.revealTimeout == .untilPointerLeaves)
        #expect(s.protectionScope == .whileWhatsAppVisible)
        #expect(!s.showDebugOverlay && !s.diagnosticLogging && !s.forceFallback)
        #expect(s.toggleShortcut?.displayString == "⇧⌘B")
    }

    @Test func codableRoundTrip() throws {
        var s = PrivacySettings()
        s.targets.avatars = true
        s.revealTimeout = .seconds(5)
        s.revealMethod = .click
        s.toggleShortcut = KeyCombo(keyCode: 35, modifiers: [.control, .option])
        let decoded = try JSONDecoder().decode(PrivacySettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
        #expect(decoded.toggleShortcut?.displayString == "⌃⌥P")
    }

    @Test func partialAndInvalidValuesFallBackPerKey() throws {
        let json = #"{"protectionEnabled": false, "revealMethod": "teleport", "intensity": 7, "toggleShortcut": null}"#
        let decoded = try JSONDecoder().decode(PrivacySettings.self, from: Data(json.utf8))
        #expect(decoded.protectionEnabled == false)
        #expect(decoded.revealMethod == .hover)
        #expect(decoded.intensity == 1)
        #expect(decoded.toggleShortcut == nil)
        #expect(decoded.targets == PrivacyTargets())
    }

    @Test func userDefaultsStoreHandlesMissingAndCorruptData() throws {
        let suite = "PrivacyCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(defaults: defaults)

        #expect(store.load().1 == .defaults)

        var s = PrivacySettings()
        s.blurStyle = .solid
        store.save(s)
        #expect(store.load() == (s, .loaded))

        defaults.set(Data("not json".utf8), forKey: UserDefaultsSettingsStore.settingsKey)
        #expect(store.load() == (PrivacySettings(), .recoveredFromCorruption))
    }

    @Test(arguments: [(0.0, IntensityPreset.low), (0.34, .low), (0.36, .medium), (0.7, .high), (1.0, .high)])
    func intensityPresetNearest(value: Double, expected: IntensityPreset) {
        #expect(IntensityPreset(nearest: value) == expected)
    }
}

@Suite("Debouncer")
@MainActor
struct DebouncerTests {
    @Test func onlyLastScheduledActionRuns() async throws {
        let debouncer = Debouncer()
        var fired: [Int] = []
        for i in 0..<5 {
            debouncer.schedule(after: .milliseconds(40)) { fired.append(i) }
        }
        try await Task.sleep(for: .milliseconds(250))
        #expect(fired == [4])
    }

    @Test func zeroDelayRunsImmediatelyAndCancelStops() async throws {
        let debouncer = Debouncer()
        var fired = 0
        debouncer.schedule(after: .zero) { fired += 1 }
        #expect(fired == 1)

        debouncer.schedule(after: .milliseconds(30)) { fired += 1 }
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(120))
        #expect(fired == 1)
    }
}
