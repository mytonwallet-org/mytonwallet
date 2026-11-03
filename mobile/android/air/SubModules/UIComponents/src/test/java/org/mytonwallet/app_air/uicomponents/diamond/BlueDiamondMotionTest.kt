package org.mytonwallet.app_air.uicomponents.diamond

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BlueDiamondMotionTest {
    @Test
    fun repeatedTapContinuesAtTheCurrentAngleAndVelocity() {
        val motion = BlueDiamondMotion()
        motion.press(0f, true)
        motion.release(0f, fullTurn = true)
        motion.update(0.9f)
        val before = motion.yaw
        motion.update(0.91f)
        val atPress = motion.yaw
        val previousTravel = atPress - before
        motion.press(0.91f, true)
        motion.update(0.96f)
        assertEquals(atPress, motion.yaw, 0f)
        motion.release(0.96f, fullTurn = true)
        motion.update(0.97f)
        val nextTravel = motion.yaw - atPress
        assertTrue(nextTravel > previousTravel * 0.9f)
        assertTrue(nextTravel < previousTravel * 1.1f)
        motion.update(2.76f)
        assertEquals(atPress + 6 * PI.toFloat(), motion.yaw, 0.001f)
        assertEquals(0f, motion.pitch, 0f)
    }

    @Test
    fun holdingCancelsTheAutomaticTurnAndAllowsImmediateDragging() {
        val motion = BlueDiamondMotion()
        motion.press(0f, true)
        motion.release(0f, fullTurn = true)
        motion.update(0.6f)
        val angle = motion.yaw
        motion.press(0.6f, true)
        motion.update(1f)
        assertEquals(angle, motion.yaw, 0f)
        motion.drag(4f, 4f)
        assertTrue(motion.yaw > angle)
        assertTrue(motion.pitch > 0f)
        motion.release(1f)
        motion.update(1.7f)
        assertEquals(0f, motion.yaw, 0.001f)
    }
}
