// ax-dump — Phase 0 spike S1.
// Records the structure of WhatsApp's main window accessibility tree: roles, subroles, frames,
// supported attribute/action names. It never reads titles, values, descriptions or any text content.

import AppKit
import ApplicationServices
import Foundation
import SpikeSupport

let usage = """
usage: swift run ax-dump [--label NAME] [--out FILE] [--depth N] [--max-nodes N] [--rows N]

  --label NAME     tag for this capture, e.g. light, dark, narrow (default: dump)
  --out FILE       JSON output path (default: spikes-output/ax-dump-<label>-<time>.json)
  --depth N        maximum tree depth (default 40)
  --max-nodes N    stop after N elements (default 6000)
  --rows N         rows to detail in the summary (default 3)
"""

let args = Arguments()
if args.flag("--help") || args.flag("-h") {
    print(usage)
    exit(0)
}

AXTrust.require(tool: "ax-dump")
let app = WhatsApp.requireRunning()
let appElement = AXApp.element(for: app)
guard let window = AXApp.primaryWindow(of: appElement), let windowFrame = window.frame else {
    fail("Could not find WhatsApp's main window. Make sure it is open and not minimized.")
}

let label = args.value("--label") ?? "dump"
let maxDepth = args.int("--depth", default: 40)
let maxNodes = args.int("--max-nodes", default: 6000)
let detailRows = args.int("--rows", default: 3)

// MARK: - Model

struct Node: Codable {
    var role: String
    var subrole: String?
    var identifier: String?
    /// Window-relative [x, y, width, height] in points.
    var frame: [Double]?
    var childCount: Int
    var truncated: Bool?
    var children: [Node]

    var rect: CGRect? {
        guard let f = frame, f.count == 4 else { return nil }
        return CGRect(x: f[0], y: f[1], width: f[2], height: f[3])
    }
}

struct Dump: Codable {
    var tool = "ax-dump"
    var label: String
    var whatsAppBundleIdentifier: String
    var whatsAppVersion: String
    var macOSVersion: String
    var systemAppearance: String
    var capturedAt: String
    var windowCount: Int
    var windowSubrole: String?
    var windowFrame: [Double]
    var screens: [[Double]]
    var nodeCount: Int
    var deepestLevel: Int
    var durationMs: Int
    var attributesByRole: [String: [String]]
    var actionsByRole: [String: [String]]
    var root: Node
}

func rounded(_ rect: CGRect) -> [Double] {
    [rect.minX, rect.minY, rect.width, rect.height].map { (value: CGFloat) -> Double in
        Double((value * 10).rounded() / 10)
    }
}

// MARK: - Walk

var nodeCount = 0
var deepest = 0
var attributesByRole: [String: Set<String>] = [:]
var actionsByRole: [String: Set<String>] = [:]

func walk(_ element: AXUIElement, depth: Int) -> Node {
    nodeCount += 1
    deepest = max(deepest, depth)

    let role = element.role ?? "?"
    attributesByRole[role, default: []].formUnion(element.attributeNames)
    actionsByRole[role, default: []].formUnion(element.actionNames)

    let kids = element.children
    let relative = element.frame.map { rounded($0.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)) }
    var node = Node(
        role: role,
        subrole: element.subrole,
        identifier: element.redactedIdentifier,
        frame: relative,
        childCount: kids.count,
        truncated: nil,
        children: []
    )

    guard depth < maxDepth else {
        if !kids.isEmpty { node.truncated = true }
        return node
    }
    for kid in kids {
        guard nodeCount < maxNodes else {
            node.truncated = true
            break
        }
        node.children.append(walk(kid, depth: depth + 1))
    }
    return node
}

note("Walking WhatsApp window accessibility tree…")
let started = Date()
let root = walk(window, depth: 0)
let durationMs = Int(Date().timeIntervalSince(started) * 1000)

let appearance: String = {
    let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
    return (global?["AppleInterfaceStyle"] as? String) == "Dark" ? "dark" : "light"
}()

let dump = Dump(
    label: label,
    whatsAppBundleIdentifier: app.bundleIdentifier ?? "?",
    whatsAppVersion: WhatsApp.version(of: app),
    macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
    systemAppearance: appearance,
    capturedAt: ISO8601DateFormatter().string(from: Date()),
    windowCount: appElement.windows.count,
    windowSubrole: window.subrole,
    windowFrame: rounded(windowFrame),
    screens: NSScreen.screens.map { rounded($0.frame) + [Double($0.backingScaleFactor)] },
    nodeCount: nodeCount,
    deepestLevel: deepest,
    durationMs: durationMs,
    attributesByRole: attributesByRole.mapValues { $0.sorted() },
    actionsByRole: actionsByRole.mapValues { $0.sorted() },
    root: root
)

// MARK: - Write JSON

let outputPath: String = {
    if let out = args.value("--out") { return out }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "spikes-output/ax-dump-\(label)-\(formatter.string(from: Date())).json"
}()

do {
    let url = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(dump).write(to: url)
} catch {
    fail("Could not write \(outputPath): \(error.localizedDescription)")
}

// MARK: - Summary

