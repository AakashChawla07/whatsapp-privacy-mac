import AppKit
import SwiftUI

@main
struct WhatsAppPrivacyBlurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: appDelegate.model)
        } label: {
            Image(systemName: appDelegate.model.menuBarSymbol)
                .accessibilityLabel("WhatsApp Privacy Blur")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator
    var model: AppModel { coordinator.model }

    override init() {
        coordinator = AppCoordinator(dependencies: .live())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only, even when run unbundled via `swift run` (bundled builds also set LSUIElement).
        NSApp.setActivationPolicy(.accessory)
        coordinator.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        coordinator.refreshPermission()
    }
}
