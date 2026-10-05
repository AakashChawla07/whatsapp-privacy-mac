import AppKit
import PrivacyCore
import SwiftUI

struct MenuBarContent: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("WhatsApp Privacy Blur")
        Text(model.statusText)

        Divider()

        Toggle("Privacy Protection", isOn: model.binding(\.protectionEnabled))
            .keyboardShortcut(model.settings.toggleShortcut)

        Toggle("Reveal on Hover", isOn: revealOnHover)

        Picker("Blur Intensity", selection: model.binding(\.intensityPreset)) {
            ForEach(IntensityPreset.allCases) { preset in
                Text(preset.title).tag(preset)
            }
        }

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit WhatsApp Privacy Blur") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var revealOnHover: Binding<Bool> {
        Binding(
            get: { model.settings.revealMethod.revealsOnHover },
            set: { model.binding(\.revealMethod).wrappedValue = $0 ? .hover : .disabled }
        )
    }
}

extension IntensityPreset {
    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

private extension View {
    /// Shows the configured global shortcut next to the menu item (the global hot key itself is registered separately).
    @ViewBuilder
    func keyboardShortcut(_ combo: KeyCombo?) -> some View {
        if let combo, let shortcut = combo.swiftUIShortcut {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}

private extension KeyCombo {
    var swiftUIShortcut: KeyboardShortcut? {
        guard let character = displayString.last, character.isLetter || character.isNumber else { return nil }
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(Character(character.lowercased())), modifiers: eventModifiers)
    }
}
