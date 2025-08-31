package org.mytonwallet.app_air.uicomponents.helpers

class MultiTapDetector(
    private val requiredTaps: Int = 5,
    private val timeoutMs: Long = 1000L,
    private val onSuccess: () -> Unit
) {
    private var tapCount = 0
    private var lastTapTime = 0L

    fun registerTap() {
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastTapTime > timeoutMs) {
            tapCount = 1
        } else {
            tapCount++
        }
        lastTapTime = currentTime

        if (tapCount >= requiredTaps) {
            tapCount = 0
            onSuccess()
        }
    }
}
