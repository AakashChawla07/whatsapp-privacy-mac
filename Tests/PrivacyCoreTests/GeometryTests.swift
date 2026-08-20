import CoreGraphics
import Testing
@testable import PrivacyCore

@Suite("Coordinate conversion")
struct GeometryTests {
    // Primary 1512×982 @2x; secondary 1920×1080 @1x to the left and higher (negative x, y above primary).
    let converter = CoordinateConverter(screens: [
        ScreenInfo(frame: ScreenRect(x: 0, y: 0, width: 1512, height: 982), backingScaleFactor: 2),
        ScreenInfo(frame: ScreenRect(x: -1920, y: 200, width: 1920, height: 1080), backingScaleFactor: 1),
    ])

    @Test func axToAppKitFlipsAroundPrimaryHeight() {
        let ax = AXRect(x: 100, y: 80, width: 400, height: 300)
        let appKit = converter.toAppKit(ax)
        #expect(appKit == ScreenRect(x: 100, y: 982 - 380, width: 400, height: 300))
    }

    @Test(arguments: [
        CGRect(x: 0, y: 0, width: 10, height: 10),
        CGRect(x: -1800, y: -250, width: 900, height: 700),
        CGRect(x: 1400, y: 900, width: 300, height: 200),
    ])
    func roundTripIsLossless(rect: CGRect) {
        let ax = AXRect(rect)
        #expect(converter.toAX(converter.toAppKit(ax)) == ax)
        let point = AXPoint(x: rect.minX, y: rect.minY)
        #expect(converter.toAX(converter.toAppKit(point)) == point)
    }

    @Test func overlayLocalUsesBottomLeftOrigin() {
        let overlay = AXRect(x: 100, y: 100, width: 300, height: 600)
        let region = AXRect(x: 120, y: 110, width: 200, height: 20)   // near the top of the overlay
        let local = converter.toOverlay(region, overlayFrame: overlay)
        #expect(local == OverlayRect(x: 20, y: 600 - 30, width: 200, height: 20))
    }

    @Test func screenLookupUsesMidpointThenLargestOverlap() {
        let onSecondary = AXRect(x: -1000, y: -100, width: 200, height: 200)
        #expect(converter.screen(containing: onSecondary)?.backingScaleFactor == 1)

        let onPrimary = AXRect(x: 200, y: 200, width: 100, height: 100)
        #expect(converter.screen(containing: onPrimary)?.backingScaleFactor == 2)

        let offscreen = AXRect(x: 10_000, y: 10_000, width: 10, height: 10)
        #expect(converter.screen(containing: offscreen) == nil)
    }

    @Test func pixelAlignmentRoundsOutward() {
        let rect = ScreenRect(x: 10.3, y: 20.6, width: 5.1, height: 5.1)
        #expect(converter.pixelAligned(rect, scale: 2) == ScreenRect(x: 10.0, y: 20.5, width: 5.5, height: 5.5))
        #expect(converter.pixelAligned(rect, scale: 1) == ScreenRect(x: 10, y: 20, width: 6, height: 6))
    }

    @Test func sidebarRebaseTranslatesOnMoveAndStretchesOnResize() {
        let window = AXRect(x: 0, y: 0, width: 1000, height: 800)
        let sidebar = SidebarLayout(
            frame: AXRect(x: 0, y: 28, width: 360, height: 772),
            listViewport: AXRect(x: 0, y: 140, width: 360, height: 650),   // 10pt bottom inset
            rows: []
        )

        let moved = sidebar.rebased(from: window, to: window.offsetBy(dx: 50, dy: 30))
        #expect(moved.listViewport == AXRect(x: 50, y: 170, width: 360, height: 650))

        let taller = sidebar.rebased(from: window, to: AXRect(x: 0, y: 0, width: 1000, height: 1000))
        #expect(taller.listViewport == AXRect(x: 0, y: 140, width: 360, height: 850))
    }
}
