import AppKit
import ApplicationServices
import Foundation

// MARK: - Console

public func note(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

public func fail(_ message: String) -> Never {
    note("error: " + message)
    exit(1)
}

public struct Arguments {
    private let args: [String]

    public init(_ args: [String] = Array(CommandLine.arguments.dropFirst())) {
        self.args = args
    }

    public func flag(_ name: String) -> Bool { args.contains(name) }

    public func value(_ name: String) -> String? {
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    public func int(_ name: String, default fallback: Int) -> Int {
        value(name).flatMap(Int.init) ?? fallback
    }
}

public let startTime = Date()

/// Seconds since the tool started, formatted like "+12.345s".
public func stamp(_ date: Date = Date()) -> String {
    String(format: "+%7.3fs", date.timeIntervalSince(startTime))
}

public func fmt(_ rect: CGRect?) -> String {
    guard let r = rect else { return "(no frame)" }
    return String(format: "(%.0f, %.0f, %.0f×%.0f)", r.minX, r.minY, r.width, r.height)
}

// MARK: - WhatsApp

public enum WhatsApp {
    public static let bundleIdentifiers = ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]

    public static func running() -> NSRunningApplication? {
        for id in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { !$0.isTerminated }) {
                return app
            }
        }
        return nil
    }

    public static func requireRunning() -> NSRunningApplication {
        guard let app = running() else { fail("WhatsApp is not running. Open WhatsApp and try again.") }
        return app
    }

    public static func version(of app: NSRunningApplication) -> String {
        guard let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary else { return "unknown" }
        return (info["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    public static func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }
}

// MARK: - Accessibility permission

public enum AXTrust {
    public static func require(tool: String) {
        if AXIsProcessTrusted() { return }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        fail("""
        \(tool) needs Accessibility access for the app running it (Terminal, iTerm, VS Code, …).
               System Settings → Privacy & Security → Accessibility → enable your terminal app,
               then quit and reopen the terminal and run the command again.
        """)
    }
}

// MARK: - AX helpers (geometry and structure only — never text content)

public extension AXUIElement {
    private func copy(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    var role: String? { copy("AXRole") as? String }
    var subrole: String? { copy("AXSubrole") as? String }

    /// Developer-set identifier. Redacted if it looks like it could embed user data
    /// (digits runs such as phone numbers, or '@' such as JIDs / e-mail).
    var redactedIdentifier: String? {
        guard let id = copy("AXIdentifier") as? String, !id.isEmpty else { return nil }
        let longDigitRun = id.range(of: #"\d{5,}"#, options: .regularExpression) != nil
        if longDigitRun || id.contains("@") || id.count > 80 {
            return "<redacted len=\(id.count)>"
        }
        return id
    }

    var frame: CGRect? {
        guard let positionRef = copy("AXPosition"), let sizeRef = copy("AXSize"),
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    var children: [AXUIElement] { (copy("AXChildren") as? [AXUIElement]) ?? [] }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = copy(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func bool(_ attribute: String) -> Bool? {
        (copy(attribute) as? NSNumber)?.boolValue
    }

    var windows: [AXUIElement] { (copy("AXWindows") as? [AXUIElement]) ?? [] }

    var attributeNames: [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(self, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    var actionNames: [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(self, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    var pid: pid_t {
        var value: pid_t = 0
        AXUIElementGetPid(self, &value)
        return value
    }
}

public enum AXApp {
    public static func element(for app: NSRunningApplication, timeout: Float = 0.5) -> AXUIElement {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    /// AXMainWindow → AXFocusedWindow → largest standard window.
    public static func primaryWindow(of appElement: AXUIElement) -> AXUIElement? {
        if let main = appElement.element("AXMainWindow") { return main }
        if let focused = appElement.element("AXFocusedWindow") { return focused }
        return appElement.windows
            .filter { $0.subrole == "AXStandardWindow" }
            .max { ($0.frame?.width ?? 0) * ($0.frame?.height ?? 0) < ($1.frame?.width ?? 0) * ($1.frame?.height ?? 0) }
    }
}

// MARK: - CGWindowList

public struct WindowInfo {
    public let number: CGWindowID
    public let ownerPID: pid_t
    public let ownerName: String
    public let layer: Int
    public let bounds: CGRect
    public let alpha: Double
    public let isOnScreen: Bool
    /// Whether the title key is present at all (it is withheld without Screen Recording). Value is never read.
    public let titleKeyPresent: Bool

    public static func list(onScreenOnly: Bool) -> [WindowInfo] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return WindowInfo(
                number: number,
                ownerPID: pid,
                ownerName: (entry[kCGWindowOwnerName as String] as? String) ?? "?",
                layer: (entry[kCGWindowLayer as String] as? Int) ?? 0,
                bounds: bounds,
                alpha: (entry[kCGWindowAlpha as String] as? Double) ?? 1,
                isOnScreen: (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                titleKeyPresent: entry[kCGWindowName as String] != nil
            )
        }
    }

    /// The layer-0 window of `pid` whose bounds match `frame` (AX and CG share top-left global coordinates).
    public static func match(pid: pid_t, frame: CGRect, in windows: [WindowInfo], tolerance: CGFloat = 1) -> WindowInfo? {
        windows.first {
            $0.ownerPID == pid && $0.layer == 0
                && abs($0.bounds.minX - frame.minX) <= tolerance && abs($0.bounds.minY - frame.minY) <= tolerance
                && abs($0.bounds.width - frame.width) <= tolerance && abs($0.bounds.height - frame.height) <= tolerance
        }
    }
}

// MARK: - Coordinates

public enum Coordinates {
    /// AX/CG (top-left origin) → AppKit (bottom-left origin of the primary display).
    public static func toAppKit(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
