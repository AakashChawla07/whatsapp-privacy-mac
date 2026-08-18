import CoreGraphics

public struct ScreenInfo: Equatable, Sendable {
    public var frame: ScreenRect
    public var backingScaleFactor: CGFloat

    public init(frame: ScreenRect, backingScaleFactor: CGFloat) {
        self.frame = frame
        self.backingScaleFactor = backingScaleFactor
    }
}

/// The only place in the codebase that converts between coordinate spaces (requirements §25).
public struct CoordinateConverter: Equatable, Sendable {
    /// Height of the primary display (`NSScreen.screens[0]`, not `NSScreen.main`).
    public var primaryDisplayHeight: CGFloat
    /// All screens, primary first.
    public var screens: [ScreenInfo]

    public init(screens: [ScreenInfo]) {
        self.screens = screens
        self.primaryDisplayHeight = screens.first?.frame.height ?? 0
    }

    // MARK: AX <-> AppKit

    public func toAppKit(_ rect: AXRect) -> ScreenRect {
        ScreenRect(x: rect.minX, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public func toAX(_ rect: ScreenRect) -> AXRect {
        AXRect(x: rect.minX, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public func toAppKit(_ point: AXPoint) -> ScreenPoint {
        ScreenPoint(x: point.x, y: primaryDisplayHeight - point.y)
    }

    public func toAX(_ point: ScreenPoint) -> AXPoint {
        AXPoint(x: point.x, y: primaryDisplayHeight - point.y)
    }

    // MARK: Overlay-local

    /// Converts a global AX rect into the bottom-left-origin space of an overlay whose frame is `overlayFrame`.
    public func toOverlay(_ rect: AXRect, overlayFrame: AXRect) -> OverlayRect {
        OverlayRect(
            x: rect.minX - overlayFrame.minX,
            y: overlayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: Screens & pixel alignment

    /// The screen containing the rect's midpoint, else the screen with the largest overlap.
    public func screen(containing rect: AXRect) -> ScreenInfo? {
        let appKitRect = toAppKit(rect)
        let mid = CGPoint(x: appKitRect.midX, y: appKitRect.midY)
        if let hit = screens.first(where: { $0.frame.raw.contains(mid) }) {
            return hit
        }
        let best = screens.max { lhs, rhs in
            (lhs.frame.intersection(appKitRect)?.area ?? 0) < (rhs.frame.intersection(appKitRect)?.area ?? 0)
        }
        guard let best, (best.frame.intersection(appKitRect)?.area ?? 0) > 0 else { return nil }
        return best
    }

    /// Rounds outward to whole backing pixels so blur regions never leave a sub-pixel seam.
    public func pixelAligned(_ rect: ScreenRect, scale: CGFloat) -> ScreenRect {
        guard scale > 0, !rect.isEmpty else { return rect }
        let minX = (rect.minX * scale).rounded(.down) / scale
        let minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale
        let maxY = (rect.maxY * scale).rounded(.up) / scale
        return ScreenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func pixelAlignedAppKitRect(for rect: AXRect) -> ScreenRect {
        let scale = screen(containing: rect)?.backingScaleFactor ?? 1
        return pixelAligned(toAppKit(rect), scale: scale)
    }
}
