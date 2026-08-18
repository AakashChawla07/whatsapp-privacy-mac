// blur-lab — Phase 0 spikes S2 (blur legibility) and S3 (window stacking).
//
// Places a click-through overlay over WhatsApp's sidebar area and a small control window to vary:
//   • style: native material blur / solid mask / tint only
//   • material and tint opacity (S2: find the weakest setting that makes previews unreadable)
//   • window level policy (S3: does the overlay stay directly above WhatsApp when apps switch?)
// Stacking is verified objectively via CGWindowList and logged on every change.
// Spike-only: follows WhatsApp by sampling its frame at 30 Hz; the real app will use AX notifications.

import AppKit
import ApplicationServices
import Foundation
import SpikeSupport

let args = Arguments()
if args.flag("--help") || args.flag("-h") {
    print("usage: swift run blur-lab   (close the control window or press Ctrl+C to quit)")
    exit(0)
}

AXTrust.require(tool: "blur-lab")
let whatsApp = WhatsApp.requireRunning()

enum Style: Int, CaseIterable {
    case material, solid, tintOnly
    var title: String { ["Material blur + tint", "Solid mask", "Tint only (no blur)"][rawValue] }
}

enum LevelMode: Int, CaseIterable {
    case hybrid, floating, aboveWindow, normalFront
    var title: String {
        [
            "Hybrid (floating when WA front, else above WA)",
            "Always .floating",
            "Always .normal + order above WA",
            ".normal, ordered front once",
        ][rawValue]
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Target/action glue for closures.
final class Action: NSObject {
    let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSControl) { handler(sender) }
}

final class Lab: NSObject, NSWindowDelegate {
    let app: NSRunningApplication
    let appElement: AXUIElement

    let overlay: OverlayPanel
    let effect = NSVisualEffectView()
    let tint = NSView()

    let materials: [(String, NSVisualEffectView.Material)] = [
        ("hudWindow", .hudWindow), ("popover", .popover), ("menu", .menu), ("sidebar", .sidebar),
        ("underWindowBackground", .underWindowBackground), ("fullScreenUI", .fullScreenUI),
        ("headerView", .headerView), ("sheet", .sheet), ("windowBackground", .windowBackground),
        ("contentBackground", .contentBackground), ("titlebar", .titlebar), ("toolTip", .toolTip),
    ]

    var style: Style = .material
    var materialIndex = 0
    var tintAlpha: Double = 0.35
    var levelMode: LevelMode = .hybrid
    var sidebarWidth: CGFloat = 380
    var topInset: CGFloat = 60
    var leftInset: CGFloat = 0
    var reapplyEveryFrame = false

    var controls: NSWindow!
    let statusLabel = NSTextField(labelWithString: "")
    var actions: [Action] = []

    var timer: Timer?
    var tickCount = 0
    var lastWindowFrame: CGRect?
    var whatsAppWindowNumber: CGWindowID?
    var lastStackState = ""
    var lastActivation: (name: String, at: Date)?

    init(app: NSRunningApplication) {
        self.app = app
        appElement = AXApp.element(for: app, timeout: 0.25)
        overlay = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()

        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.hidesOnDeactivate = false
        overlay.isReleasedWhenClosed = false
        overlay.animationBehavior = .none
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlay.setAccessibilityElement(false)

        let content = NSView()
        content.wantsLayer = true
        for view in [effect, tint] {
            view.wantsLayer = true
            view.autoresizingMask = [.width, .height]
            content.addSubview(view)
        }
        effect.blendingMode = .behindWindow
        effect.state = .active
        overlay.contentView = content
    }

    func start() {
        buildControls()
        applyStyle()
        tick()
        applyLevel(reason: "start")

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = activated?.localizedName ?? "?"
            self.lastActivation = (name, Date())
            print("\(stamp())  app activated: \(name)")
            self.applyLevel(reason: "activation")
        }
    }

    // MARK: Overlay

    func applyStyle() {
        effect.isHidden = style != .material
        effect.material = materials[materialIndex].1
        let alpha = style == .solid ? 1.0 : tintAlpha
        overlay.effectiveAppearance.performAsCurrentDrawingAppearance {
            tint.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(alpha).cgColor
        }
        updateStatus()
    }

