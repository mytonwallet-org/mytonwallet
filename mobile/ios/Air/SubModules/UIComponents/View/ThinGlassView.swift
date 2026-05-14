import UIKit
import SwiftUI

public class ThinGlassView: UIView {

    public var cornerRadius: CGFloat = 26 {
        didSet { if oldValue != cornerRadius { setNeedsDisplay() } }
    }

    public var edgeStrokeWidth: CGFloat = 0.7 {
        didSet { if oldValue != edgeStrokeWidth { setNeedsDisplay() } }
    }

    public var fillColor: UIColor? {
        didSet { if oldValue != fillColor { setNeedsDisplay() } }
    }

    public var edgeColor: UIColor? {
        didSet { if oldValue != edgeColor { setNeedsDisplay() } }
    }

    private static let gradientStops: [(CGFloat, CGFloat)] = [
        (0.0, 0.4), (0.125, 0.15), (0.25, 0.5),
        (0.375, 0.95), (0.5, 0.5), (0.625, 0.15),
        (0.75, 0.5), (0.875, 0.95), (1.0, 0.4),
    ]

    private struct GeometryCache {
        let bounds: CGRect
        let cornerRadius: CGFloat
        let edgeStrokeWidth: CGFloat
        let path: CGPath
        let center: CGPoint
        let ringVertices: [CGPoint]
        let cumulative: [CGFloat]
        let perimeterLength: CGFloat
        let perimeterOrigin: CGFloat
        let perimeterClockwise: Bool
    }

    private var geometryCache: GeometryCache?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        guard !bounds.isEmpty else { return }

        let geometry = getGeometry()

        if let fillColor {
            ctx.setFillColor(fillColor.cgColor)
            ctx.addPath(geometry.path)
            ctx.fillPath()
        }

