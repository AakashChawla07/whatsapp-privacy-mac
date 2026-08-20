import CoreGraphics
import Testing
@testable import PrivacyCore

@Suite("Protection reducer")
struct ProtectionReducerTests {
    /// Drives a fresh state to `.protecting` with WhatsApp frontmost.
    func protectingState(settings: PrivacySettings = PrivacySettings()) -> CoreState {
        var state = CoreState(settings: settings)
        _ = ProtectionReducer.reduce(&state, .appStarted(accessibilityTrusted: true))
        _ = ProtectionReducer.reduce(&state, .whatsAppLaunched(pid: Fixtures.pid, isActive: true, isHidden: false))
        _ = ProtectionReducer.reduce(&state, .windowAvailable(Fixtures.trackedWindow))
        return state
    }

    func kinds(_ effects: [Effect]) -> [Effect.Kind] { effects.map(\.kind) }

    @Test func launchWithoutPermissionShowsOnboardingAndDoesNotObserve() {
        var state = CoreState()
        let effects = ProtectionReducer.reduce(&state, .appStarted(accessibilityTrusted: false))
        #expect(state.phase == .needsPermission)
        #expect(kinds(effects) == [.registerHotKey, .showOnboarding])
    }

    @Test func fullStartupSequenceReachesProtectingWithFailsafeCoverage() {
        var state = CoreState()
        #expect(state.phase == .launching)

        _ = ProtectionReducer.reduce(&state, .appStarted(accessibilityTrusted: true))
        #expect(state.phase == .waitingForWhatsApp)

        let launch = ProtectionReducer.reduce(&state, .whatsAppLaunched(pid: Fixtures.pid, isActive: true, isHidden: false))
        #expect(state.phase == .waitingForWindow)
        #expect(launch == [.startObserving(pid: Fixtures.pid)])

        let window = ProtectionReducer.reduce(&state, .windowAvailable(Fixtures.trackedWindow))
        #expect(state.phase == .protecting)
        #expect(kinds(window) == [.applyCoverage, .setOverlayLevel, .showOverlay, .setInputMonitoring, .requestDetection])
        #expect(state.coverage?.tier == .windowHeuristic)
        #expect(window.contains(.setOverlayLevel(.floating)))
        #expect(window.contains(.requestDetection(state.generation, hint: .fullScan, after: .zero)))
    }

    @Test func currentDetectionRefinesCoverageAndStaleDetectionIsDropped() {
        var state = protectingState()
        let stale = Fixtures.snapshot(generation: Generation(state.generation.value - 1))
        #expect(ProtectionReducer.reduce(&state, .layoutDetected(stale)).isEmpty)
        #expect(state.coverage?.tier == .windowHeuristic)

        let effects = ProtectionReducer.reduce(&state, .layoutDetected(Fixtures.snapshot(generation: state.generation)))
        #expect(kinds(effects) == [.applyCoverage])
        #expect(state.coverage?.tier == .precise)
        #expect(state.layoutInvalidated == false)
    }

    @Test func resizeWidensImmediatelyConcealsAndDebouncesDetection() {
        var state = protectingState()
        _ = ProtectionReducer.reduce(&state, .layoutDetected(Fixtures.snapshot(generation: state.generation)))
        let oldGeneration = state.generation

        let resized = AXRect(x: Fixtures.window.minX, y: Fixtures.window.minY, width: 1200, height: 950)
        let effects = ProtectionReducer.reduce(&state, .windowResized(resized))
        #expect(state.generation > oldGeneration)
        #expect(kinds(effects) == [.concealAll, .applyCoverage, .requestDetection])
        #expect(state.coverage?.tier == .column)
        #expect(effects.last == .requestDetection(state.generation, hint: .fastPath, after: .milliseconds(80)))

        // A result for the pre-resize generation must not restore precise regions.
        _ = ProtectionReducer.reduce(&state, .layoutDetected(Fixtures.snapshot(generation: oldGeneration)))
        #expect(state.coverage?.tier == .column)
    }

    @Test func pureMoveTranslatesWithoutInvalidating() {
        var state = protectingState()
        _ = ProtectionReducer.reduce(&state, .layoutDetected(Fixtures.snapshot(generation: state.generation)))
        let generation = state.generation
        let effects = ProtectionReducer.reduce(&state, .windowMoved(Fixtures.window.offsetBy(dx: 40, dy: 10)))
        #expect(state.generation == generation)
        #expect(kinds(effects) == [.applyCoverage])
        #expect(state.coverage?.tier == .precise)
    }

    @Test func scrollWidensUntilQuietThenRequestsDetection() {
        var state = protectingState()
        _ = ProtectionReducer.reduce(&state, .layoutDetected(Fixtures.snapshot(generation: state.generation)))

        let active = ProtectionReducer.reduce(&state, .scrollActivity(.active))
        #expect(kinds(active) == [.concealAll, .applyCoverage])
        #expect(state.coverage?.tier == .column)

        let again = ProtectionReducer.reduce(&state, .scrollActivity(.active))
        #expect(kinds(again) == [.concealAll])

        let ended = ProtectionReducer.reduce(&state, .scrollActivity(.ended))
        #expect(ended == [.requestDetection(state.generation, hint: .fastPath, after: .zero)])
    }

    @Test func switchingAppsChangesLevelOrSuspendsByScope() {
        var visible = protectingState()
        let deactivate = ProtectionReducer.reduce(&visible, .whatsAppActivationChanged(isActive: false))
        #expect(visible.phase == .protecting)
        #expect(deactivate == [.setOverlayLevel(.aboveWindow(Fixtures.windowID))])

        var activeOnly = PrivacySettings()
        activeOnly.protectionScope = .whileWhatsAppActive
        var state = protectingState(settings: activeOnly)
        let effects = ProtectionReducer.reduce(&state, .whatsAppActivationChanged(isActive: false))
        #expect(state.phase == .suspended(.inactiveScope))
        #expect(effects == [.setInputMonitoring(enabled: false), .hideOverlay])
    }

