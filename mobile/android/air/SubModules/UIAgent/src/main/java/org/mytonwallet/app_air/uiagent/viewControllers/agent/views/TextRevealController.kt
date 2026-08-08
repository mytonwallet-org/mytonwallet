package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import kotlin.math.max
import kotlin.math.min

class TextRevealController(initialRevealedCount: Int, initialLength: Int) {

    companion object {
        private const val VELOCITY_TAU = 0.12
        private const val GAP_EWMA_ALPHA = 0.4
        private const val INITIAL_GAP = 0.5
        private const val STALL_FLOOR = 0.10
        private const val FINALIZE_TIME = 0.3
        private const val FRAME_DT_CAP = 0.05
        private const val INITIAL_INPUT_RATE = 40.0
    }

    var revealedCount: Double = initialRevealedCount.toDouble()
        private set
    private var velocity = 0.0
    private var avgInterArrival = INITIAL_GAP
    private var lastSampleTime: Double? = null
    private var lastSampleLength: Int? = null
    private var predictedNextArrivalTime: Double? = null
    private var chunkCount = 0
    var latestLength: Int = initialLength
        private set
    var isFinalizing = false
        private set
    private var lastFrameTime: Double? = null

    fun observeUpdate(latestLength: Int, now: Double) {
        val lastLen = lastSampleLength
        if (lastLen != null) {
            if (latestLength > lastLen) {
                lastSampleTime?.let { lastTime ->
                    val interArrival = max(now - lastTime, 0.001)
                    avgInterArrival =
                        GAP_EWMA_ALPHA * interArrival + (1.0 - GAP_EWMA_ALPHA) * avgInterArrival
                }
                lastSampleTime = now
                lastSampleLength = latestLength
                predictedNextArrivalTime = now + avgInterArrival
                chunkCount += 1
            } else if (latestLength < lastLen) {
                lastSampleLength = latestLength
            }
        } else {
            lastSampleTime = now
            lastSampleLength = latestLength
            predictedNextArrivalTime = now + avgInterArrival
            chunkCount += 1
        }
        this.latestLength = latestLength
        if (revealedCount > latestLength) {
            revealedCount = latestLength.toDouble()
        }
    }

    fun rewind(count: Int) {
        if (revealedCount > count) {
            revealedCount = count.toDouble()
        }
    }

    fun finalize(finalLength: Int) {
        latestLength = finalLength
        isFinalizing = true
        if (revealedCount > finalLength) {
            revealedCount = finalLength.toDouble()
        }
    }

    // Returns revealed character count and whether the reveal is complete.
    fun tick(now: Double): Pair<Int, Boolean> {
        val dt = min(now - (lastFrameTime ?: now), FRAME_DT_CAP)
        val lag = max(0.0, latestLength - revealedCount)
        val predNext = predictedNextArrivalTime
        val targetVelocity: Double = when {
            isFinalizing -> max(velocity, lag / FINALIZE_TIME)

            chunkCount < 2 -> if (lag > 0.0) INITIAL_INPUT_RATE else 0.0

            predNext != null -> {
                val timeToNext = max(STALL_FLOOR, predNext - now)
                lag / timeToNext
            }

            else -> if (lag > 0.0) INITIAL_INPUT_RATE else 0.0
        }
        if (isFinalizing) {
            velocity = max(velocity, targetVelocity)
        } else {
            val smoothing = min(1.0, dt / VELOCITY_TAU)
            velocity += (targetVelocity - velocity) * smoothing
        }
        revealedCount = min(latestLength.toDouble(), revealedCount + velocity * dt)
        lastFrameTime = now
        val isComplete = isFinalizing && revealedCount >= latestLength
        return Pair(revealedCount.toInt(), isComplete)
    }
}
