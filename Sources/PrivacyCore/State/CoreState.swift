import CoreGraphics
import Foundation

public enum SuspendReason: String, Sendable, CaseIterable {
    case systemAsleep, screenLocked, appHidden, minimized, otherSpace, inactiveScope
}

public enum ProtectionPhase: Equatable, Sendable {
    case launching
    case disabled
    case needsPermission
    case waitingForWhatsApp
    case waitingForWindow
    case suspended(SuspendReason)
    case protecting

    public var isProtecting: Bool { self == .protecting }

    /// Content-free name, safe for logging.
    public enum Tag: String, Sendable, CaseIterable {
        case launching, disabled, needsPermission, waitingForWhatsApp, waitingForWindow, suspended, protecting
    }

    public var tag: Tag {
        switch self {
        case .launching: .launching
        case .disabled: .disabled
        case .needsPermission: .needsPermission
        case .waitingForWhatsApp: .waitingForWhatsApp
        case .waitingForWindow: .waitingForWindow
        case .suspended: .suspended
        case .protecting: .protecting
        }
    }
}

public struct TargetAppState: Equatable, Sendable {
    public var pid: pid_t
    public var isActive: Bool
    public var isHidden: Bool

    public init(pid: pid_t, isActive: Bool, isHidden: Bool) {
        self.pid = pid
        self.isActive = isActive
        self.isHidden = isHidden
    }
}

public struct WindowState: Equatable, Sendable {
    public var tracked: TrackedWindow
    public var isMinimized: Bool
    public var isOnActiveSpace: Bool

    public init(tracked: TrackedWindow, isMinimized: Bool = false, isOnActiveSpace: Bool = true) {
        self.tracked = tracked
        self.isMinimized = isMinimized
        self.isOnActiveSpace = isOnActiveSpace
    }
}

/// Facts about the world. The protection phase and all overlay effects are derived from these
/// by `ProtectionReducer`, so there is no hand-maintained transition table to drift out of sync.
public struct CoreState: Equatable, Sendable {
    public var hasStarted = false
    public var settings: PrivacySettings
    public var accessibilityTrusted = false

    public var whatsApp: TargetAppState?
    public var window: WindowState?
    public var isSystemAsleep = false
    public var isScreenLocked = false

    public var generation = Generation()
    /// True while current regions may be stale; coverage is widened to the column until refined.
    public var layoutInvalidated = true
    public var latestSnapshot: LayoutSnapshot?
    public var lastSidebarSnapshot: LayoutSnapshot?

    /// Last coverage/level sent to the overlay (nil while not protecting).
    public var coverage: Coverage?
    public var overlayLevel: OverlayLevelPolicy?

    public var consecutiveDetectionFailures = 0
    public var degradedNoticeShown = false

    public var coverageProfile: CoverageProfile

    public init(settings: PrivacySettings = PrivacySettings(), coverageProfile: CoverageProfile = .standard) {
        self.settings = settings
        self.coverageProfile = coverageProfile
    }

    public var phase: ProtectionPhase {
        guard hasStarted else { return .launching }
        guard settings.protectionEnabled else { return .disabled }
        guard accessibilityTrusted else { return .needsPermission }
        guard let whatsApp else { return .waitingForWhatsApp }
        guard let window else { return .waitingForWindow }
        if isSystemAsleep { return .suspended(.systemAsleep) }
        if isScreenLocked { return .suspended(.screenLocked) }
        if whatsApp.isHidden { return .suspended(.appHidden) }
        if window.isMinimized { return .suspended(.minimized) }
        if !window.isOnActiveSpace { return .suspended(.otherSpace) }
        if settings.protectionScope == .whileWhatsAppActive, !whatsApp.isActive { return .suspended(.inactiveScope) }
        return .protecting
    }

    /// PID whose accessibility notifications should currently be observed.
    var observedPID: pid_t? {
        guard hasStarted, settings.protectionEnabled, accessibilityTrusted else { return nil }
        return whatsApp?.pid
    }
}