    func applyLevel(reason: String) {
        let frontmost = WhatsApp.isFrontmost(app)
        let useFloating: Bool
        switch levelMode {
        case .hybrid: useFloating = frontmost
        case .floating: useFloating = true
        case .aboveWindow: useFloating = false
        case .normalFront:
            overlay.level = .normal
            overlay.orderFrontRegardless()
            return
        }
        if useFloating {
            overlay.level = .floating
            overlay.orderFrontRegardless()
        } else {
            overlay.level = .normal
            if let number = whatsAppWindowNumber {
                overlay.order(.above, relativeTo: Int(number))
            } else {
                overlay.orderFrontRegardless()
            }
        }
        if reason != "frame" {
            print("\(stamp())  level applied (\(reason)): \(useFloating ? ".floating" : ".normal above WA #\(whatsAppWindowNumber.map(String.init) ?? "?")")")
        }
    }

    func tick() {
        tickCount += 1
        guard let window = AXApp.primaryWindow(of: appElement), let frame = window.frame,
              !(window.bool("AXMinimized") ?? false)
        else {
            if overlay.isVisible {
                overlay.orderOut(nil)
                print("\(stamp())  WhatsApp window unavailable → overlay hidden")
            }
            return
        }

        if frame != lastWindowFrame {
            lastWindowFrame = frame
            whatsAppWindowNumber = WindowInfo.match(pid: app.processIdentifier, frame: frame, in: WindowInfo.list(onScreenOnly: false))?.number
        }

        let width = max(0, min(sidebarWidth, frame.width - leftInset))
        let area = CGRect(x: frame.minX + leftInset, y: frame.minY + topInset, width: width, height: max(0, frame.height - topInset))
        let target = Coordinates.toAppKit(area)
        if overlay.frame != target {
            overlay.setFrame(target, display: true)
        }
        if !overlay.isVisible {
            applyLevel(reason: "show")
        } else if reapplyEveryFrame {
            applyLevel(reason: "frame")
        }

        if tickCount % 6 == 0 { checkStacking(area: area) }
    }

    /// Objective S3 check: where is the overlay relative to WhatsApp's window in the on-screen z-order?
    func checkStacking(area: CGRect) {
        guard let waNumber = whatsAppWindowNumber else { return }
        let onScreen = WindowInfo.list(onScreenOnly: true)
        let overlayNumber = CGWindowID(overlay.windowNumber)
        guard let overlayIndex = onScreen.firstIndex(where: { $0.number == overlayNumber }) else { return }
        guard let waIndex = onScreen.firstIndex(where: { $0.number == waNumber }) else {
            report("WhatsApp window not on screen")
            return
        }

        let state: String
        if overlayIndex > waIndex {
            state = "✗ BELOW WhatsApp — previews EXPOSED"
        } else {
            let between = onScreen[(overlayIndex + 1)..<waIndex].filter {
                $0.ownerPID != app.processIdentifier && $0.alpha > 0 && $0.bounds.intersects(area)
            }
            state = between.isEmpty
                ? "✓ directly above WhatsApp"
                : "△ above WhatsApp but also covering \(between.count) other window(s): \(Set(between.map(\.ownerName)).sorted().joined(separator: ", "))"
        }
        report(state)
    }

    func report(_ state: String) {
        guard state != lastStackState else { return }
        lastStackState = state
        var suffix = ""
        if let activation = lastActivation {
            suffix = String(format: "  (%.0f ms after %@ activated)", Date().timeIntervalSince(activation.at) * 1000, activation.name)
        }
        print("\(stamp())  stacking: \(state)\(suffix)")
        updateStatus()
    }

    // MARK: Controls

    func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
        let action = Action(handler)
        actions.append(action)
        control.target = action
        control.action = #selector(Action.fire(_:))
    }

    func popup(_ titles: [String], selected: Int, _ handler: @escaping (Int) -> Void) -> NSPopUpButton {
        let button = NSPopUpButton()
        button.addItems(withTitles: titles)
        button.selectItem(at: selected)
        bind(button) { handler(($0 as! NSPopUpButton).indexOfSelectedItem) }
        return button
    }

