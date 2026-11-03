package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The Agent's spinning top as a smooth surface of revolution around the y axis, fitted to the flat mark: a rounded
 * point, flanks that curve in toward a thin rim low on the body, a long concave flare up into the stem, and a rounded
 * cap. The point sits at the origin, where the top pivots as it precesses.
 */
internal object AgentSpinningTopGeometry {
    /** The camera's elevation above the rim's plane, at which the top shows the mark's silhouette */
    const val VIEW_PITCH = (9.2 * PI / 180).toFloat()

    /** The lean of the spin axis, which the mark shows leaning to the right */
    const val LEAN = (11 * PI / 180).toFloat()

    /** Where the point sits in the square box, relative to its center, in model units, y up: the mark's point */
    const val RESTING_OFFSET_X = -0.134f
    const val RESTING_OFFSET_Y = -0.722f

    /** Half of the box side in model units: the mark's 48 dp box at 26.1 dp per unit */
    const val BOX_HALF_EXTENT = 0.92f

    /** Position and normal of each vertex, three floats each */
    const val FLOATS_PER_VERTEX = 6

    /**
     * The profile in (radius, height), from the point up to the cap, through which a centripetal Catmull–Rom spline
     * runs. Fitted so the top, leaning and seen from the camera's elevation, covers the mark.
     */
    private val profile = arrayOf(
        floatArrayOf(0.0000f, 0.0000f),
        floatArrayOf(0.0479f, 0.0134f),
        floatArrayOf(0.0843f, 0.0652f),
        floatArrayOf(0.1112f, 0.1073f),
        floatArrayOf(0.1380f, 0.1610f),
        floatArrayOf(0.1687f, 0.2223f),
        floatArrayOf(0.2070f, 0.2798f),
        floatArrayOf(0.2837f, 0.3527f),
        floatArrayOf(0.4600f, 0.4447f),
        // The rim: its lower edge, its rounded outer edge and its upper edge
        floatArrayOf(0.6747f, 0.4696f),
        floatArrayOf(0.7283f, 0.4887f),
        floatArrayOf(0.6747f, 0.5079f),
        floatArrayOf(0.4907f, 0.5309f),
        floatArrayOf(0.3450f, 0.5865f),
        floatArrayOf(0.2722f, 0.6555f),
        floatArrayOf(0.2300f, 0.7092f),
        floatArrayOf(0.1955f, 0.7667f),
        floatArrayOf(0.1687f, 0.8280f),
        floatArrayOf(0.1418f, 0.9200f),
        floatArrayOf(0.1265f, 1.0158f),
        floatArrayOf(0.1169f, 1.1308f),
        floatArrayOf(0.1112f, 1.2267f),
        floatArrayOf(0.1054f, 1.3225f),
        floatArrayOf(0.0862f, 1.4030f),
        floatArrayOf(0.0479f, 1.4605f),
        floatArrayOf(0.0000f, 1.4797f)
    )

    class Mesh(val vertices: FloatArray, val indices: IntArray)

