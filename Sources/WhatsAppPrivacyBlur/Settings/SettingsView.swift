import PrivacyCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            BlurSettingsTab(model: model)
                .tabItem { Label("Blur", systemImage: "drop.halffull") }
            RevealSettingsTab(model: model)
                .tabItem { Label("Reveal", systemImage: "eye") }
            AdvancedSettingsTab(model: model)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettingsTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable privacy blur automatically", isOn: model.binding(\.enableAutomaticallyOnLaunch))
                Toggle("Launch at login", isOn: model.binding(\.launchAtLogin))
                    .disabled(model.loginItemStatus == .unavailable)
                if let note = loginItemNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Protect previews", selection: model.binding(\.protectionScope)) {
                    ForEach(ProtectionScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                LabeledContent("Toggle protection shortcut") {
                    Text(model.settings.toggleShortcut?.displayString ?? "None")
                        .monospaced()
                        .accessibilityLabel(model.settings.toggleShortcut == nil ? "No shortcut" : "Shortcut \(model.settings.toggleShortcut!.displayString)")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var loginItemNote: String? {
        switch model.loginItemStatus {
        case .unavailable: "Available when running the installed app."
        case .requiresApproval: "Approve WhatsApp Privacy Blur in System Settings → General → Login Items."
        case .enabled, .disabled: nil
        }
    }
}

private struct BlurSettingsTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Blur") {
                Toggle("Message previews", isOn: model.binding(\.targets.previews))
                Toggle("Contact names", isOn: model.binding(\.targets.names))
                Toggle("Timestamps", isOn: model.binding(\.targets.timestamps))
                Toggle("Profile pictures", isOn: model.binding(\.targets.avatars))
            }

            Section("Appearance") {
                Picker("Style", selection: model.binding(\.blurStyle)) {
                    ForEach(BlurStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                Slider(value: model.binding(\.intensity), in: 0...1) {
                    Text("Blur intensity")
                } minimumValueLabel: {
                    Text("Low")
                } maximumValueLabel: {
                    Text("High")
                }
                .accessibilityValue(IntensityPreset(nearest: model.settings.intensity).title)
                Picker("Overlay appearance", selection: model.binding(\.overlayAppearance)) {
                    ForEach(AppearanceOverride.allCases, id: \.self) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct RevealSettingsTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Picker("Reveal method", selection: model.binding(\.revealMethod)) {
                ForEach(RevealMethod.allCases, id: \.self) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.radioGroup)

            Picker("Reveal timeout", selection: model.binding(\.revealTimeout)) {
                ForEach(RevealTimeout.choices, id: \.self) { timeout in
                    Text(timeout.title).tag(timeout)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(model.settings.revealMethod == .disabled)

            Picker("Reveal area", selection: model.binding(\.revealScope)) {
                ForEach(RevealScope.allCases, id: \.self) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .disabled(model.settings.revealMethod == .disabled)
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettingsTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Use fallback sidebar blur", isOn: model.binding(\.forceFallback))
                Toggle("Show debug overlay", isOn: model.binding(\.showDebugOverlay))
                Toggle("Enable diagnostic logging", isOn: model.binding(\.diagnosticLogging))
            } footer: {
                Text("Diagnostics contain only geometry and state — never message content, names or numbers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings to Defaults", role: .destructive) {
                    model.resetSettings()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Titles

extension ProtectionScope {
    var title: String {
        switch self {
        case .whileWhatsAppVisible: "Whenever WhatsApp is visible"
        case .whileWhatsAppActive: "Only while WhatsApp is active"
        }
    }
}

extension BlurStyle {
    var title: String {
        switch self {
        case .material: "Frosted material"
        case .solid: "Solid mask"
        }
    }
}

extension AppearanceOverride {
    var title: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

extension RevealMethod {
    var title: String {
        switch self {
        case .hover: "Hover"
        case .click: "Click"
        case .hoverAndClick: "Hover + Click"
        case .optionHover: "Hover while holding ⌥"
        case .disabled: "Disabled"
        }
    }
}

extension RevealTimeout {
    var title: String {
        switch self {
        case .untilPointerLeaves: "Until mouse leaves"
        case .seconds(let seconds): "\(seconds) seconds"
        }
    }
}

extension RevealScope {
    var title: String {
        switch self {
        case .previewOnly: "Message preview only"
        case .wholeRow: "Whole chat row"
        }
    }
}