    func slider(_ value: Double, _ range: ClosedRange<Double>, format: String, _ handler: @escaping (Double) -> Void) -> NSView {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let valueLabel = NSTextField(labelWithString: String(format: format, value))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        bind(slider) { control in
            valueLabel.stringValue = String(format: format, control.doubleValue)
            handler(control.doubleValue)
        }
        return NSStackView(views: [slider, valueLabel])
    }

    func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        return stack
    }

    func buildControls() {
        let styleButton = popup(Style.allCases.map(\.title), selected: style.rawValue) { [unowned self] in
            style = Style(rawValue: $0) ?? .material
            print("\(stamp())  style: \(style.title)")
            applyStyle()
        }
        let materialButton = popup(materials.map(\.0), selected: materialIndex) { [unowned self] in
            materialIndex = $0
            print("\(stamp())  material: \(materials[$0].0)")
            applyStyle()
        }
        let levelButton = popup(LevelMode.allCases.map(\.title), selected: levelMode.rawValue) { [unowned self] in
            levelMode = LevelMode(rawValue: $0) ?? .hybrid
            print("\(stamp())  level mode: \(levelMode.title)")
            applyLevel(reason: "mode change")
        }
        let reapply = NSButton(checkboxWithTitle: "Re-apply level every frame", target: nil, action: nil)
        bind(reapply) { [unowned self] in reapplyEveryFrame = ($0 as! NSButton).state == .on }
        let applyNow = NSButton(title: "Apply level now", target: nil, action: nil)
        bind(applyNow) { [unowned self] _ in applyLevel(reason: "button") }

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.preferredMaxLayoutWidth = 400

        let help = NSTextField(wrappingLabelWithString: """
        S2: adjust until previews are unreadable (check from ~1 m, light and dark). Note the weakest setting that works.
        S3: switch between WhatsApp and other apps / overlap windows; watch the stacking line here and in the terminal.
        """)
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        help.preferredMaxLayoutWidth = 400

        let stack = NSStackView(views: [
            row("Style", styleButton),
            row("Material", materialButton),
            row("Tint opacity", slider(tintAlpha, 0...1, format: "%.2f") { [unowned self] in tintAlpha = $0; applyStyle() }),
            row("Sidebar width", slider(Double(sidebarWidth), 120...800, format: "%.0f pt") { [unowned self] in sidebarWidth = $0; tick() }),
            row("Top inset", slider(Double(topInset), 0...250, format: "%.0f pt") { [unowned self] in topInset = $0; tick() }),
            row("Left inset", slider(Double(leftInset), 0...150, format: "%.0f pt") { [unowned self] in leftInset = $0; tick() }),
            row("Level", levelButton),
            row("", NSStackView(views: [reapply, applyNow])),
            statusLabel,
            help,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        controls = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        controls.title = "blur-lab — WhatsApp Privacy Blur spike"
        controls.contentView = stack
        controls.delegate = self
        controls.isReleasedWhenClosed = false
        controls.center()
        controls.makeKeyAndOrderFront(nil)
    }

    func updateStatus() {
        let material = style == .material ? materials[materialIndex].0 : "-"
        statusLabel.stringValue = """
        style=\(style.title) material=\(material) tint=\(String(format: "%.2f", style == .solid ? 1 : tintAlpha))
        stacking: \(lastStackState.isEmpty ? "checking…" : lastStackState)
        """
    }

    func windowWillClose(_ notification: Notification) {
        print("\(stamp())  final settings → style=\(style.title) material=\(materials[materialIndex].0) tint=\(String(format: "%.2f", tintAlpha))")
        NSApp.terminate(nil)
    }
}

let nsApp = NSApplication.shared
nsApp.setActivationPolicy(.accessory)
let lab = Lab(app: whatsApp)
lab.start()
nsApp.activate(ignoringOtherApps: true)
print("""
blur-lab · WhatsApp \(WhatsApp.version(of: whatsApp)) — overlay placed over the sidebar area.
Adjust the controls; close the control window (or Ctrl+C) to quit.
""")
nsApp.run()
