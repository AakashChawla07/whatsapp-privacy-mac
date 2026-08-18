import CoreGraphics

/// Marker for a coordinate space. Rects from different spaces cannot be mixed by accident.
public protocol CoordinateSpace: Sendable {}

/// Accessibility / CoreGraphics global space: origin at the top-left of the primary display, y grows down, points.
public enum AXGlobal: CoordinateSpace {}
/// AppKit global space: origin at the bottom-left of the primary display, y grows up, points.
public enum AppKitGlobal: CoordinateSpace {}
/// Local space of the overlay content view: origin at its bottom-left, y grows up, points.
public enum OverlayLocal: CoordinateSpace {}

public struct TypedPoint<Space: CoordinateSpace>: Equatable, Sendable {
    public var raw: CGPoint

    public init(_ raw: CGPoint) { self.raw = raw }
    public init(x: CGFloat, y: CGFloat) { self.raw = CGPoint(x: x, y: y) }

    public var x: CGFloat { raw.x }
    public var y: CGFloat { raw.y }
}

public struct TypedRect<Space: CoordinateSpace>: Equatable, Sendable {
    public var raw: CGRect

    public init(_ raw: CGRect) { self.raw = raw.standardized }
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(CGRect(x: x, y: y, width: width, height: height))
    }

    public static var zero: TypedRect { TypedRect(.zero) }

    public var minX: CGFloat { raw.minX }
    public var minY: CGFloat { raw.minY }
    public var maxX: CGFloat { raw.maxX }
    public var maxY: CGFloat { raw.maxY }
    public var midX: CGFloat { raw.midX }
    public var midY: CGFloat { raw.midY }
    public var width: CGFloat { raw.width }
    public var height: CGFloat { raw.height }
    public var size: CGSize { raw.size }
    public var area: CGFloat { isEmpty ? 0 : raw.width * raw.height }
    public var isEmpty: Bool { raw.isNull || raw.isEmpty }

    public func contains(_ point: TypedPoint<Space>) -> Bool { raw.contains(point.raw) }
    public func contains(_ rect: TypedRect<Space>) -> Bool { raw.contains(rect.raw) }
    public func intersects(_ other: TypedRect<Space>) -> Bool { raw.intersects(other.raw) }

    /// Returns nil when the rects do not overlap with a positive area.
    public func intersection(_ other: TypedRect<Space>) -> TypedRect<Space>? {
        let result = raw.intersection(other.raw)
        return (result.isNull || result.isEmpty) ? nil : TypedRect(result)
    }

    public func union(_ other: TypedRect<Space>) -> TypedRect<Space> {
        TypedRect(raw.union(other.raw))
    }

    /// Negative values outset the rect.
    public func insetBy(dx: CGFloat, dy: CGFloat) -> TypedRect<Space> {
        TypedRect(raw.insetBy(dx: dx, dy: dy))
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> TypedRect<Space> {
        TypedRect(raw.offsetBy(dx: dx, dy: dy))
    }
}

public typealias AXRect = TypedRect<AXGlobal>
public typealias AXPoint = TypedPoint<AXGlobal>
public typealias ScreenRect = TypedRect<AppKitGlobal>
public typealias ScreenPoint = TypedPoint<AppKitGlobal>
public typealias OverlayRect = TypedRect<OverlayLocal>
