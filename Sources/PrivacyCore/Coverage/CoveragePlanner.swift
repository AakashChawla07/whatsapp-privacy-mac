import CoreGraphics

/// Generic layout constants the planner needs. Supplied by the target-app adapter;
/// contains no app-specific names.
public struct CoverageProfile: Equatable, Sendable {
    /// Outset applied to every region so descenders and antialiasing stay covered.
    public var regionPadding: CGFloat
    /// Width of the avatar column at the leading edge of each row.
    public var avatarGutter: CGFloat
    public var fallbackSidebarRatio: CGFloat
    public var fallbackSidebarMinWidth: CGFloat
    public var fallbackSidebarMaxWidth: CGFloat
    public var titleBarHeight: CGFloat

    public init(
        regionPadding: CGFloat = 2,
        avatarGutter: CGFloat = 64,
        fallbackSidebarRatio: CGFloat = 0.32,
        fallbackSidebarMinWidth: CGFloat = 280,
        fallbackSidebarMaxWidth: CGFloat = 520,
        titleBarHeight: CGFloat = 28
    ) {
        self.regionPadding = regionPadding
        self.avatarGutter = avatarGutter
        self.fallbackSidebarRatio = fallbackSidebarRatio
        self.fallbackSidebarMinWidth = fallbackSidebarMinWidth
        self.fallbackSidebarMaxWidth = fallbackSidebarMaxWidth
        self.titleBarHeight = titleBarHeight
    }

    public static let standard = CoverageProfile()
}

/// Turns the latest layout knowledge into blur regions.
///
/// Invariant (privacy first): whenever precise geometry cannot be trusted — the layout is invalidated,
/// the window size changed since measurement, confidence is low, or fallback is forced — the result
/// covers the whole chat-list column (or a window-based estimate), never less.
public enum CoveragePlanner {
    public static func plan(
        latest: LayoutSnapshot?,
        lastWithSidebar: LayoutSnapshot?,
        window: AXRect,
        invalidated: Bool,
        settings: PrivacySettings,
        profile: CoverageProfile = .standard
    ) -> Coverage {
        let targets = settings.targets

        if !invalidated, !settings.forceFallback,
           let latest, latest.window.size == window.size,
           latest.confidence >= .medium,
           let measured = latest.sidebar {
            let sidebar = measured.rebased(from: latest.window, to: window)
            let tier: CoverageTier = latest.confidence == .high ? .precise : .rowBand
            return rowCoverage(sidebar: sidebar, tier: tier, window: window, targets: targets, profile: profile)
        }

        if let source = latest?.sidebar != nil ? latest : lastWithSidebar, let measured = source.sidebar {
            let sidebar = measured.rebased(from: source.window, to: window)
            if let viewport = sidebar.listViewport.intersection(window) {
                let overlay = overlayFrame(for: sidebar.frame.union(viewport), window: window, profile: profile)
                let regions = columnRegions(in: viewport, kind: .column, targets: targets, profile: profile)
                return Coverage(tier: .column, overlayFrame: overlay, regions: regions)
            }
        }

        return windowHeuristicCoverage(window: window, targets: targets, profile: profile)
    }

    // MARK: - Tiers

    private static func rowCoverage(
        sidebar: SidebarLayout,
        tier: CoverageTier,
        window: AXRect,
        targets: PrivacyTargets,
        profile: CoverageProfile
    ) -> Coverage {
        var regions: [BlurRegion] = []
        var seen = Set<RegionID>()

        func add(_ kind: RegionKind, slot: Int, _ frame: AXRect) {
            let id = RegionID(slot: slot, kind: kind)
            guard !seen.contains(id),
                  let clipped = frame.insetBy(dx: -profile.regionPadding, dy: -profile.regionPadding)
                      .intersection(sidebar.listViewport)
            else { return }
            seen.insert(id)
            regions.append(BlurRegion(id: id, frame: clipped))
        }

        func textBand(_ row: ChatRowLayout) -> AXRect {
            let leading = targets.avatars ? row.frame.minX : row.frame.minX + profile.avatarGutter
            return AXRect(x: leading, y: row.frame.minY, width: max(0, row.frame.maxX - leading), height: row.frame.height)
        }

        for row in sidebar.rows {
            if tier == .rowBand {
                if targets.anyText {
                    add(.rowBand, slot: row.slot, textBand(row))
                } else if targets.avatars {
                    add(.avatar, slot: row.slot, row.avatarFrame ?? gutter(of: row, profile: profile))
                }
                continue
            }

            // Precise: a missing sub-element falls back to the row's text band rather than exposing it.
            if targets.previews { add(row.previewFrame.map { _ in .preview } ?? .rowBand, slot: row.slot, row.previewFrame ?? textBand(row)) }
            if targets.names { add(row.nameFrame.map { _ in .name } ?? .rowBand, slot: row.slot, row.nameFrame ?? textBand(row)) }
            if targets.timestamps { add(row.timestampFrame.map { _ in .timestamp } ?? .rowBand, slot: row.slot, row.timestampFrame ?? textBand(row)) }
            if targets.avatars { add(.avatar, slot: row.slot, row.avatarFrame ?? gutter(of: row, profile: profile)) }
        }

        let overlay = overlayFrame(for: sidebar.frame.union(sidebar.listViewport), window: window, profile: profile)
        return Coverage(tier: tier, overlayFrame: overlay, regions: regions)
    }

    private static func windowHeuristicCoverage(window: AXRect, targets: PrivacyTargets, profile: CoverageProfile) -> Coverage {
        let estimatedWidth = min(
            window.width,
            min(profile.fallbackSidebarMaxWidth, max(profile.fallbackSidebarMinWidth, window.width * profile.fallbackSidebarRatio))
        )
        let area = AXRect(
            x: window.minX,
            y: window.minY + profile.titleBarHeight,
            width: estimatedWidth,
            height: max(0, window.height - profile.titleBarHeight)
        )
        guard !area.isEmpty else {
            return Coverage(tier: .windowHeuristic, overlayFrame: window, regions: [])
        }
        let regions = columnRegions(in: area, kind: .windowHeuristic, targets: targets, profile: profile)
        return Coverage(tier: .windowHeuristic, overlayFrame: area, regions: regions)
    }

    // MARK: - Helpers

    /// One region spanning the column: avatar gutter included only when avatars are a target,
    /// text area included when any text target is enabled.
    private static func columnRegions(in area: AXRect, kind: RegionKind, targets: PrivacyTargets, profile: CoverageProfile) -> [BlurRegion] {
        guard targets.any else { return [] }
        let gutterEnd = min(area.maxX, area.minX + profile.avatarGutter)
        let start = targets.avatars ? area.minX : gutterEnd
        let end = targets.anyText ? area.maxX : gutterEnd
        guard end > start else { return [] }
        let frame = AXRect(x: start, y: area.minY, width: end - start, height: area.height)
        return [BlurRegion(id: RegionID(slot: 0, kind: kind), frame: frame)]
    }

    private static func gutter(of row: ChatRowLayout, profile: CoverageProfile) -> AXRect {
        AXRect(x: row.frame.minX, y: row.frame.minY, width: min(profile.avatarGutter, row.frame.width), height: row.frame.height)
    }

    private static func overlayFrame(for area: AXRect, window: AXRect, profile: CoverageProfile) -> AXRect {
        let padded = area.insetBy(dx: -profile.regionPadding, dy: -profile.regionPadding)
        return padded.intersection(window) ?? area
    }
}