    @Test func terminationHidesOverlayAndStopsObserving() {
        var state = protectingState()
        #expect(ProtectionReducer.reduce(&state, .whatsAppTerminated(pid: 1)).isEmpty)   // unrelated pid

        let effects = ProtectionReducer.reduce(&state, .whatsAppTerminated(pid: Fixtures.pid))
        #expect(state.phase == .waitingForWhatsApp)
        #expect(effects == [.stopObserving, .setInputMonitoring(enabled: false), .hideOverlay])
        #expect(state.window == nil && state.latestSnapshot == nil)
    }

    @Test func toggleOffRemovesOverlayAndPersists() {
        var state = protectingState()
        let effects = ProtectionReducer.reduce(&state, .toggleProtection)
        #expect(state.phase == .disabled)
        #expect(kinds(effects) == [.stopObserving, .setInputMonitoring, .hideOverlay, .persistSettings])

        let on = ProtectionReducer.reduce(&state, .toggleProtection)
        #expect(state.phase == .protecting)
        #expect(kinds(on).contains(.showOverlay))
        #expect(kinds(on).first == .startObserving)
    }

    @Test(arguments: [
        (AppEvent.windowMinimizedChanged(true), ProtectionPhase.suspended(.minimized)),
        (.whatsAppHiddenChanged(isHidden: true), .suspended(.appHidden)),
        (.windowOnActiveSpaceChanged(false), .suspended(.otherSpace)),
        (.screenLockChanged(isLocked: true), .suspended(.screenLocked)),
        (.systemSleepChanged(isAsleep: true), .suspended(.systemAsleep)),
        (.permissionChanged(trusted: false), .needsPermission),
        (.windowClosed, .waitingForWindow),
    ])
    func eventsThatStopProtectionHideOverlay(event: AppEvent, expected: ProtectionPhase) {
        var state = protectingState()
        let effects = ProtectionReducer.reduce(&state, event)
        #expect(state.phase == expected)
        #expect(effects.contains(.hideOverlay))
        #expect(state.coverage == nil)
    }

    @Test func resumingProtectionAlwaysRequestsFreshDetection() {
        var state = protectingState()
        _ = ProtectionReducer.reduce(&state, .layoutDetected(Fixtures.snapshot(generation: state.generation)))
        _ = ProtectionReducer.reduce(&state, .windowMinimizedChanged(true))
        let effects = ProtectionReducer.reduce(&state, .windowMinimizedChanged(false))
        #expect(kinds(effects) == [.applyCoverage, .setOverlayLevel, .showOverlay, .setInputMonitoring, .requestDetection])
    }

    @Test func wakeRebuildsObserversAndRedetects() {
        var state = protectingState()
        _ = ProtectionReducer.reduce(&state, .systemSleepChanged(isAsleep: true))
        let effects = ProtectionReducer.reduce(&state, .systemSleepChanged(isAsleep: false))
        #expect(kinds(effects).prefix(2) == [.stopObserving, .startObserving])
        #expect(effects.last == .requestDetection(state.generation, hint: .fullScan, after: .milliseconds(500)))
    }

    @Test func failuresBackOffThenEnterDegradedModeOnce() {
        var state = protectingState()
        var delays: [Duration] = []
        for _ in 0..<(ProtectionReducer.degradedThreshold - 1) {
            let effects = ProtectionReducer.reduce(&state, .detectionFailed(state.generation, .unsupportedLayout))
            if case .requestDetection(_, _, let after)? = effects.last { delays.append(after) }
        }
        #expect(delays == [.milliseconds(250), .seconds(1), .seconds(4), .seconds(4)])

        let fifth = ProtectionReducer.reduce(&state, .detectionFailed(state.generation, .unsupportedLayout))
        #expect(fifth == [.noticeDegradedMode])
        #expect(state.coverage?.tier == .windowHeuristic)

        let sixth = ProtectionReducer.reduce(&state, .detectionFailed(state.generation, .unsupportedLayout))
        #expect(!sixth.contains(.noticeDegradedMode))
    }

    @Test func settingsSideEffects() {
        var state = protectingState()
        var s = state.settings
        s.launchAtLogin = true
        s.toggleShortcut = nil
        s.targets.names = true
        let effects = ProtectionReducer.reduce(&state, .settingsChanged(s))
        #expect(kinds(effects) == [.persistSettings, .setLoginItem, .registerHotKey])
        #expect(ProtectionReducer.reduce(&state, .settingsChanged(s)).isEmpty)
    }

    @Test func autoEnableOnLaunchTurnsProtectionBackOn() {
        var s = PrivacySettings()
        s.protectionEnabled = false
        var state = CoreState(settings: s)
        let effects = ProtectionReducer.reduce(&state, .appStarted(accessibilityTrusted: true))
        #expect(state.settings.protectionEnabled)
        #expect(kinds(effects).contains(.persistSettings))
    }

    @Test func relaunchWithNewPIDDropsOldWindow() {
        var state = protectingState()
        let effects = ProtectionReducer.reduce(&state, .whatsAppLaunched(pid: 9999, isActive: true, isHidden: false))
        #expect(state.phase == .waitingForWindow)
        #expect(effects.prefix(2) == [.stopObserving, .startObserving(pid: 9999)])
        #expect(effects.contains(.hideOverlay))
    }
}
