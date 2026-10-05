import Observation
import PrivacyCore
import SwiftUI

/// UI-facing projection of `CoreState`. Views never mutate state directly; they send events.
@MainActor
@Observable
final class AppModel {
    private(set) var phase: ProtectionPhase = .launching
    private(set) var coverageTier: CoverageTier?
    private(set) var settings: PrivacySettings
    private(set) var loginItemStatus: LoginItemStatus

    @ObservationIgnored var sendEvent: (AppEvent) -> Void = { _ in }

    init(settings: PrivacySettings, loginItemStatus: LoginItemStatus) {
        self.settings = settings
        self.loginItemStatus = loginItemStatus
    }

    func update(from state: CoreState, loginItemStatus: LoginItemStatus) {
        if phase != state.phase { phase = state.phase }
        if coverageTier != state.coverage?.tier { coverageTier = state.coverage?.tier }
        if settings != state.settings { settings = state.settings }
        if self.loginItemStatus != loginItemStatus { self.loginItemStatus = loginItemStatus }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<PrivacySettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = self.settings
                updated[keyPath: keyPath] = newValue
                self.sendEvent(.settingsChanged(updated))
            }
        )
    }

    func toggleProtection() {
        sendEvent(.toggleProtection)
    }

    func resetSettings() {
        sendEvent(.settingsChanged(PrivacySettings()))
    }

    // MARK: Presentation

    var menuBarSymbol: String {
        switch phase {
        case .protecting: "lock.fill"
        case .disabled: "lock.open"
        case .needsPermission: "lock.trianglebadge.exclamationmark"
        default: "lock"
        }
    }

    var statusText: String {
        switch phase {
        case .launching: "Starting…"
        case .disabled: "Protection is off"
        case .needsPermission: "Needs Accessibility permission"
        case .waitingForWhatsApp: "Waiting for WhatsApp"
        case .waitingForWindow: "Waiting for WhatsApp window"
        case .suspended(let reason): "Paused — \(reason.title)"
        case .protecting: "Protecting" + (coverageTier.map { " · \($0.title)" } ?? "")
        }
    }
}

extension SuspendReason {
    var title: String {
        switch self {
        case .systemAsleep: "Mac asleep"
        case .screenLocked: "screen locked"
        case .appHidden: "WhatsApp hidden"
        case .minimized: "WhatsApp minimized"
        case .otherSpace: "WhatsApp on another Space"
        case .inactiveScope: "WhatsApp not active"
        }
    }
}

extension CoverageTier {
    var title: String {
        switch self {
        case .precise: "Precise"
        case .rowBand: "Rows"
        case .column: "Sidebar column"
        case .windowHeuristic: "Safe fallback"
        }
    }
}
