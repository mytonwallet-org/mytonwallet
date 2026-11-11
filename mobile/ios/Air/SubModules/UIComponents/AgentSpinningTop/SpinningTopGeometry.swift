import Foundation
import simd

/// The Agent's spinning top as a smooth surface of revolution around the y axis: a rounded point, a neck above it from
/// which concave flanks flare to a thin rim low on the body with a rounded edge, a long concave flare up into the stem,
/// and a rounded cap. The point sits at the origin, where the top pivots as it precesses.
struct SpinningTopGeometry {
    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    /// The camera's elevation above the rim's plane, at which the top shows the mark's silhouette
    static let viewPitch: Float = 9.2 * .pi / 180
    /// The lean of the spin axis, which the mark shows leaning to the right
    static let lean: Float = 11 * .pi / 180
    /// Where the point sits in the square box, relative to its centre, in model units, y up: the mark's point
    static let restingOffset = SIMD2<Float>(-0.134, -0.722)
    /// Half of the box side in model units: the mark's 48 pt box at 26.1 pt per unit
    static let boxHalfExtent: Float = 0.92

    /// The profile in (radius, height), from the point up to the cap, through which a centripetal Catmull–Rom spline
    /// runs. The rim, 0.68 across from the axis, is the widest ring, its outer edge rounded with a radius of about 0.03.
    private static let profile: [SIMD2<Float>] = [
        SIMD2(0.0000, 0.0000),
        SIMD2(0.0356, 0.0067),
        SIMD2(0.0649, 0.0318),
        SIMD2(0.0822, 0.0627),
        SIMD2(0.1203, 0.1331),
        SIMD2(0.1756, 0.2413),
        SIMD2(0.2366, 0.3151),
        SIMD2(0.2874, 0.3543),
        SIMD2(0.3389, 0.3844),
        SIMD2(0.4176, 0.4191),
        SIMD2(0.5191, 0.4496),
        SIMD2(0.6140, 0.4676),
        // The rim: its lower edge, its rounded outer edge and its upper edge
        SIMD2(0.6467, 0.4727),
        SIMD2(0.6630, 0.4810),
        SIMD2(0.6747, 0.4929),
        SIMD2(0.6791, 0.5093),
        SIMD2(0.6747, 0.5256),
        SIMD2(0.6630, 0.5375),
        SIMD2(0.6467, 0.5458),
        SIMD2(0.6102, 0.5520),
        SIMD2(0.5190, 0.5734),
        SIMD2(0.4677, 0.5895),
        SIMD2(0.3864, 0.6215),
        SIMD2(0.3408, 0.6444),
        SIMD2(0.3082, 0.6673),
        SIMD2(0.2333, 0.7440),
        SIMD2(0.1967, 0.7981),
        SIMD2(0.1761, 0.8423),
        SIMD2(0.1556, 0.9032),
        SIMD2(0.1271, 1.0183),
        SIMD2(0.1060, 1.1741),
        SIMD2(0.0917, 1.3553),
        SIMD2(0.0740, 1.4280),
        SIMD2(0.0526, 1.4588),
        SIMD2(0.0353, 1.4705),
        SIMD2(0.0000, 1.4797),
    ]

    let vertices: [Vertex]
    let indices: [UInt32]

    @MainActor static let shared = SpinningTopGeometry()

