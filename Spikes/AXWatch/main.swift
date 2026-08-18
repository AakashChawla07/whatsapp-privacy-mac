// ax-watch — Phase 0 spike S4.
// Logs which accessibility notifications WhatsApp emits (and how often) while you drag, resize,
// scroll the chat list, type in search, switch chats, minimize, etc. Optionally correlates with
// global scroll / drag mouse activity. Reads roles and frames only — never text content.

import AppKit
import ApplicationServices
import Foundation
import SpikeSupport

let usage = """
usage: swift run ax-watch [--quiet-frames] [--no-mouse] [--only NAME[,NAME…]]

  Press Ctrl+C to stop and print the summary.

  --quiet-frames   do not print element frames (fewer AX calls per notification)
  --no-mouse       do not monitor global scroll / drag activity
  --only LIST      print only these notifications (all are still counted)
"""

let args = Arguments()
if args.flag("--help") || args.flag("-h") {
    print(usage)
    exit(0)
}

AXTrust.require(tool: "ax-watch")
let whatsApp = WhatsApp.requireRunning()
let pid = whatsApp.processIdentifier
let appElement = AXApp.element(for: whatsApp, timeout: 0.25)
let printFrames = !args.flag("--quiet-frames")
let onlyNotifications = args.value("--only").map { Set($0.split(separator: ",").map(String.init)) }

let appNotifications = [
    "AXApplicationActivated", "AXApplicationDeactivated", "AXApplicationHidden", "AXApplicationShown",
    "AXWindowCreated", "AXMainWindowChanged", "AXFocusedWindowChanged", "AXFocusedUIElementChanged",
    "AXCreated", "AXUIElementDestroyed", "AXValueChanged", "AXLayoutChanged", "AXRowCountChanged",
    "AXSelectedRowsChanged", "AXSelectedChildrenChanged", "AXSelectedChildrenMoved", "AXRowExpanded",
    "AXRowCollapsed", "AXElementBusyChanged", "AXTitleChanged",
]
// Geometry / minimize notifications are registered on the window only, so they are not counted twice.
let windowNotifications = ["AXMoved", "AXResized", "AXWindowMiniaturized", "AXWindowDeminiaturized", "AXUIElementDestroyed"]

// MARK: - Stats

final class Stats {
    var counts: [String: Int] = [:]
    var lastTime: [String: Date] = [:]
    var maxGapWhileBursting: [String: TimeInterval] = [:]
    var intervals: [String: [TimeInterval]] = [:]
    var lastNonGeometryNotification: Date?

    var scrollEvents = 0
    var dragEvents = 0
    var scrollBursts = 0
    var scrollBurstsWithoutAX = 0
    var scrollBurstStart: Date?
    var lastScroll: Date?

    func record(_ name: String, at date: Date) {
        counts[name, default: 0] += 1
        if let last = lastTime[name] {
            let gap = date.timeIntervalSince(last)
            if gap < 0.5 { intervals[name, default: []].append(gap) }
        }
        lastTime[name] = date
        if name != "AXMoved" && name != "AXResized" { lastNonGeometryNotification = date }
    }
}

let stats = Stats()

// MARK: - Observer

/// Set once the observer is created below; declared first so the handlers can reference it.
var observer: AXObserver!

func handle(element: AXUIElement, notification: String) {
    let now = Date()
    stats.record(notification, at: now)
    if let only = onlyNotifications, !only.contains(notification) { return }

    var line = "\(stamp(now))  \(notification.padding(toLength: 28, withPad: " ", startingAt: 0))"
    line += " \((element.role ?? "?") + (element.subrole.map { "/" + $0 } ?? ""))"
    if printFrames { line += "  \(fmt(element.frame))" }
    if notification == "AXMainWindowChanged" || notification == "AXFocusedWindowChanged" || notification == "AXWindowCreated" {
        registerWindow()
    }
    print(line)
}

var createdObserver: AXObserver?
let callback: AXObserverCallback = { _, element, notification, _ in
    handle(element: element, notification: notification as String)
}

guard AXObserverCreate(pid, callback, &createdObserver) == .success, let created = createdObserver else {
    fail("AXObserverCreate failed.")
}
observer = created
CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

