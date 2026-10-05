import Foundation
import PrivacyCore
import PrivacyLog

/// Composition root at runtime: feeds events into the pure reducer and executes the resulting effects.
/// Contains no protection logic of its own.
@MainActor
final class AppCoordinator {
    let model: AppModel
    private(set) var state: CoreState

    private let dependencies: Dependencies
    private var pendingEvents: [AppEvent] = []
    private var isReducing = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        let (settings, loadResult) = dependencies.settingsStore.load()
        state = CoreState(settings: settings)
        model = AppModel(settings: settings, loginItemStatus: dependencies.loginItems.status)
        model.sendEvent = { [weak self] event in self?.send(event) }
        PrivacyLog.diagnostics.isEnabled = settings.diagnosticLogging
        PrivacyLog.record(.settingsLoaded(loadResult))
    }

    func start() {
        PrivacyLog.record(.appStarted)
        let trusted = dependencies.permissions.isTrusted()
        PrivacyLog.record(.permission(trusted: trusted))
        send(.appStarted(accessibilityTrusted: trusted))
    }

    func refreshPermission() {
        guard state.hasStarted else { return }
        send(.permissionChanged(trusted: dependencies.permissions.isTrusted()))
    }

    /// Events raised while effects are executing are queued and processed in order, never re-entrantly.
    func send(_ event: AppEvent) {
        pendingEvents.append(event)
        guard !isReducing else { return }
        isReducing = true
        defer { isReducing = false }

        while !pendingEvents.isEmpty {
            let next = pendingEvents.removeFirst()
            let oldPhase = state.phase
            let effects = ProtectionReducer.reduce(&state, next)
            if oldPhase != state.phase {
                PrivacyLog.record(.phaseChanged(from: oldPhase.tag, to: state.phase.tag))
            }
            effects.forEach(execute)
            model.update(from: state, loginItemStatus: dependencies.loginItems.status)
        }
    }

    private func execute(_ effect: Effect) {
        switch effect {
        case .persistSettings(let settings):
            dependencies.settingsStore.save(settings)
            PrivacyLog.diagnostics.isEnabled = settings.diagnosticLogging
            PrivacyLog.record(.settingsSaved)

        case .setLoginItem(let enabled):
            if !dependencies.loginItems.setEnabled(enabled) {
                PrivacyLog.record(.loginItemUpdateFailed)
            }

        case .applyCoverage(let coverage):
            PrivacyLog.record(.coverageApplied(tier: coverage.tier, regions: coverage.regions.count))

        case .noticeDegradedMode:
            PrivacyLog.record(.degradedModeEntered)

        // Implemented in later phases (see docs/ARCHITECTURE.md §15):
        // observation & detection (Phase 2/4), overlay (Phase 3), input (Phase 6), hot key & onboarding (Phase 7).
        case .startObserving, .stopObserving, .requestDetection, .showOverlay, .hideOverlay,
             .setOverlayLevel, .concealAll, .setInputMonitoring, .showOnboarding, .registerHotKey:
            PrivacyLog.record(.effectNotYetImplemented(effect.kind))
        }
    }
}
