package org.mytonwallet.app_air.uicomponents.widgets.particles

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.UUID
import kotlin.math.cos
import kotlin.math.sin

data class ParticleSystem(
    val id: String = UUID.randomUUID().toString(),
    val config: ParticleConfig,
    val startTime: Long = System.currentTimeMillis(),
    val seed: Int = (Math.random() * 1000000).toInt(),
    var selfDestroyTimeout: Runnable? = null
) {
    val centerX: Float = config.width / 2f + config.centerShift[0]
    val centerY: Float = config.height / 2f + config.centerShift[1]
    val avgDistance: Float = (config.width / 2f + config.height / 2f) / 2f

    // Buffers for OpenGL
    lateinit var startPositionBuffer: FloatBuffer
    lateinit var velocityBuffer: FloatBuffer
    lateinit var startTimeBuffer: FloatBuffer
    lateinit var lifetimeBuffer: FloatBuffer
    lateinit var sizeBuffer: FloatBuffer
    lateinit var baseOpacityBuffer: FloatBuffer

    fun initializeBuffers(dpr: Float) {
        val rng = SeededRandom(seed)

        val startPositions = FloatArray(config.particleCount * 2)
        val velocities = FloatArray(config.particleCount * 2)
        val startTimes = FloatArray(config.particleCount)
        val lifetimes = FloatArray(config.particleCount)
        val sizes = FloatArray(config.particleCount)
        val baseOpacities = FloatArray(config.particleCount)

        for (i in 0 until config.particleCount) {
            val angle = rng.next() * Math.PI.toFloat() * 2f
            val spawnRadius = rng.nextBetween(config.minSpawnRadius, config.maxSpawnRadius)

            val cos = cos(angle)
            val sin = sin(angle)

            val spawnX = centerX + cos * spawnRadius
            val spawnY = centerY + sin * spawnRadius

            startPositions[i * 2] = spawnX * dpr
            startPositions[i * 2 + 1] = spawnY * dpr

            lifetimes[i] = rng.nextBetween(config.minLifetime, config.maxLifetime)
            startTimes[i] = rng.next() * config.maxStartTimeDelay

            val travelDist = rng.nextBetween(
                avgDistance * config.distanceLimit * 0.5f,
                avgDistance * config.distanceLimit
            )

            // Calculate speed based on travel distance and lifetime
            val speed = (travelDist / lifetimes[i]) * dpr

            velocities[i * 2] = cos * speed
            velocities[i * 2 + 1] = sin * speed

            val sizeVariant = rng.next()
            sizes[i] = when {
                sizeVariant < 0.3f -> config.baseSize * SIZE_SMALL * dpr
                sizeVariant < 0.7f -> config.baseSize * SIZE_MEDIUM * dpr
                else -> config.baseSize * SIZE_LARGE * dpr
            }

            baseOpacities[i] = rng.nextBetween(0.1f, 0.7f)
        }

        startPositionBuffer = createFloatBuffer(startPositions)
        velocityBuffer = createFloatBuffer(velocities)
        startTimeBuffer = createFloatBuffer(startTimes)
        lifetimeBuffer = createFloatBuffer(lifetimes)
        sizeBuffer = createFloatBuffer(sizes)
        baseOpacityBuffer = createFloatBuffer(baseOpacities)
    }

    private fun createFloatBuffer(data: FloatArray): FloatBuffer {
        val buffer = ByteBuffer.allocateDirect(data.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        buffer.put(data)
        buffer.position(0)
        return buffer
    }

    companion object {
        private const val SIZE_SMALL = 0.67f
        private const val SIZE_MEDIUM = 1.33f
        private const val SIZE_LARGE = 2.0f
    }
}
