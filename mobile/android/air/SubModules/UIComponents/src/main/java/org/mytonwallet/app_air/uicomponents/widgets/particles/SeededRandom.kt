package org.mytonwallet.app_air.uicomponents.widgets.particles

class SeededRandom(private var seed: Int) {

    fun next(): Float {
        seed = (seed * 9301 + 49297) % 233280
        return seed / 233280f
    }

    fun nextBetween(min: Float, max: Float): Float {
        return min + (max - min) * next()
    }
}
