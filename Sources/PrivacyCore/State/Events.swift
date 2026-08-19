import CoreGraphics
import Foundation

public enum ScrollPhase: Sendable, Equatable {
    /// Scroll (or momentum) delta observed inside the sidebar.
    case active
    /// No scroll activity for the quiet period.
    case ended
}

public enum InvalidationReason: String, Sendable, CaseIterable {
    case treeChanged, rowsChanged, typing, displaysChanged, systemWoke

    /// Debounce before re-detecting. Coverage is widened immediately regardless.
    public var detectionDelay: Duration {
        switch self {
        case .treeChanged, .rowsChanged: .milliseconds(80)
        case .typing, .displaysChanged: .milliseconds(150)
        case .systemWoke: .milliseconds(500)
        }
    }
}

public enum DetectionHint: Sendable, Equatable {
    /// Re-query children of the cached chat-list anchor.
    case fastPath
    /// Walk the window's accessibility tree from the top.
    case fullScan
}

public enum AppEvent: Sendable, Equatable {
    // Lifecycle & configuration
    case appStarted(accessibilityTrusted: Bool)
    case settingsChanged(PrivacySettings)
    case toggleProtection
    case permissionChanged(trusted: Bool)

    // Target application
    case whatsAppLaunched(pid: pid_t, isActive: Bool, isHidden: Bool)
    case whatsAppTerminated(pid: pid_t)
    case whatsAppActivationChanged(isActive: Bool)
    case whatsAppHiddenChanged(isHidden: Bool)

    // Window
    case windowAvailable(TrackedWindow)
    case windowClosed
    case windowMoved(AXRect)
    case windowResized(AXRect)
    case windowMinimizedChanged(Bool)
    case windowOnActiveSpaceChanged(Bool)

    // Layout
    case layoutInvalidated(InvalidationReason)
    case layoutDetected(LayoutSnapshot)
    case detectionFailed(Generation, DetectionFailure)
    case scrollActivity(ScrollPhase)

    // System
    case systemSleepChanged(isAsleep: Bool)
    case screenLockChanged(isLocked: Bool)
    case displaysChanged
}

public enum OverlayLevelPolicy: Equatable, Sendable {
    /// Above everything at normal level; used while WhatsApp is frontmost.
    case floating
    /// Normal level, ordered directly above WhatsApp's window; used while WhatsApp is in the background.
    case aboveWindow(CGWindowID)
}

public enum Effect: Equatable, Sendable {
    case startObserving(pid: pid_t)
    case stopObserving
    /// Executors must cancel any pending (not yet started) request when a new one arrives: latest wins.
    case requestDetection(Generation, hint: DetectionHint, after: Duration)
    case showOverlay
    case hideOverlay
    case setOverlayLevel(OverlayLevelPolicy)
    case applyCoverage(Coverage)
    /// Instantly re-blur any revealed region.
    case concealAll
    case setInputMonitoring(enabled: Bool)
    case showOnboarding
    case noticeDegradedMode
    case persistSettings(PrivacySettings)
    case setLoginItem(enabled: Bool)
    case registerHotKey(KeyCombo?)

    /// Content-free name, safe for logging.
    public enum Kind: String, Sendable, CaseIterable {
        case startObserving, stopObserving, requestDetection, showOverlay, hideOverlay, setOverlayLevel
        case applyCoverage, concealAll, setInputMonitoring, showOnboarding, noticeDegradedMode
        case persistSettings, setLoginItem, registerHotKey
    }

    public var kind: Kind {
        switch self {
        case .startObserving: .startObserving
        case .stopObserving: .stopObserving
        case .requestDetection: .requestDetection
        case .showOverlay: .showOverlay
        case .hideOverlay: .hideOverlay
        case .setOverlayLevel: .setOverlayLevel
        case .applyCoverage: .applyCoverage
        case .concealAll: .concealAll
        case .setInputMonitoring: .setInputMonitoring
        case .showOnboarding: .showOnboarding
        case .noticeDegradedMode: .noticeDegradedMode
        case .persistSettings: .persistSettings
        case .setLoginItem: .setLoginItem
        case .registerHotKey: .registerHotKey
        }
    }
}
