import Foundation

/// Pure state transition function: `(state, event) -> effects`.
///
/// Each event updates facts in `CoreState`; overlay, observation and level effects are then derived by
/// diffing the phase and planned coverage before and after the update.
public enum ProtectionReducer {
    /// Consecutive failed or low-confidence detections before the degraded-mode notice (§52).
    public static let degradedThreshold = 5
    public static let resizeDetectionDelay: Duration = .milliseconds(80)

    public static func reduce(_ state: inout CoreState, _ event: AppEvent) -> [Effect] {
        let before = state
        var concealing = false
        var restartObserver = false
        var detection: Effect?
        var trailing: [Effect] = []

        func invalidate() {
            state.generation = state.generation.next()
            state.layoutInvalidated = true
        }

        func clearWindow() {
            state.window = nil
            state.latestSnapshot = nil
            state.lastSidebarSnapshot = nil
            invalidate()
        }

        func apply(settings newSettings: PrivacySettings) {
            let old = state.settings
            guard newSettings != old else { return }
            state.settings = newSettings
            trailing.append(.persistSettings(newSettings))
            if newSettings.launchAtLogin != old.launchAtLogin {
                trailing.append(.setLoginItem(enabled: newSettings.launchAtLogin))
            }
            if newSettings.toggleShortcut != old.toggleShortcut {
                trailing.append(.registerHotKey(newSettings.toggleShortcut))
            }
        }

        func recordDetectionOutcome(success: Bool) {
            state.consecutiveDetectionFailures = success ? 0 : state.consecutiveDetectionFailures + 1
            if state.consecutiveDetectionFailures >= degradedThreshold, !state.degradedNoticeShown {
                state.degradedNoticeShown = true
                trailing.append(.noticeDegradedMode)
            }
        }

        switch event {
        case .appStarted(let trusted):
            guard !state.hasStarted else { return [] }
            state.hasStarted = true
            state.accessibilityTrusted = trusted
            if state.settings.enableAutomaticallyOnLaunch, !state.settings.protectionEnabled {
                var enabled = state.settings
                enabled.protectionEnabled = true
                apply(settings: enabled)
            }
            trailing.append(.registerHotKey(state.settings.toggleShortcut))
            if !trusted { trailing.append(.showOnboarding) }

        case .settingsChanged(let newSettings):
            apply(settings: newSettings)

        case .toggleProtection:
            var toggled = state.settings
            toggled.protectionEnabled.toggle()
            apply(settings: toggled)

        case .permissionChanged(let trusted):
            guard trusted != state.accessibilityTrusted else { return [] }
            state.accessibilityTrusted = trusted
            invalidate()

        case .whatsAppLaunched(let pid, let isActive, let isHidden):
            if state.whatsApp?.pid != pid { clearWindow() }
            state.whatsApp = TargetAppState(pid: pid, isActive: isActive, isHidden: isHidden)

        case .whatsAppTerminated(let pid):
            guard state.whatsApp?.pid == pid else { return [] }
            state.whatsApp = nil
            clearWindow()

        case .whatsAppActivationChanged(let isActive):
            state.whatsApp?.isActive = isActive

        case .whatsAppHiddenChanged(let isHidden):
            state.whatsApp?.isHidden = isHidden

        case .windowAvailable(let tracked):
            guard state.whatsApp != nil else { return [] }
            if let existing = state.window, existing.tracked.windowID == tracked.windowID {
                let resized = existing.tracked.frame.size != tracked.frame.size
                state.window?.tracked = tracked
                if resized { invalidate() }
            } else {
                clearWindow()
                state.window = WindowState(tracked: tracked)
            }

        case .windowClosed:
            guard state.window != nil else { return [] }
            clearWindow()

        case .windowMoved(let frame), .windowResized(let frame):
            guard let current = state.window else { return [] }
            state.window?.tracked.frame = frame
            if current.tracked.frame.size != frame.size {
                invalidate()
                concealing = true
                detection = .requestDetection(state.generation, hint: .fastPath, after: resizeDetectionDelay)
            }

        case .windowMinimizedChanged(let minimized):
            state.window?.isMinimized = minimized

        case .windowOnActiveSpaceChanged(let visible):
            state.window?.isOnActiveSpace = visible

        case .layoutInvalidated(let reason):
            invalidate()
            concealing = true
            detection = .requestDetection(state.generation, hint: .fastPath, after: reason.detectionDelay)

        case .layoutDetected(let snapshot):
            guard snapshot.generation == state.generation, state.window != nil else { return [] }
            state.latestSnapshot = snapshot
            if snapshot.sidebar != nil { state.lastSidebarSnapshot = snapshot }
            state.layoutInvalidated = false
            recordDetectionOutcome(success: snapshot.confidence >= .medium)

        case .detectionFailed(let generation, _):
            guard generation == state.generation, state.window != nil else { return [] }
            recordDetectionOutcome(success: false)
            if state.consecutiveDetectionFailures < degradedThreshold {
                detection = .requestDetection(
                    generation, hint: .fullScan, after: retryDelay(forFailures: state.consecutiveDetectionFailures)
                )
            }

        case .scrollActivity(.active):
            invalidate()
            concealing = true

        case .scrollActivity(.ended):
            guard state.layoutInvalidated else { return [] }
            detection = .requestDetection(state.generation, hint: .fastPath, after: .zero)

        case .systemSleepChanged(let asleep):
            state.isSystemAsleep = asleep
            if !asleep {
                // Observers can be stale after wake; rebuild them and re-detect from scratch.
                restartObserver = true
                invalidate()
                detection = .requestDetection(state.generation, hint: .fullScan, after: InvalidationReason.systemWoke.detectionDelay)
            }

        case .screenLockChanged(let locked):
            state.isScreenLocked = locked

        case .displaysChanged:
            invalidate()
            concealing = true
            detection = .requestDetection(state.generation, hint: .fastPath, after: InvalidationReason.displaysChanged.detectionDelay)
        }

        return derivedEffects(
            before: before,
            state: &state,
            concealing: concealing,
            restartObserver: restartObserver,
            detection: detection,
            trailing: trailing
        )
    }

