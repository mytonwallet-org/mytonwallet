package org.mytonwallet.app_air.walletcontext.helpers

import kotlin.math.exp
import kotlin.math.ln
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WInterpolatorSpringTest {

    private val times = (0..100).map { it / 100f }

    @Test
    fun criticallyDampedSpringRisesSmoothlyToItsEnd() {
        val stiffness = 8f
        val curve = times.map { springProgress(it, dampingRatio = 1f, stiffness) }
        assertRisesWithoutOvershoot(curve)
        // The critically damped curve, scaled to end at 1 where it would still be short of it
        val end = 1 - 9 * exp(-8.0)
        assertEquals(
            (1 - 5 * exp(-4.0)) / end,
            springProgress(0.5f, 1f, stiffness).toDouble(),
            1e-6
        )
    }

    @Test
    fun overdampedSpringRisesSlowerThanACriticallyDampedOne() {
        val stiffness = 8f
        val curve = times.map { springProgress(it, dampingRatio = 1.5f, stiffness) }
        assertRisesWithoutOvershoot(curve)
        // From where either has gone anywhere until both end at 1
        times.filter { it in 0.05f..0.99f }.forEach { t ->
            assertTrue(springProgress(t, 1.5f, stiffness) < springProgress(t, 1f, stiffness))
        }
    }

    @Test
    fun springsJustOverCriticalDampingFollowIt() {
        times.forEach { t ->
            assertEquals(springProgress(t, 1f, 8f), springProgress(t, 1.001f, 8f), 1e-3f)
        }
    }

    @Test
    fun springsWithoutASwingReachTheirEndOnTheirLastFrame() {
        // The reaction collapse's 0.35 s spring and the long press release's 0.3 s one, at a damping of 1, which
        // settle by stiffness ln(500), and an overdamped one
        listOf(1f to 346L, 1f to 297L, 1.5f to 346L).forEach { (dampingRatio, durationMs) ->
            val stiffness = ln(500f) / dampingRatio
            assertEquals(1f, springProgress(0.9999f, dampingRatio, stiffness), 1e-4f)
            // Frames at 60 fps, the last one at the end
            val frames = generateSequence(0f) { it + 1000f / 60 / durationMs }
                .takeWhile { it < 1f }
                .plus(1f)
                .map { springProgress(it, dampingRatio, stiffness) }
                .toList()
            val (beforeLast, last) = frames.zipWithNext { before, after -> after - before }
                .takeLast(2)
            assertTrue("A last step of $last after $beforeLast", last <= beforeLast)
        }
    }

    private fun assertRisesWithoutOvershoot(curve: List<Float>) {
        assertEquals(0f, curve.first(), 1e-6f)
        curve.zipWithNext().forEach { (before, after) ->
            assertTrue("$after after $before", after.isFinite() && after >= before && after <= 1f)
        }
    }
}