    /// Enough rings and segments that the smooth shading shows no facets even on the held top, three times larger
    init(profileSamples: Int = 160, segments: Int = 144) {
        let rings = Self.sampleProfile(count: profileSamples)
        var vertices: [Vertex] = []
        vertices.reserveCapacity(rings.count * segments)
        for (index, ring) in rings.enumerated() {
            // Outward normal of the profile, which runs upward; the poles face straight down and up
            var normal = SIMD2<Float>(ring.tangent.y, -ring.tangent.x)
            if index == 0 { normal = SIMD2(0, -1) }
            if index == rings.count - 1 { normal = SIMD2(0, 1) }
            for segment in 0..<segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                let c = cos(angle)
                let s = sin(angle)
                vertices.append(Vertex(
                    position: SIMD3(ring.point.x * c, ring.point.y, ring.point.x * s),
                    normal: simd_normalize(SIMD3(normal.x * c, normal.y, normal.x * s))
                ))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((rings.count - 1) * segments * 6)
        for ring in 0..<(rings.count - 1) {
            for segment in 0..<segments {
                let next = (segment + 1) % segments
                let a = UInt32(ring * segments + segment)
                let b = UInt32(ring * segments + next)
                let c = UInt32((ring + 1) * segments + segment)
                let d = UInt32((ring + 1) * segments + next)
                // Counter-clockwise when seen from outside
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        self.vertices = vertices
        self.indices = indices
    }

    /// Points along the profile, spaced by arc length plus a share of the turning angle, so the rounded point,
    /// the rim and the cap get denser rings than the gently curving flanks
    private static func sampleProfile(count: Int) -> [(point: SIMD2<Float>, tangent: SIMD2<Float>)] {
        let dense = makeDenseProfile(stepsPerSpan: 96)
        var measure: [Float] = [0]
        measure.reserveCapacity(dense.count)
        for i in 1..<dense.count {
            let length = simd_length(dense[i].point - dense[i - 1].point)
            let turn = acos(simd_clamp(simd_dot(dense[i].tangent, dense[i - 1].tangent), -1, 1))
            measure.append(measure[i - 1] + length + 0.05 * turn)
        }
        let total = measure[measure.count - 1]
        var result: [(point: SIMD2<Float>, tangent: SIMD2<Float>)] = []
        result.reserveCapacity(count)
        var j = 0
        for k in 0..<count {
            let target = total * Float(k) / Float(count - 1)
            while j < dense.count - 2 && measure[j + 1] < target { j += 1 }
            let span = max(measure[j + 1] - measure[j], 1e-6)
            let f = simd_clamp((target - measure[j]) / span, 0, 1)
            let point = dense[j].point + (dense[j + 1].point - dense[j].point) * f
            let tangent = simd_normalize(dense[j].tangent + (dense[j + 1].tangent - dense[j].tangent) * f)
            result.append((point, tangent))
        }
        return result
    }

    /// The spline sampled finely, with tangents from neighbouring samples
    private static func makeDenseProfile(stepsPerSpan: Int) -> [(point: SIMD2<Float>, tangent: SIMD2<Float>)] {
        var controls = profile
        controls.insert(2 * profile[0] - profile[1], at: 0)
        controls.append(2 * profile[profile.count - 1] - profile[profile.count - 2])
        var points: [SIMD2<Float>] = []
        points.reserveCapacity((profile.count - 1) * stepsPerSpan + 1)
        for span in 1..<(controls.count - 2) {
            for step in 0..<stepsPerSpan {
                points.append(getCentripetalPoint(
                    controls[span - 1], controls[span], controls[span + 1], controls[span + 2],
                    Float(step) / Float(stepsPerSpan)
                ))
            }
        }
        points.append(profile[profile.count - 1])
        return points.indices.map { i in
            let previous = points[max(0, i - 1)]
            let next = points[min(points.count - 1, i + 1)]
            return (points[i], simd_normalize(next - previous))
        }
    }

    /// A point of the centripetal Catmull–Rom span from `p1` to `p2`, which neither overshoots nor loops at the rim
    private static func getCentripetalPoint(
        _ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>, _ fraction: Float
    ) -> SIMD2<Float> {
        func advanceKnot(_ t: Float, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            t + max(simd_length(b - a), 1e-6).squareRoot()
        }
        let t0: Float = 0
        let t1 = advanceKnot(t0, p0, p1)
        let t2 = advanceKnot(t1, p1, p2)
        let t3 = advanceKnot(t2, p2, p3)
        let t = t1 + (t2 - t1) * fraction
        let a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
        let a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
        let a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
        let b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
        let b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
        return (t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2
    }
}