        drawBorder(in: ctx, geometry: geometry)
    }

    private func getGeometry() -> GeometryCache {
        let b = bounds
        let cr = cornerRadius
        let w = edgeStrokeWidth

        if let cache = geometryCache, cache.bounds == b, cache.cornerRadius == cr, cache.edgeStrokeWidth == w {
            return cache
        }

        let path: CGPath
        if #available(iOS 17.0, *) {
            path = Path(roundedRect: b, cornerRadius: cr, style: .continuous).cgPath
        } else {
            path = UIBezierPath(roundedRect: b, cornerRadius: cr).cgPath
        }
        var ring = Self.flatten(path)
        if let f = ring.first, let l = ring.last, hypot(f.x - l.x, f.y - l.y) < 0.5 {
            ring.removeLast()
        }

        let (cum, L) = Self.cumulativeLengths(ring)
        let topTarget = CGPoint(x: b.midX, y: b.minY)
        let sTop = Self.closestArclength(ring: ring, cumulative: cum, perimeterLength: L, to: topTarget)
        let center = CGPoint(x: b.midX, y: b.midY)
        let cw = Self.pathIsClockwiseFromTop(
            ring: ring, cumulative: cum, perimeterLength: L, sTop: sTop, center: center,
            pointOnPerimeter: { Self.pointOnRing(ring: ring, cumulative: cum, perimeterLength: L, arclength: $0) }
        )

        let cache = GeometryCache(
            bounds: b,
            cornerRadius: cr,
            edgeStrokeWidth: w,
            path: path,
            center: center,
            ringVertices: ring,
            cumulative: cum,
            perimeterLength: L,
            perimeterOrigin: sTop,
            perimeterClockwise: cw,
        )

        geometryCache = cache
        return cache
    }

    private func drawBorder(in ctx: CGContext, geometry: GeometryCache) {
        let edgeColor = self.edgeColor ?? .white
        let edgeColorAlpha = CGFloat(edgeColor.cgColor.alpha)
        let geo = geometry

        ctx.saveGState()

        ctx.addPath(geo.path)
        ctx.clip()

        ctx.setLineWidth(geo.edgeStrokeWidth * 2)
        ctx.addPath(geo.path)
        ctx.replacePathWithStrokedPath()
        ctx.clip()

        if #available(iOS 17.0, *) {
            let steps = 360
            let stepsF = CGFloat(steps)
            let L = geo.perimeterLength
            let s0 = geo.perimeterOrigin
            let cw = geo.perimeterClockwise ? CGFloat(1) : CGFloat(-1)

            for i in 0..<steps {
                let t0 = CGFloat(i) / stepsF
                let t1 = CGFloat(i + 1) / stepsF
                let sA = s0 + cw * t0 * L
                let sB = s0 + cw * t1 * L
                let p0 = Self.pointOnRing(
                    ring: geo.ringVertices, cumulative: geo.cumulative, perimeterLength: L, arclength: sA
                )
                let p1 = Self.pointOnRing(
                    ring: geo.ringVertices, cumulative: geo.cumulative, perimeterLength: L, arclength: sB
                )

                let tMid = (CGFloat(i) + 0.5) / stepsF
                let alpha = interpolatedAlpha(at: tMid)
                ctx.setFillColor(edgeColor.withAlphaComponent(alpha * edgeColorAlpha).cgColor)
                ctx.move(to: geo.center)
                ctx.addLine(to: p0)
                ctx.addLine(to: p1)
                ctx.closePath()
                ctx.fillPath()
            }
        } else {
            // It is easier to draw solid border rather than fight with iOS 16 inconsistency.
            ctx.setFillColor(edgeColor.withAlphaComponent(edgeColorAlpha * 0.55).cgColor)
            ctx.addRect(bounds)
            ctx.fillPath()
        }

        ctx.restoreGState()
    }

    private func interpolatedAlpha(at t: CGFloat) -> CGFloat {
        let stops = Self.gradientStops
        for i in 1..<stops.count {
            if t <= stops[i].0 {
                let (t0, a0) = stops[i - 1]
                let (t1, a1) = stops[i]
                let f = (t - t0) / (t1 - t0)
                return a0 + f * (a1 - a0)
            }
        }
        return stops.last?.1 ?? 1.0
    }

    // MARK: - Ring sampling (perimeter / arclength)

    private static func cumulativeLengths(_ ring: [CGPoint]) -> ([CGFloat], CGFloat) {
        let n = ring.count
        guard n >= 2 else { return ([0], 0) }
        var cum: [CGFloat] = [0]
        var L: CGFloat = 0
        for i in 0..<n {
            let a = ring[i]
            let b = ring[(i + 1) % n]
            let d = hypot(b.x - a.x, b.y - a.y)
            L += d
            cum.append(L)
        }
        return (cum, L)
    }

    private static func pointOnRing(
        ring: [CGPoint], cumulative: [CGFloat], perimeterLength L: CGFloat, arclength s: CGFloat
    ) -> CGPoint {
        let n = ring.count
        guard n >= 2, L > 0 else { return ring.first ?? .zero }
        var ss = s.truncatingRemainder(dividingBy: L)
        if ss < 0 { ss += L }

        var lo = 0
        var hi = n
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cumulative[mid] <= ss {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        let i = min(lo, n - 1)
        let segStart = cumulative[i]
        let segEnd = cumulative[i + 1]
        let segLen = max(segEnd - segStart, 1e-6)
        let u = (ss - segStart) / segLen
        let p0 = ring[i % n]
        let p1 = ring[(i + 1) % n]
        return CGPoint(x: p0.x + u * (p1.x - p0.x), y: p0.y + u * (p1.y - p0.y))
    }

    private static func closestArclength(
        ring: [CGPoint], cumulative: [CGFloat], perimeterLength L: CGFloat, to target: CGPoint
    ) -> CGFloat {
        let n = ring.count
        guard n >= 2, L > 0 else { return 0 }
        var bestD = CGFloat.infinity
        var bestS: CGFloat = 0
        for i in 0..<n {
            let a = ring[i]
            let b = ring[(i + 1) % n]
            let s0 = cumulative[i]
            let segLen = max(cumulative[i + 1] - s0, 1e-6)
            let (u, d) = closestOnSegment(a: a, b: b, to: target)
            let ds = s0 + u * segLen
            if d < bestD {
                bestD = d
                bestS = ds
            }
        }
        return bestS.truncatingRemainder(dividingBy: L)
    }

    private static func closestOnSegment(a: CGPoint, b: CGPoint, to p: CGPoint) -> (CGFloat, CGFloat) {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y
        let ab2 = abx * abx + aby * aby
        if ab2 < 1e-12 { return (0, hypot(apx, apy)) }
        var u = (apx * abx + apy * aby) / ab2
        u = min(1, max(0, u))
        let qx = a.x + u * abx
        let qy = a.y + u * aby
        return (u, hypot(p.x - qx, p.y - qy))
    }

    private static func pathIsClockwiseFromTop(
        ring: [CGPoint], cumulative: [CGFloat], perimeterLength L: CGFloat, sTop: CGFloat, center: CGPoint,
        pointOnPerimeter: (CGFloat) -> CGPoint
    ) -> Bool {
        let eps = max(L * 0.001, 0.35)
        let p0 = pointOnPerimeter(sTop)
        let p1 = pointOnPerimeter(sTop + eps)
        let a0 = angleFromTop(center: center, point: p0)
        let a1 = angleFromTop(center: center, point: p1)
        var d = a1 - a0
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d > 0
    }

    private static func angleFromTop(center: CGPoint, point: CGPoint) -> CGFloat {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return atan2(dx, -dy)
    }

    private static func flatten(_ path: CGPath) -> [CGPoint] {
        var pts: [CGPoint] = []
        var current = CGPoint.zero

        path.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint:
                current = e.points[0]
                pts.append(current)
            case .addLineToPoint:
                current = e.points[0]
                pts.append(current)
            case .addQuadCurveToPoint:
                let p0 = current
                let c1 = e.points[0]
                let p2 = e.points[1]
                for k in 1...8 {
                    let t = CGFloat(k) / 8
                    pts.append(quad(p0, c1, p2, t))
                }
                current = p2
            case .addCurveToPoint:
                let p0 = current
                let c1 = e.points[0]
                let c2 = e.points[1]
                let p3 = e.points[2]
                for k in 1...12 {
                    let t = CGFloat(k) / 12
                    pts.append(cubic(p0, c1, c2, p3, t))
                }
                current = p3
            case .closeSubpath:
                if !pts.isEmpty {
                    let f = pts[0]
                    if hypot(f.x - current.x, f.y - current.y) > 0.01 {
                        pts.append(f)
                    }
                    current = f
                }
            @unknown default:
                break
            }
        }
        return pts
    }

    private static func quad(_ p0: CGPoint, _ c: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = u * u * p0.x + 2 * u * t * c.x + t * t * p2.x
        let y = u * u * p0.y + 2 * u * t * c.y + t * t * p2.y
        return CGPoint(x: x, y: y)
    }

    private static func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        let x = uu * u * p0.x + 3 * uu * t * c1.x + 3 * u * tt * c2.x + tt * t * p3.x
        let y = uu * u * p0.y + 3 * uu * t * c1.y + 3 * u * tt * c2.y + tt * t * p3.y
        return CGPoint(x: x, y: y)
    }
}

public struct ThinGlass: UIViewRepresentable {
    public var cornerRadius: CGFloat
    public var fillColor: UIColor?
    public var edgeColor: UIColor?

    public init(cornerRadius: CGFloat = 26, fillColor: UIColor? = nil, edgeColor: UIColor? = nil) {
        self.cornerRadius = cornerRadius
        self.fillColor = fillColor
        self.edgeColor = edgeColor
    }

    public func makeUIView(context: Context) -> ThinGlassView {
        ThinGlassView()
    }

    public func updateUIView(_ uiView: ThinGlassView, context: Context) {
        uiView.cornerRadius = cornerRadius
        uiView.fillColor = fillColor
        uiView.edgeColor = edgeColor
    }
}
