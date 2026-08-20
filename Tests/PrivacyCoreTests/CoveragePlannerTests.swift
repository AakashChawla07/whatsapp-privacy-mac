import CoreGraphics
import Testing
@testable import PrivacyCore

@Suite("Coverage planner")
struct CoveragePlannerTests {
    let window = Fixtures.window
    let settings = PrivacySettings()

    @Test func noLayoutKnowledgeUsesWindowHeuristic() {
        let coverage = CoveragePlanner.plan(latest: nil, lastWithSidebar: nil, window: window, invalidated: true, settings: settings)
        #expect(coverage.tier == .windowHeuristic)
        #expect(coverage.regions.count == 1)
        let region = coverage.regions[0].frame
        #expect(region.minY == window.minY + 28)
        #expect(region.maxY == window.maxY)
        // 1400 × 0.32 = 448, inside [280, 520]; avatar gutter excluded by default.
        #expect(region.maxX == window.minX + 448)
        #expect(region.minX == window.minX + 64)
    }

    @Test func heuristicWidthIsClampedAndNeverWiderThanWindow() {
        let narrow = AXRect(x: 0, y: 0, width: 200, height: 600)
        let coverage = CoveragePlanner.plan(latest: nil, lastWithSidebar: nil, window: narrow, invalidated: true, settings: settings)
        #expect(coverage.overlayFrame.width == 200)
    }

    @Test func highConfidenceProducesOnePreviewRegionPerRow() {
        let snapshot = Fixtures.snapshot(generation: Generation(1))
        let coverage = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: window, invalidated: false, settings: settings)
        #expect(coverage.tier == .precise)
        #expect(coverage.regions.count == 8)
        #expect(coverage.regions.allSatisfy { $0.id.kind == .preview })
        for row in snapshot.sidebar!.rows {
            #expect(coverage.regions.covers(row.previewFrame!))
            // Name and timestamp stay readable by default.
            #expect(!coverage.regions.contains { $0.frame.intersects(row.nameFrame!.insetBy(dx: 0, dy: 3)) })
        }
    }

    @Test func optionalTargetsAddRegions() {
        var all = settings
        all.targets = PrivacyTargets(previews: true, names: true, timestamps: true, avatars: true)
        let snapshot = Fixtures.snapshot(generation: Generation(1))
        let coverage = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: window, invalidated: false, settings: all)
        #expect(coverage.regions.count == 8 * 4)
    }

    @Test func missingPreviewFrameFallsBackToRowBand() {
        let sidebar = Fixtures.sidebar(previews: false)
        let snapshot = Fixtures.snapshot(generation: Generation(1), sidebar: sidebar)
        let coverage = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: window, invalidated: false, settings: settings)
        #expect(coverage.regions.allSatisfy { $0.id.kind == .rowBand })
        #expect(coverage.regions.count == 8)
    }

    @Test func mediumConfidenceUsesRowBands() {
        let snapshot = Fixtures.snapshot(generation: Generation(1), confidence: .medium)
        let coverage = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: window, invalidated: false, settings: settings)
        #expect(coverage.tier == .rowBand)
        #expect(coverage.regions.count == 8)
    }

    @Test(arguments: [
        (DetectionConfidence.low, false, false),
        (DetectionConfidence.high, true, false),   // invalidated
        (DetectionConfidence.high, false, true),   // forced fallback
    ])
    func untrustedGeometryCoversWholeColumn(confidence: DetectionConfidence, invalidated: Bool, forceFallback: Bool) {
        var s = settings
        s.forceFallback = forceFallback
        let snapshot = Fixtures.snapshot(generation: Generation(1), confidence: confidence)
        let coverage = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: window, invalidated: invalidated, settings: s)
        #expect(coverage.tier == .column)
        #expect(coverage.regions.count == 1)
        let viewport = snapshot.sidebar!.listViewport
        #expect(coverage.regions[0].frame == AXRect(x: viewport.minX + 64, y: viewport.minY, width: viewport.width - 64, height: viewport.height))
    }

    @Test func rowsOutsideViewportProduceNoRegionsAndPartialRowsAreClipped() {
        var sidebar = Fixtures.sidebar(rowCount: 0)
        let viewport = sidebar.listViewport
        sidebar.rows = [
            ChatRowLayout(slot: 0, frame: AXRect(x: viewport.minX, y: viewport.minY - 200, width: 380, height: 72),
                          previewFrame: AXRect(x: viewport.minX + 72, y: viewport.minY - 160, width: 280, height: 18)),
            ChatRowLayout(slot: 1, frame: AXRect(x: viewport.minX, y: viewport.maxY - 50, width: 380, height: 72),
                          previewFrame: AXRect(x: viewport.minX + 72, y: viewport.maxY - 10, width: 280, height: 18)),
        ]
        let snapshot = Fixtures.snapshot(generation: Generation(1), sidebar: sidebar)
        let coverage = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: window, invalidated: false, settings: settings)
        #expect(coverage.regions.map(\.id.slot) == [1])
        #expect(coverage.regions[0].frame.maxY == viewport.maxY)
    }

    @Test func windowMoveTranslatesPreciseRegions() {
        let snapshot = Fixtures.snapshot(generation: Generation(1))
        let before = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: window, invalidated: false, settings: settings)
        let moved = window.offsetBy(dx: 300, dy: -40)
        let after = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: moved, invalidated: false, settings: settings)
        #expect(after.tier == .precise)
        #expect(zip(before.regions, after.regions).allSatisfy { $0.frame.offsetBy(dx: 300, dy: -40) == $1.frame })
    }

    @Test func windowResizeWithoutRedetectionNeverUsesStaleRows() {
        let snapshot = Fixtures.snapshot(generation: Generation(1))
        let resized = AXRect(x: window.minX, y: window.minY, width: 1100, height: 1000)
        let coverage = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: resized, invalidated: false, settings: settings)
        #expect(coverage.tier == .column)
        #expect(coverage.regions[0].frame.maxY == resized.maxY - (window.maxY - snapshot.sidebar!.listViewport.maxY))
    }

    @Test func noTargetsMeansNoRegions() {
        var none = settings
        none.targets = PrivacyTargets(previews: false)
        for invalidated in [true, false] {
            let snapshot = Fixtures.snapshot(generation: Generation(1))
            let coverage = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: window, invalidated: invalidated, settings: none)
            #expect(coverage.regions.isEmpty)
        }
    }

    /// Privacy invariant: widening for invalidation always covers what precise coverage covered.
    @Test func invalidatedCoverageIsSupersetOfPreciseCoverage() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let rowCount = Int.random(in: 1...14, using: &generator)
            let w = AXRect(
                x: .random(in: -2000...2000, using: &generator), y: .random(in: -500...500, using: &generator),
                width: .random(in: 700...2400, using: &generator), height: .random(in: 500...1400, using: &generator)
            )
            let snapshot = Fixtures.snapshot(generation: Generation(1), window: w, sidebar: Fixtures.sidebar(in: w, rowCount: rowCount))
            let precise = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: w, invalidated: false, settings: settings)
            let widened = CoveragePlanner.plan(latest: snapshot, lastWithSidebar: snapshot, window: w, invalidated: true, settings: settings)
            for region in precise.regions {
                #expect(widened.regions.covers(region.frame, step: 4))
            }
        }
    }
}
