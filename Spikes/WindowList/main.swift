// window-list — Phase 0 spike S5.
// Shows what CGWindowList exposes about WhatsApp's windows *without* Screen Recording permission:
// window number, layer, bounds, alpha, on-screen state, z-order and occluding windows.
// Window titles are never read; only whether the title key is present is reported.

import AppKit
import ApplicationServices
import Foundation
import SpikeSupport

let usage = """
usage: swift run window-list [--watch] [--interval SECONDS]

  --watch          re-print whenever WhatsApp's window state changes (Ctrl+C to stop).
                   Try: minimize, switch Space, full screen, hide (⌘H), cover with another window.
  --interval S     polling interval for --watch (default 0.5; spike-only polling)
"""

let args = Arguments()
if args.flag("--help") || args.flag("-h") {
    print(usage)
    exit(0)
}

let whatsApp = WhatsApp.requireRunning()
let pid = whatsApp.processIdentifier
let axTrusted = AXIsProcessTrusted()
let screenRecording = CGPreflightScreenCaptureAccess()

print("""
window-list · WhatsApp \(WhatsApp.version(of: whatsApp)) pid \(pid)
  Screen Recording granted to this terminal: \(screenRecording ? "YES (results may show more than the app will get)" : "no (good — this is the app's situation)")
  Accessibility trusted: \(axTrusted ? "yes" : "no (AX window matching skipped)")
""")

func snapshot() -> String {
    let all = WindowInfo.list(onScreenOnly: false)
    let onScreen = WindowInfo.list(onScreenOnly: true)
    let mine = all.filter { $0.ownerPID == pid }

    var lines: [String] = []
    lines.append("WhatsApp windows (all \(mine.count)):")
    for w in mine {
        lines.append(String(
            format: "  #%-6u layer=%-3d onScreen=%@ alpha=%.2f bounds=%@ titleKey=%@",
            w.number, w.layer, w.isOnScreen ? "yes" : "no ", w.alpha, fmt(w.bounds), w.titleKeyPresent ? "present" : "withheld"
        ))
    }

    // AX main window ↔ CGWindowID matching
    var mainNumber: CGWindowID?
    if axTrusted {
        let appElement = AXApp.element(for: whatsApp)
        if let window = AXApp.primaryWindow(of: appElement), let frame = window.frame {
            let minimized = window.bool("AXMinimized") ?? false
            let fullScreen = window.bool("AXFullScreen") ?? false
            if let match = WindowInfo.match(pid: pid, frame: frame, in: all) {
                mainNumber = match.number
                lines.append("AX main window \(fmt(frame)) minimized=\(minimized) fullScreen=\(fullScreen) → matched CGWindowID #\(match.number)")
            } else {
                lines.append("AX main window \(fmt(frame)) minimized=\(minimized) fullScreen=\(fullScreen) → NO CGWindowList match")
            }
        } else {
            lines.append("AX main window: not available (closed or minimized?)")
        }
    }

    // Z-order among on-screen windows (index 0 = frontmost)
    let target = mainNumber.flatMap { number in onScreen.firstIndex { $0.number == number } }
        ?? onScreen.firstIndex { $0.ownerPID == pid && $0.layer == 0 }
    if let index = target {
        let window = onScreen[index]
        let above = onScreen[..<index].filter { $0.bounds.intersects(window.bounds) && $0.alpha > 0 }
        lines.append("Z-order: WhatsApp window #\(window.number) is on-screen at index \(index); \(above.count) overlapping window(s) above it:")
        for w in above.prefix(12) {
            let overlap = w.bounds.intersection(window.bounds)
            lines.append(String(
                format: "    #%-6u layer=%-4d %@ overlap=%@", w.number, w.layer,
                w.ownerName.padding(toLength: 22, withPad: " ", startingAt: 0), fmt(overlap)
            ))
        }
    } else {
        lines.append("Z-order: WhatsApp main window is NOT in the on-screen list (minimized, hidden, or on another Space)")
    }
    return lines.joined(separator: "\n")
}

if !args.flag("--watch") {
    print(snapshot())
    exit(0)
}

let interval = Double(args.value("--interval") ?? "") ?? 0.5
var previous = ""
signal(SIGINT, SIG_DFL)
while true {
    let current = snapshot()
    if current != previous {
        print("\n\(stamp())\n\(current)")
        previous = current
    }
    Thread.sleep(forTimeInterval: interval)
}