var supported: [String] = []
var unsupported: [String] = []
for name in appNotifications {
    let result = AXObserverAddNotification(observer, appElement, name as CFString, nil)
    if result == .success || result == .notificationAlreadyRegistered {
        supported.append(name)
    } else {
        unsupported.append("\(name)(\(result.rawValue))")
    }
}

var registeredWindow: AXUIElement?
func registerWindow() {
    guard let window = AXApp.primaryWindow(of: appElement) else { return }
    if let current = registeredWindow, CFEqual(current, window) { return }
    if let current = registeredWindow {
        windowNotifications.forEach { AXObserverRemoveNotification(observer, current, $0 as CFString) }
    }
    var ok: [String] = []
    for name in windowNotifications where AXObserverAddNotification(observer, window, name as CFString, nil) == .success {
        ok.append(name)
    }
    registeredWindow = window
    print("\(stamp())  [registered main window \(fmt(window.frame)) for: \(ok.joined(separator: ", "))]")
}

print("""
ax-watch · WhatsApp \(WhatsApp.version(of: whatsApp)) pid \(pid)
  app-level notifications accepted: \(supported.joined(separator: ", "))
  rejected: \(unsupported.isEmpty ? "none" : unsupported.joined(separator: ", "))
""")
registerWindow()
print("""

Now, in WhatsApp: drag the window, resize it, scroll the chat list, type in search, switch chats,
receive a message, minimize/restore, switch to another app and back. Press Ctrl+C for the summary.

""")

// MARK: - Mouse correlation

let nsApp = NSApplication.shared
nsApp.setActivationPolicy(.prohibited)

if !args.flag("--no-mouse") {
    NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { _ in
        let now = Date()
        stats.scrollEvents += 1
        if let last = stats.lastScroll, now.timeIntervalSince(last) < 0.15 {
            stats.lastScroll = now
            return
        }
        // New burst
        stats.lastScroll = now
        stats.scrollBursts += 1
        stats.scrollBurstStart = now
        print("\(stamp(now))  ── scroll burst #\(stats.scrollBursts) started (mouse over \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") frontmost)")
        let burst = stats.scrollBursts
        func checkBurstEnd() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard let last = stats.lastScroll else { return }
                if Date().timeIntervalSince(last) < 0.15 {
                    checkBurstEnd()
                    return
                }
                // Burst ended; wait 300 ms more for late AX notifications.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let start = stats.scrollBurstStart ?? last
                    let sawAX = (stats.lastNonGeometryNotification.map { $0 >= start.addingTimeInterval(-0.05) }) ?? false
                    if !sawAX { stats.scrollBurstsWithoutAX += 1 }
                    print("\(stamp())  ── scroll burst #\(burst) ended · non-geometry AX notification during burst: \(sawAX ? "YES" : "NO")")
                }
            }
        }
        checkBurstEnd()
    }
    NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { _ in
        stats.dragEvents += 1
    }
    NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
        print("\(stamp())  ── mouse \(event.type == .leftMouseDown ? "down" : "up")")
    }
}

// MARK: - Summary on Ctrl+C

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
    print("\n══ Summary (\(String(format: "%.1f", Date().timeIntervalSince(startTime))) s) ══")
    if stats.counts.isEmpty { print("  no accessibility notifications received") }
    for (name, count) in stats.counts.sorted(by: { $0.value > $1.value }) {
        let gaps = (stats.intervals[name] ?? []).sorted()
        let gapText = gaps.isEmpty ? "" : String(
            format: "  burst interval median %.0f ms, max %.0f ms",
            gaps[gaps.count / 2] * 1000, (gaps.last ?? 0) * 1000
        )
        print("  \(name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(String(format: "%5d", count))\(gapText)")
    }
    print("""
      mouse: scroll events \(stats.scrollEvents) in \(stats.scrollBursts) bursts \
    (\(stats.scrollBurstsWithoutAX) bursts with NO non-geometry AX notification) · drag events \(stats.dragEvents)

    Interpretation hints:
      • AXMoved/AXResized with ~16 ms burst intervals  → live drag tracking works without sampling.
      • AXMoved count ≈ number of drags               → fires only at drag end; live sampler needed.
      • Scroll bursts with NO AX notification         → scroll must be detected from mouse events.
    """)
    exit(0)
}
sigint.resume()

nsApp.run()