    /** Enough rings and segments that the smooth shading shows no facets even on the held top, three times larger */
    fun buildMesh(profileSamples: Int = 160, segments: Int = 144): Mesh {
        val rings = sampleProfile(profileSamples)
        val vertices = FloatArray(rings.size * segments * FLOATS_PER_VERTEX)
        var cursor = 0
        rings.forEachIndexed { index, ring ->
            // Outward normal of the profile, which runs upward; the poles face straight down and up
            var normalX = ring.tangentY
            var normalY = -ring.tangentX
            if (index == 0) {
                normalX = 0f
                normalY = -1f
            } else if (index == rings.lastIndex) {
                normalX = 0f
                normalY = 1f
            }
            for (segment in 0 until segments) {
                val angle = segment.toFloat() / segments * 2 * PI.toFloat()
                val cosine = cos(angle)
                val sine = sin(angle)
                vertices[cursor++] = ring.x * cosine
                vertices[cursor++] = ring.y
                vertices[cursor++] = ring.x * sine
                // The profile's unit normal, turned around the axis with the segment
                vertices[cursor++] = normalX * cosine
                vertices[cursor++] = normalY
                vertices[cursor++] = normalX * sine
            }
        }
        val indices = IntArray((rings.size - 1) * segments * 6)
        cursor = 0
        for (ring in 0 until rings.size - 1) {
            for (segment in 0 until segments) {
                val next = (segment + 1) % segments
                val a = ring * segments + segment
                val b = ring * segments + next
                val c = (ring + 1) * segments + segment
                val d = (ring + 1) * segments + next
                // Counter-clockwise when seen from outside
                indices[cursor++] = a
                indices[cursor++] = c
                indices[cursor++] = b
                indices[cursor++] = b
                indices[cursor++] = c
                indices[cursor++] = d
            }
        }
        return Mesh(vertices, indices)
    }

    private class ProfilePoint(val x: Float, val y: Float, val tangentX: Float, val tangentY: Float)

    /**
     * Points along the profile, spaced by arc length plus a share of the turning angle, so the rounded point, the rim
     * and the cap get denser rings than the gently curving flanks
     */
    private fun sampleProfile(count: Int): List<ProfilePoint> {
        val dense = makeDenseProfile(stepsPerSpan = 96)
        val measure = FloatArray(dense.size)
        for (i in 1 until dense.size) {
            val length = computeLength(dense[i].x - dense[i - 1].x, dense[i].y - dense[i - 1].y)
            val dot = dense[i].tangentX * dense[i - 1].tangentX +
                dense[i].tangentY * dense[i - 1].tangentY
            val turn = acos(dot.coerceIn(-1f, 1f))
            measure[i] = measure[i - 1] + length + 0.05f * turn
        }
        val total = measure.last()
        var j = 0
        return List(count) { k ->
            val target = total * k / (count - 1)
            while (j < dense.size - 2 && measure[j + 1] < target) j++
            val span = max(measure[j + 1] - measure[j], 1e-6f)
            val f = ((target - measure[j]) / span).coerceIn(0f, 1f)
            val from = dense[j]
            val to = dense[j + 1]
            val tangentX = from.tangentX + (to.tangentX - from.tangentX) * f
            val tangentY = from.tangentY + (to.tangentY - from.tangentY) * f
            val tangentLength = max(computeLength(tangentX, tangentY), 1e-6f)
            ProfilePoint(
                from.x + (to.x - from.x) * f,
                from.y + (to.y - from.y) * f,
                tangentX / tangentLength,
                tangentY / tangentLength
            )
        }
    }

    /** The spline sampled finely, with tangents from neighbouring samples */
    private fun makeDenseProfile(stepsPerSpan: Int): List<ProfilePoint> {
        val first = profile.first()
        val second = profile[1]
        val last = profile.last()
        val beforeLast = profile[profile.size - 2]
        val controls = listOf(floatArrayOf(2 * first[0] - second[0], 2 * first[1] - second[1])) +
            profile.toList() +
            listOf(floatArrayOf(2 * last[0] - beforeLast[0], 2 * last[1] - beforeLast[1]))
        val points = ArrayList<FloatArray>((profile.size - 1) * stepsPerSpan + 1)
        for (span in 1 until controls.size - 2) {
            for (step in 0 until stepsPerSpan) {
                points.add(
                    computeCentripetalPoint(
                        controls[span - 1],
                        controls[span],
                        controls[span + 1],
                        controls[span + 2],
                        step.toFloat() / stepsPerSpan
                    )
                )
            }
        }
        points.add(last)
        return points.indices.map { i ->
            val previous = points[max(0, i - 1)]
            val next = points[minOf(points.lastIndex, i + 1)]
            val dx = next[0] - previous[0]
            val dy = next[1] - previous[1]
            val length = max(computeLength(dx, dy), 1e-6f)
            ProfilePoint(points[i][0], points[i][1], dx / length, dy / length)
        }
    }

