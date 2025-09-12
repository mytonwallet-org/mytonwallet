package org.mytonwallet.app_air.uicomponents.widgets.particles

data class ParticleConfig(
    val width: Int = 400,
    val height: Int = 250,
    val particleCount: Int = 19,
    val color: FloatArray = floatArrayOf(0f, 152f / 255f, 234f / 255f), // #0098EA (TON)
    val speed: Float = 18f,
    val baseSize: Float = 6f,
    val minSpawnRadius: Float = 55f,
    val maxSpawnRadius: Float = 70f,
    val distanceLimit: Float = 1f,
    val fadeInTime: Float = 0.25f,
    val fadeOutTime: Float = 1f,
    val minLifetime: Float = 3f,
    val maxLifetime: Float = 5f,
    val maxStartTimeDelay: Float = 1f,
    val edgeFadeZone: Float = 50f,
    val centerShift: FloatArray = floatArrayOf(0f, 0f),
    val accelerationFactor: Float = 3f,
    val selfDestroyTime: Float = 0f
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as ParticleConfig

        if (width != other.width) return false
        if (height != other.height) return false
        if (particleCount != other.particleCount) return false
        if (!color.contentEquals(other.color)) return false
        if (speed != other.speed) return false
        if (baseSize != other.baseSize) return false
        if (minSpawnRadius != other.minSpawnRadius) return false
        if (maxSpawnRadius != other.maxSpawnRadius) return false
        if (distanceLimit != other.distanceLimit) return false
        if (fadeInTime != other.fadeInTime) return false
        if (fadeOutTime != other.fadeOutTime) return false
        if (minLifetime != other.minLifetime) return false
        if (maxLifetime != other.maxLifetime) return false
        if (maxStartTimeDelay != other.maxStartTimeDelay) return false
        if (edgeFadeZone != other.edgeFadeZone) return false
        if (!centerShift.contentEquals(other.centerShift)) return false
        if (accelerationFactor != other.accelerationFactor) return false
        if (selfDestroyTime != other.selfDestroyTime) return false

        return true
    }

    override fun hashCode(): Int {
        var result = width
        result = 31 * result + height
        result = 31 * result + particleCount
        result = 31 * result + color.contentHashCode()
        result = 31 * result + speed.hashCode()
        result = 31 * result + baseSize.hashCode()
        result = 31 * result + minSpawnRadius.hashCode()
        result = 31 * result + maxSpawnRadius.hashCode()
        result = 31 * result + distanceLimit.hashCode()
        result = 31 * result + fadeInTime.hashCode()
        result = 31 * result + fadeOutTime.hashCode()
        result = 31 * result + minLifetime.hashCode()
        result = 31 * result + maxLifetime.hashCode()
        result = 31 * result + maxStartTimeDelay.hashCode()
        result = 31 * result + edgeFadeZone.hashCode()
        result = 31 * result + centerShift.contentHashCode()
        result = 31 * result + accelerationFactor.hashCode()
        result = 31 * result + selfDestroyTime.hashCode()
        return result
    }

    companion object {
        object PARTICLE_COLORS {
            val TON = floatArrayOf(0f, 152f / 255f, 234f / 255f) // #0098EA
            val USDT = floatArrayOf(0f, 147f / 255f, 147f / 255f) // #009393
            val MY = floatArrayOf(64f / 255f, 122f / 255f, 207f / 255f) // #407ACF
            val GREEN = floatArrayOf(83f / 255f, 163f / 255f, 13f / 255f) // #407ACF
        }

        // Burst particle configuration for tap
        fun particleBurstParams(color: FloatArray = PARTICLE_COLORS.TON): ParticleConfig {
            return ParticleConfig(
                particleCount = 90,
                distanceLimit = 1f,
                fadeInTime = 0.05f,
                minLifetime = 3f,
                maxLifetime = 3f,
                maxStartTimeDelay = 0f,
                selfDestroyTime = 3f,
                minSpawnRadius = 35f,
                maxSpawnRadius = 50f,
                color = color
            )
        }
    }
}
