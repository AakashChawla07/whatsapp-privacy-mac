import CoreGraphics
@testable import PrivacyCore

enum Fixtures {
    static let window = AXRect(x: 100, y: 80, width: 1400, height: 900)
    static let pid: pid_t = 4242
    static let windowID: CGWindowID = 77

    static var trackedWindow: TrackedWindow { TrackedWindow(windowID: windowID, frame: window) }

    /// A plausible sidebar with `rowCount` 72pt rows starting below a 112pt header.
    static func sidebar(in window: AXRect = window, rowCount: Int = 8, previews: Bool = true) -> SidebarLayout {
        let frame = AXRect(x: window.minX, y: window.minY + 28, width: 380, height: window.height - 28)
        let viewport = AXRect(x: window.minX, y: window.minY + 140, width: 380, height: window.height - 140)
        let rows = (0..<rowCount).map { slot -> ChatRowLayout in
            let rowFrame = AXRect(x: viewport.minX, y: viewport.minY + CGFloat(slot) * 72, width: 380, height: 72)
            return ChatRowLayout(
                slot: slot,
                frame: rowFrame,
                avatarFrame: AXRect(x: rowFrame.minX + 12, y: rowFrame.minY + 12, width: 48, height: 48),
                nameFrame: AXRect(x: rowFrame.minX + 72, y: rowFrame.minY + 14, width: 200, height: 20),
                previewFrame: previews ? AXRect(x: rowFrame.minX + 72, y: rowFrame.minY + 38, width: 280, height: 18) : nil,
                timestampFrame: AXRect(x: rowFrame.maxX - 70, y: rowFrame.minY + 14, width: 56, height: 16)
            )
        }
        return SidebarLayout(frame: frame, listViewport: viewport, rows: rows)
    }

    static func snapshot(
        generation: Generation,
        window: AXRect = window,
        confidence: DetectionConfidence = .high,
        sidebar: SidebarLayout? = nil
    ) -> LayoutSnapshot {
        LayoutSnapshot(
            generation: generation,
            window: window,
            sidebar: sidebar ?? Fixtures.sidebar(in: window),
            confidence: confidence,
            strategy: .axHierarchy
        )
    }
}

extension Array where Element == BlurRegion {
    /// True when every point of `rect` lies inside at least one region (checked on a sample grid).
    func covers(_ rect: AXRect, step: CGFloat = 2) -> Bool {
        var y = rect.minY + 0.5
        while y < rect.maxY {
            var x = rect.minX + 0.5
            while x < rect.maxX {
                let point = AXPoint(x: x, y: y)
                if !contains(where: { $0.frame.contains(point) }) { return false }
                x += step
            }
            y += step
        }
        return true
    }
}