    /** A point of the centripetal Catmull–Rom span from [p1] to [p2], which neither overshoots nor loops at the rim */
    private fun computeCentripetalPoint(
        p0: FloatArray,
        p1: FloatArray,
        p2: FloatArray,
        p3: FloatArray,
        fraction: Float
    ): FloatArray {
        fun advanceKnot(t: Float, a: FloatArray, b: FloatArray) =
            t + sqrt(max(computeLength(b[0] - a[0], b[1] - a[1]), 1e-6f))

        val t0 = 0f
        val t1 = advanceKnot(t0, p0, p1)
        val t2 = advanceKnot(t1, p1, p2)
        val t3 = advanceKnot(t2, p2, p3)
        val t = t1 + (t2 - t1) * fraction
        return FloatArray(2) { axis ->
            val a1 = (t1 - t) / (t1 - t0) * p0[axis] + (t - t0) / (t1 - t0) * p1[axis]
            val a2 = (t2 - t) / (t2 - t1) * p1[axis] + (t - t1) / (t2 - t1) * p2[axis]
            val a3 = (t3 - t) / (t3 - t2) * p2[axis] + (t - t2) / (t3 - t2) * p3[axis]
            val b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
            val b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
            (t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2
        }
    }

    private fun computeLength(dx: Float, dy: Float) = sqrt(dx * dx + dy * dy)

    /**
     * The top turned by [yaw] about its own axis, the axis leaning by [lean] toward [leanDirection] and pivoting on the
     * point at the origin, all seen from [pitch] above, into [out] as a column-major 4 × 4 matrix. Direction 0 leans to
     * the right, as the mark does; it advances the way the top spins.
     */
    fun computeTransform(
        yaw: Float,
        pitch: Float,
        lean: Float,
        leanDirection: Float,
        out: FloatArray
    ) {
        // Quaternions as (x, y, z, w): the spin about y, the tilt toward (cos ψ, 0, −sin ψ) about up × that
        // direction, and the camera's pitch about x
        val spinSin = sin(yaw / 2)
        val spinCos = cos(yaw / 2)
        val tiltSin = sin(lean / 2)
        val tiltCos = cos(lean / 2)
        val tiltX = -sin(leanDirection) * tiltSin
        val tiltZ = -cos(leanDirection) * tiltSin
        val cameraSin = sin(pitch / 2)
        val cameraCos = cos(pitch / 2)
        // tilt × spin, spin being (0, spinSin, 0, spinCos)
        val tiltSpinX = tiltX * spinCos - tiltZ * spinSin
        val tiltSpinY = tiltCos * spinSin
        val tiltSpinZ = tiltZ * spinCos + tiltX * spinSin
        val tiltSpinW = tiltCos * spinCos
        // camera × (tilt × spin), camera being (cameraSin, 0, 0, cameraCos)
        val x = cameraCos * tiltSpinX + cameraSin * tiltSpinW
        val y = cameraCos * tiltSpinY - cameraSin * tiltSpinZ
        val z = cameraCos * tiltSpinZ + cameraSin * tiltSpinY
        val w = cameraCos * tiltSpinW - cameraSin * tiltSpinX
        out[0] = 1 - 2 * (y * y + z * z)
        out[1] = 2 * (x * y + z * w)
        out[2] = 2 * (x * z - y * w)
        out[3] = 0f
        out[4] = 2 * (x * y - z * w)
        out[5] = 1 - 2 * (x * x + z * z)
        out[6] = 2 * (y * z + x * w)
        out[7] = 0f
        out[8] = 2 * (x * z + y * w)
        out[9] = 2 * (y * z - x * w)
        out[10] = 1 - 2 * (x * x + y * y)
        out[11] = 0f
        out[12] = 0f
        out[13] = 0f
        out[14] = 0f
        out[15] = 1f
    }
}
