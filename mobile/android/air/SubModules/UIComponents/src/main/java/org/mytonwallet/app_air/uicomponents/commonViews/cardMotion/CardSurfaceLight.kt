package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

internal data class CardSurfaceLight(
    val x: Double = 0.0,
    val y: Double = 0.0,
    val activity: Double = 0.0,
    val press: Double = 0.0,
    val border: Point? = null,
    val linearPosition: Double? = null,
    val linearAngle: Double? = null,
    val touch: Touch? = null,
    val gram: Gram? = null
) {
    data class Point(val x: Double, val y: Double)
    data class Vector(val x: Double, val y: Double, val z: Double)
    data class Touch(val position: Point, val opacity: Double)
    data class Gram(
        val rotation: Double = 0.0,
        val balance: Double = 0.0,
        val energy: Double = 1.0,
        val light: Vector = Vector(-.35, .5, 1.4),
        val view: Vector = Vector(0.0, 0.0, 1.0)
    )

    fun visuallyMatches(other: CardSurfaceLight): Boolean {
        fun close(a: Double, b: Double, epsilon: Double = .00015) = abs(a - b) <= epsilon
        fun point(a: Point, b: Point) = close(a.x, b.x) && close(a.y, b.y)
        fun vector(a: Vector, b: Vector) = close(a.x, b.x) && close(a.y, b.y) && close(a.z, b.z)
        fun optionalScalar(a: Double?, b: Double?, epsilon: Double) =
            if (a == null || b == null) a == b else close(a, b, epsilon)
        if (!close(x, other.x) || !close(y, other.y) ||
            !close(activity, other.activity, .0005) || !close(press, other.press, .0005) ||
            !optionalScalar(linearPosition, other.linearPosition, .00015) ||
            !optionalScalar(linearAngle, other.linearAngle, .01)
        ) {
            return false
        }
        if (border == null || other.border == null) {
            if (border != other.border) return false
        } else if (!point(border, other.border)) {
            return false
        }
        if (touch == null || other.touch == null) {
            if (touch != other.touch) return false
        } else if (!point(touch.position, other.touch.position) ||
            !close(touch.opacity, other.touch.opacity, .0005)
        ) {
            return false
        }
        if (gram == null || other.gram == null) return gram == other.gram
        return abs(shortArc(other.gram.rotation, gram.rotation)) <= .0002 &&
            close(
                gram.balance,
                other.gram.balance
            ) && close(gram.energy, other.gram.energy, .0005) &&
            vector(gram.light, other.gram.light) && vector(gram.view, other.gram.view)
    }

    fun interpolated(
        from: CardSurfaceLight,
        progress: Double,
        gpu: Boolean = false
    ): CardSurfaceLight {
        val p = unit(progress)
        if (p == 0.0) return from
        if (p == 1.0) return this
        fun scalar(a: Double, b: Double) = mix(a, b, p)
        fun point(a: Point, b: Point) = Point(scalar(a.x, b.x), scalar(a.y, b.y))
        fun vector(a: Vector, b: Vector) =
            Vector(scalar(a.x, b.x), scalar(a.y, b.y), scalar(a.z, b.z))
        val spot = touch ?: from.touch
        val a = from.gram ?: Gram()
        val b = gram ?: Gram()
        val startAngle = from.linearAngle ?: 61.0
        val targetAngle = linearAngle ?: 61.0
        return copy(
            x = scalar(from.x, x), y = scalar(from.y, y),
            activity = scalar(from.activity, activity), press = scalar(from.press, press),
            border = if (border != null || from.border != null) {
                point(from.border ?: Point(from.x, from.y), border ?: Point(x, y))
            } else {
                null
            },
            linearPosition = if (linearPosition != null || from.linearPosition != null) {
                scalar(from.linearPosition ?: -from.y, linearPosition ?: -y)
            } else {
                null
            },
            linearAngle = if (linearAngle != null || from.linearAngle != null) {
                if (gpu) {
                    startAngle + Math.toDegrees(
                        shortArc(Math.toRadians(startAngle), Math.toRadians(targetAngle))
                    ) * p
                } else {
                    scalar(startAngle, targetAngle)
                }
            } else {
                null
            },
            touch = spot?.let {
                Touch(
                    if (gpu) {
                        point(
                            from.touch?.position ?: Point(0.0, 0.0),
                            touch?.position ?: Point(0.0, 0.0)
                        )
                    } else {
                        point(from.touch?.position ?: it.position, touch?.position ?: it.position)
                    },
                    scalar(from.touch?.opacity ?: 0.0, touch?.opacity ?: 0.0)
                )
            },
            gram = if (gram != null || from.gram != null) {
                Gram(
                    a.rotation + shortArc(a.rotation, b.rotation) * p,
                    scalar(a.balance, b.balance),
                    scalar(a.energy, b.energy),
                    vector(a.light, b.light),
                    vector(a.view, b.view)
                )
            } else {
                null
            }
        )
    }

    companion object {
        val ZERO = CardSurfaceLight()
        const val RESUME_SECONDS = .28
        fun resumeProgress(elapsed: Double) = smooth(elapsed / RESUME_SECONDS)
        private fun shortArc(start: Double, target: Double) =
            atan2(sin(target - start), cos(target - start))

        fun from(motion: CardSurfaceMotion, gram: Boolean, aspect: Double): CardSurfaceLight =
            CardSurfaceLight(
                motion.lightX,
                motion.lightY,
                motion.activity,
                motion.engagement,
                Point(motion.lightX, motion.lightY),
                touch = if (motion.glow.following || motion.glow.opacity > 0) {
                    Touch(Point(motion.glow.x, motion.glow.y), motion.glow.opacity)
                } else {
                    null
                },
                gram = if (gram) {
                    Gram(
                        rotation = motion.gramAngle(aspect),
                        energy = motion.gramEnergy
                    )
                } else {
                    null
                }
            )
    }
}
