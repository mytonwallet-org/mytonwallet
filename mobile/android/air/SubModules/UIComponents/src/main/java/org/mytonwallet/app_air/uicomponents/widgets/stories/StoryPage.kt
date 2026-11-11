package org.mytonwallet.app_air.uicomponents.widgets.stories

import android.net.Uri
import java.io.File
import kotlin.math.max
import kotlin.math.min

private const val MAXIMUM_MEDIA_WAIT = 2.0
private const val DEFAULT_DURATION = 10.0

class StoryPage(
    val id: String,
    val title: String,
    val body: String,
    val buttonTitle: String? = null,
    duration: Double = DEFAULT_DURATION,
    val previewFile: File? = null,
    val videoUri: Uri? = null
) {
    /** Seconds. */
    val duration: Double = if (duration.isFinite() && duration > 0) duration else DEFAULT_DURATION
}

internal class StoryPlaybackState(pages: List<StoryPage>) {
    enum class PauseReason { HIDDEN, BACKGROUND, TOUCH, SCROLLING, ACCESSIBILITY, DISMISSAL }
    enum class Change { NONE, PAGE, COMPLETED }

    private val durations = pages.map { it.duration }
    var index = 0
        private set
    var elapsed = 0.0
        private set
    private var mediaWaitElapsed = 0.0
    private var hasStartedProgress = false
    var isCompleted = false
        private set
    private val pauseReasons = mutableSetOf(PauseReason.HIDDEN)

    val isPaused: Boolean
        get() = pauseReasons.isNotEmpty() || isCompleted || durations.isEmpty()

    val progress: Float
        get() = durations.getOrNull(index)?.let { min(1.0, elapsed / it).toFloat() } ?: 0f

    fun isPaused(reason: PauseReason) = reason in pauseReasons

    fun setPaused(paused: Boolean, reason: PauseReason) {
        if (paused) pauseReasons.add(reason) else pauseReasons.remove(reason)
    }

    fun advance(interval: Double, isWaitingForMedia: Boolean = false): Change {
        if (isPaused || !interval.isFinite() || interval <= 0) return Change.NONE
        var progressInterval = interval
        if (!hasStartedProgress && isWaitingForMedia) {
            val wait = min(interval, max(0.0, MAXIMUM_MEDIA_WAIT - mediaWaitElapsed))
            mediaWaitElapsed += wait
            progressInterval -= wait
            if (mediaWaitElapsed < MAXIMUM_MEDIA_WAIT) return Change.NONE
        }
        hasStartedProgress = true
        elapsed = min(durations[index], elapsed + progressInterval)
        return if (progress >= 1f) next() else Change.NONE
    }

    fun next(): Change {
        if (isCompleted || durations.isEmpty()) return Change.NONE
        if (index + 1 >= durations.size) {
            elapsed = durations[index]
            isCompleted = true
            return Change.COMPLETED
        }
        index += 1
        resetPage()
        return Change.PAGE
    }

    fun previous(): Change {
        if (isCompleted || durations.isEmpty()) return Change.NONE
        index = max(0, index - 1)
        resetPage()
        return Change.PAGE
    }

    private fun resetPage() {
        elapsed = 0.0
        mediaWaitElapsed = 0.0
        hasStartedProgress = false
    }
}
