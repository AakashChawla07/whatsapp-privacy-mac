import AppKit
import ApplicationServices
import PrivacyCore
import ServiceManagement

@MainActor
struct Dependencies {
    var settingsStore: any SettingsStore
    var permissions: any PermissionChecking
    var loginItems: any LoginItemManaging

    static func live() -> Dependencies {
        Dependencies(
            settingsStore: UserDefaultsSettingsStore(),
            permissions: AccessibilityPermissionService(),
            loginItems: LoginItemService()
        )
    }
}

// MARK: - Accessibility permission

@MainActor
protocol PermissionChecking {
    func isTrusted() -> Bool
    func openAccessibilitySettings()
}

/// Reads trust state only. Prompting and the onboarding flow arrive in Phase 2/7;
/// the app never attempts to bypass the permission (requirements §9).
struct AccessibilityPermissionService: PermissionChecking {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        guard let url = Self.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Launch at login

enum LoginItemStatus: Equatable, Sendable {
    case enabled, disabled, requiresApproval, unavailable
}

@MainActor
protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    /// Returns false when the system rejected the change.
    func setEnabled(_ enabled: Bool) -> Bool
}

/// Uses Apple's supported `SMAppService` login item (requirements §23).
/// Only works from a bundled, signed .app — `swift run` reports `.unavailable`.
struct LoginItemService: LoginItemManaging {
    private var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var status: LoginItemStatus {
        guard isBundled else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        guard isBundled else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