print("""
ax-dump [\(label)]
  WhatsApp \(dump.whatsAppBundleIdentifier) \(dump.whatsAppVersion) · macOS \(dump.macOSVersion) · system \(appearance)
  Window \(fmt(windowFrame)) subrole=\(window.subrole ?? "-") · windows=\(dump.windowCount)
  Elements \(nodeCount) · depth \(deepest) · \(durationMs) ms\(nodeCount >= maxNodes ? " · HIT --max-nodes LIMIT" : "")
""")

// Role histogram
var roleCounts: [String: Int] = [:]
func countRoles(_ node: Node) {
    roleCounts[node.role + (node.subrole.map { "/" + $0 } ?? ""), default: 0] += 1
    node.children.forEach(countRoles)
}
countRoles(root)
print("\nRoles (top 20):")
for (role, count) in roleCounts.sorted(by: { $0.value > $1.value }).prefix(20) {
    print(String(format: "  %5d  %@", count, role))
}

// Candidate lists: containers with ≥3 children aligned in one column with similar heights.
struct Candidate {
    let path: String
    let node: Node
    let rows: [Node]
    let medianHeight: Double
}

var candidates: [Candidate] = []

func findCandidates(_ node: Node, path: String) {
    let framed = node.children.filter { ($0.rect?.height ?? 0) > 8 && ($0.rect?.width ?? 0) > 40 }
    let groups = Dictionary(grouping: framed) { child -> String in
        let r = child.rect!
        return "\(Int((r.minX / 4).rounded()))-\(Int((r.width / 4).rounded()))"
    }
    if let best = groups.values.max(by: { $0.count < $1.count }), best.count >= 3 {
        let heights = best.map { $0.rect!.height }.sorted()
        if let minH = heights.first, let maxH = heights.last, maxH / minH <= 1.6 {
            let sorted = best.sorted { $0.rect!.minY < $1.rect!.minY }
            candidates.append(Candidate(path: path, node: node, rows: sorted, medianHeight: heights[heights.count / 2]))
        }
    }
    for (index, child) in node.children.enumerated() {
        findCandidates(child, path: path + " > " + child.role + "[\(index)]")
    }
}
findCandidates(root, path: root.role)

func rel(_ r: CGRect?) -> String {
    guard let r else { return "(no frame)" }
    return String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", r.minX, r.minY, r.width, r.height)
}

let windowWidth = windowFrame.width
let ranked = candidates.sorted {
    // Prefer lists starting in the left third of the window, then more rows.
    let lLeft = ($0.rows.first?.rect?.minX ?? .infinity) < windowWidth / 3
    let rLeft = ($1.rows.first?.rect?.minX ?? .infinity) < windowWidth / 3
    return lLeft != rLeft ? lLeft : $0.rows.count > $1.rows.count
}

print("\nRow-list candidates (\(candidates.count) found, top 6):")
if ranked.isEmpty {
    print("  none — the chat list may not be exposed as separate row elements")
}
for (i, candidate) in ranked.prefix(6).enumerated() {
    let first = candidate.rows.first?.rect
    print("""
      #\(i + 1) \(candidate.node.role)\(candidate.node.subrole.map { "/" + $0 } ?? "") \(rel(candidate.node.rect))
         rows=\(candidate.rows.count) rowRole=\(candidate.rows.first?.role ?? "?") rowHeight≈\(Int(candidate.medianHeight)) firstRow: \(rel(first))
         path: \(candidate.path)
    """)
}

// Detail rows of the best candidate: descendant elements with frames relative to the row.
if let best = ranked.first {
    print("\nBest candidate #1 — descendants of the first \(detailRows) rows (frames relative to row):")
    func describe(_ node: Node, row: CGRect, depth: Int) {
        guard depth <= 6 else { return }
        let indent = String(repeating: "  ", count: depth + 2)
        let relFrame = node.rect.map { $0.offsetBy(dx: -row.minX, dy: -row.minY) }
        print("\(indent)\(node.role)\(node.subrole.map { "/" + $0 } ?? "")\(node.identifier.map { " id=" + $0 } ?? "") \(rel(relFrame))")
        node.children.forEach { describe($0, row: row, depth: depth + 1) }
    }
    for (index, row) in best.rows.prefix(detailRows).enumerated() {
        guard let rowRect = row.rect else { continue }
        print("  row \(index): \(row.role) \(rel(rowRect))")
        row.children.forEach { describe($0, row: rowRect, depth: 0) }
    }

    // How consistent are rows? Count text / image descendants per row.
    func countDescendants(_ node: Node, roles: Set<String>) -> Int {
        node.children.reduce(0) { $0 + (roles.contains($1.role) ? 1 : 0) + countDescendants($1, roles: roles) }
    }
    var textHistogram: [Int: Int] = [:]
    var imageHistogram: [Int: Int] = [:]
    for row in best.rows {
        textHistogram[countDescendants(row, roles: ["AXStaticText", "AXTextField", "AXTextArea"]), default: 0] += 1
        imageHistogram[countDescendants(row, roles: ["AXImage"]), default: 0] += 1
    }
    print("\n  text elements per row: " + textHistogram.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value) rows" }.joined(separator: ", "))
    print("  image elements per row: " + imageHistogram.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value) rows" }.joined(separator: ", "))
}

print("\nSaved: \(outputPath)")
