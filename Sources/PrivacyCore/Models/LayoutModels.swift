import CoreGraphics

/// Monotonic token used to discard detection results that were started before the latest layout change.
public struct Generation: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let value: UInt64

    public init(_ value: UInt64 = 0) { self.value = value }

    public func next() -> Generation { Generation(value &+ 1) }

    public static func < (lhs: Generation, rhs: Generation) -> Bool { lhs.value < rhs.value }

    public var description: String { "gen\(value)" }
}

public struct TrackedWindow: Equatable, Sendable {
    public var windowID: CGWindowID
    public var frame: AXRect
    public var isFullScreen: Bool

    public init(windowID: CGWindowID, frame: AXRect, isFullScreen: Bool = false) {
        self.windowID = windowID
        self.frame = frame
        self.isFullScreen = isFullScreen
    }
}

public enum DetectionConfidence: Int, Comparable, Sendable, CaseIterable {
    case none = 0, low, medium, high

    public static func < (lhs: DetectionConfidence, rhs: DetectionConfidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum StrategyID: String, Sendable, CaseIterable {
    case axHierarchy, knownLayout, geometryHeuristic
}

public enum DetectionFailure: String, Error, Sendable, CaseIterable {
    case permissionDenied, timeout, windowUnavailable, unsupportedLayout, elementInvalidated
}

/// Geometry of one visible chat row. Deliberately has no field that can hold message text.
public struct ChatRowLayout: Equatable, Sendable {
    /// 0 = topmost visible row.
    public var slot: Int
    public var frame: AXRect
    public var avatarFrame: AXRect?
    public var nameFrame: AXRect?
    public var previewFrame: AXRect?
    public var timestampFrame: AXRect?

    public init(
        slot: Int,
        frame: AXRect,
        avatarFrame: AXRect? = nil,
        nameFrame: AXRect? = nil,
        previewFrame: AXRect? = nil,
        timestampFrame: AXRect? = nil
    ) {
        self.slot = slot
        self.frame = frame
        self.avatarFrame = avatarFrame
        self.nameFrame = nameFrame
        self.previewFrame = previewFrame
        self.timestampFrame = timestampFrame
    }

    func translated(dx: CGFloat, dy: CGFloat) -> ChatRowLayout {
        ChatRowLayout(
            slot: slot,
            frame: frame.offsetBy(dx: dx, dy: dy),
            avatarFrame: avatarFrame?.offsetBy(dx: dx, dy: dy),
            nameFrame: nameFrame?.offsetBy(dx: dx, dy: dy),
            previewFrame: previewFrame?.offsetBy(dx: dx, dy: dy),
            timestampFrame: timestampFrame?.offsetBy(dx: dx, dy: dy)
        )
    }
}

public struct SidebarLayout: Equatable, Sendable {
    public var frame: AXRect
    /// Scrollable chat-list area below the header / search field.
    public var listViewport: AXRect
    public var rows: [ChatRowLayout]

    public init(frame: AXRect, listViewport: AXRect, rows: [ChatRowLayout]) {
        self.frame = frame
        self.listViewport = listViewport
        self.rows = rows
    }

    public func translated(dx: CGFloat, dy: CGFloat) -> SidebarLayout {
        SidebarLayout(
            frame: frame.offsetBy(dx: dx, dy: dy),
            listViewport: listViewport.offsetBy(dx: dx, dy: dy),
            rows: rows.map { $0.translated(dx: dx, dy: dy) }
        )
    }

    /// Re-anchors a sidebar measured in `oldWindow` onto `newWindow`.
    /// Moves translate exactly. Size changes keep the top-left anchor and the bottom inset;
    /// row geometry is then stale and must not be used for precise coverage.
    public func rebased(from oldWindow: AXRect, to newWindow: AXRect) -> SidebarLayout {
        var result = translated(dx: newWindow.minX - oldWindow.minX, dy: newWindow.minY - oldWindow.minY)
        guard oldWindow.size != newWindow.size else { return result }

        func stretch(_ rect: AXRect, original: AXRect) -> AXRect {
            let bottomInset = oldWindow.maxY - original.maxY
            let maxWidth = max(0, newWindow.maxX - rect.minX)
            return AXRect(
                x: rect.minX,
                y: rect.minY,
                width: min(rect.width, maxWidth),
                height: max(0, newWindow.maxY - bottomInset - rect.minY)
            )
        }
        result.frame = stretch(result.frame, original: frame)
        result.listViewport = stretch(result.listViewport, original: listViewport)
        return result
    }
}

public struct LayoutSnapshot: Equatable, Sendable {
    public let generation: Generation
    /// Window frame the layout was measured against.
    public let window: AXRect
    public let sidebar: SidebarLayout?
    public let confidence: DetectionConfidence
    public let strategy: StrategyID
    public let durationMs: Int

    public init(
        generation: Generation,
        window: AXRect,
        sidebar: SidebarLayout?,
        confidence: DetectionConfidence,
        strategy: StrategyID,
        durationMs: Int = 0
    ) {
        self.generation = generation
        self.window = window
        self.sidebar = sidebar
        self.confidence = confidence
        self.strategy = strategy
        self.durationMs = durationMs
    }
}

// MARK: - Blur regions

public enum RegionKind: String, Hashable, Sendable, CaseIterable {
    case preview, name, timestamp, avatar, rowBand, column, windowHeuristic
}

/// Stable across re-detections so a hovered region does not flicker when regions are rebuilt.
public struct RegionID: Hashable, Sendable {
    public var slot: Int
    public var kind: RegionKind

    public init(slot: Int, kind: RegionKind) {
        self.slot = slot
        self.kind = kind
    }
}

public struct BlurRegion: Identifiable, Equatable, Sendable {
    public let id: RegionID
    public var frame: AXRect
    public var isRevealed: Bool

    public init(id: RegionID, frame: AXRect, isRevealed: Bool = false) {
        self.id = id
        self.frame = frame
        self.isRevealed = isRevealed
    }
}

public enum CoverageTier: String, Sendable, CaseIterable {
    /// Per-row preview (and optional name/timestamp/avatar) rects.
    case precise
    /// Per-row text band.
    case rowBand
    /// Whole chat-list column.
    case column
    /// Left portion of the window estimated from window geometry alone.
    case windowHeuristic
}

public struct Coverage: Equatable, Sendable {
    public var tier: CoverageTier
    /// Frame the overlay window should occupy.
    public var overlayFrame: AXRect
    public var regions: [BlurRegion]

    public init(tier: CoverageTier, overlayFrame: AXRect, regions: [BlurRegion]) {
        self.tier = tier
        self.overlayFrame = overlayFrame
        self.regions = regions
    }
}