    public static func retryDelay(forFailures failures: Int) -> Duration {
        switch failures {
        case ...1: .milliseconds(250)
        case 2: .seconds(1)
        default: .seconds(4)
        }
    }

    // MARK: - Derivation

    private static func derivedEffects(
        before: CoreState,
        state: inout CoreState,
        concealing: Bool,
        restartObserver: Bool,
        detection: Effect?,
        trailing: [Effect]
    ) -> [Effect] {
        var effects: [Effect] = []

        // Observation
        let oldPID = before.observedPID
        let newPID = state.observedPID
        if oldPID != newPID || (restartObserver && newPID != nil) {
            if oldPID != nil { effects.append(.stopObserving) }
            if let newPID { effects.append(.startObserving(pid: newPID)) }
        }

        let wasProtecting = before.phase.isProtecting
        let isProtecting = state.phase.isProtecting

        if wasProtecting, !isProtecting {
            effects.append(.setInputMonitoring(enabled: false))
            effects.append(.hideOverlay)
            state.coverage = nil
            state.overlayLevel = nil
        }

        if isProtecting, let window = state.window, let app = state.whatsApp {
            if concealing, wasProtecting { effects.append(.concealAll) }

            let coverage = CoveragePlanner.plan(
                latest: state.latestSnapshot,
                lastWithSidebar: state.lastSidebarSnapshot,
                window: window.tracked.frame,
                invalidated: state.layoutInvalidated,
                settings: state.settings,
                profile: state.coverageProfile
            )
            if coverage != state.coverage {
                state.coverage = coverage
                effects.append(.applyCoverage(coverage))
            }

            let level: OverlayLevelPolicy = app.isActive ? .floating : .aboveWindow(window.tracked.windowID)
            if level != state.overlayLevel {
                state.overlayLevel = level
                effects.append(.setOverlayLevel(level))
            }

            if !wasProtecting {
                effects.append(.showOverlay)
                effects.append(.setInputMonitoring(enabled: true))
            }

            if let detection {
                effects.append(detection)
            } else if !wasProtecting {
                // Always refresh on (re)entering protection; the layout may have changed while suspended.
                let hint: DetectionHint = state.lastSidebarSnapshot == nil ? .fullScan : .fastPath
                effects.append(.requestDetection(state.generation, hint: hint, after: .zero))
            }
        }

        effects.append(contentsOf: trailing)
        return effects
    }
}
