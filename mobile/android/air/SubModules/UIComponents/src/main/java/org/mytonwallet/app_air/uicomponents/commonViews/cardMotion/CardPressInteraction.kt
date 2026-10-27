package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import kotlin.math.hypot

/** Observes a stationary host; only a recognized hold owns the gesture. */
class CardPressInteraction(
    private val host: View,
    private val surface: CardPressSurfaceView,
    private val isAllowed: () -> Boolean,
    private val canBeginPlay: (Float, Float) -> Boolean,
    private val cancelChildTouch: () -> Unit,
    private val onPlayBegan: () -> Unit,
    private val onPlayTouch: (Float, Float) -> Unit,
    private val onPose: (Float, Float, Float) -> Unit
) {
    private val motion = CardPressMotion()
    private var pointerId = MotionEvent.INVALID_POINTER_ID
    private var initialX = 0f
    private var initialY = 0f
    private var latestX = 0f
    private var latestY = 0f
    private var playEligible = false
    private var childrenCancelled = true
    private var minimumPressRemaining = 0.0
    private var releaseAfter: Double? = null
    private var returningToRest = false
    private var framePosted = false
    private var lastFrameNanos = 0L
    private val scrollLockReleases = ArrayList<() -> Unit>()

    var isPlaying = false
        private set

    private val beginPlay = Runnable {
        if (pointerId == MotionEvent.INVALID_POINTER_ID || !playEligible || !isAllowed() ||
            !canBeginPlay(initialX, initialY)
        ) {
            return@Runnable
        }
        var ancestor = host.parent
        while (ancestor is View) {
            if (ancestor is CardPlayScrollHost) {
                val release = ancestor.acquireCardPlayScrollLock()
                if (release == null) {
                    releaseScrollLocks()
                    return@Runnable
                }
                scrollLockReleases.add(release)
            }
            ancestor = ancestor.parent
        }
        isPlaying = true
        host.parent?.requestDisallowInterceptTouchEvent(true)
        cancelChildren()
        onPlayTouch(latestX, latestY)
        onPlayBegan()
    }

    private val frameCallback = Choreographer.FrameCallback { frameTimeNanos ->
        framePosted = false
        if (!host.isAttachedToWindow || !host.hasWindowFocus()) {
            reset()
            return@FrameCallback
        }
        if (!isAllowed() && pointerId != MotionEvent.INVALID_POINTER_ID) release(cancelled = true)
        val dt = if (lastFrameNanos == 0L) {
            1.0 / 60.0
        } else {
            ((frameTimeNanos - lastFrameNanos) / 1_000_000_000.0).coerceIn(0.0, 0.1)
        }
        lastFrameNanos = frameTimeNanos
        minimumPressRemaining = (minimumPressRemaining - dt).coerceAtLeast(0.0)
        releaseAfter?.let { remaining ->
            if (remaining <= dt) {
                releaseAfter = null
                motion.release()
            } else {
                releaseAfter = remaining - dt
            }
        }
        motion.advance(dt)
        renderPose()
        if (!motion.isSettled || releaseAfter != null || minimumPressRemaining > 0.0) {
            scheduleFrame()
        } else {
            lastFrameNanos = 0L
            returningToRest = false
        }
    }

    /** The host calls this before dispatching into its transformed children. */
    fun observe(event: MotionEvent): Boolean {
        val wasTracking = pointerId != MotionEvent.INVALID_POINTER_ID
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (!isAllowed()) {
                    if (!returningToRest) reset()
                    return false
                }
                finishPlay()
                returningToRest = false
                if (host.width == 0 || host.height == 0) {
                    reset()
                    return false
                }
                pointerId = event.getPointerId(0)
                childrenCancelled = false
                initialX = event.x
                initialY = event.y
                minimumPressRemaining = 0.07
                releaseAfter = null
                playEligible = canBeginPlay(initialX, initialY)
                pressAt(event.x, event.y)
                if (playEligible) host.postDelayed(beginPlay, 150L)
            }

            MotionEvent.ACTION_MOVE -> {
                val index = event.findPointerIndex(pointerId)
                if (index >= 0) {
                    val x = event.getX(index)
                    val y = event.getY(index)
                    if (!isPlaying && hypot(x - initialX, y - initialY) >
                        12f * host.resources.displayMetrics.density
                    ) {
                        playEligible = false
                        host.removeCallbacks(beginPlay)
                    }
                    pressAt(x, y)
                }
            }

            MotionEvent.ACTION_UP -> {
                val index = event.findPointerIndex(pointerId)
                if (index >= 0) pressAt(event.getX(index), event.getY(index))
                release()
            }

            MotionEvent.ACTION_POINTER_UP -> {
                if (event.getPointerId(event.actionIndex) == pointerId) release()
            }

            MotionEvent.ACTION_CANCEL -> release()
        }
        return wasTracking || pointerId != MotionEvent.INVALID_POINTER_ID
    }

    private fun pressAt(x: Float, y: Float) {
        latestX = x
        latestY = y
        if (isPlaying) onPlayTouch(x, y)
        motion.press(2.0 * x / host.width - 1.0, 2.0 * y / host.height - 1.0)
        scheduleFrame()
    }

    fun release(cancelled: Boolean = false) {
        val wasTracking = pointerId != MotionEvent.INVALID_POINTER_ID
        if (wasTracking && cancelled) cancelChildren()
        pointerId = MotionEvent.INVALID_POINTER_ID
        finishPlay()
        if (!wasTracking) return
        if (minimumPressRemaining > 0.0) {
            releaseAfter = minimumPressRemaining
        } else {
            motion.release()
        }
        scheduleFrame()
    }

    /** Continue only the existing spring when scrolling takes ownership. */
    fun deactivate(animated: Boolean) {
        if (!animated) {
            reset()
            return
        }
        if (pointerId != MotionEvent.INVALID_POINTER_ID) cancelChildren()
        pointerId = MotionEvent.INVALID_POINTER_ID
        finishPlay()
        minimumPressRemaining = 0.0
        releaseAfter = null
        motion.release()
        returningToRest = !motion.isSettled
        if (returningToRest) scheduleFrame()
    }

    /** Reparenting the same visible card pauses callbacks, not its spring state. */
    fun pauseForReparent() {
        deactivate(animated = true)
        if (framePosted) Choreographer.getInstance().removeFrameCallback(frameCallback)
        framePosted = false
        lastFrameNanos = 0L
    }

    fun resumeAfterReparent() {
        if (returningToRest && !motion.isSettled) scheduleFrame()
    }

    fun reset() {
        returningToRest = false
        if (pointerId != MotionEvent.INVALID_POINTER_ID) cancelChildren()
        pointerId = MotionEvent.INVALID_POINTER_ID
        finishPlay()
        if (framePosted) Choreographer.getInstance().removeFrameCallback(frameCallback)
        framePosted = false
        lastFrameNanos = 0L
        minimumPressRemaining = 0.0
        releaseAfter = null
        motion.reset()
        renderPose()
    }

    fun onLayout() {
        surface.updatePose(motion)
    }

    private fun finishPlay() {
        host.removeCallbacks(beginPlay)
        playEligible = false
        releaseScrollLocks()
        if (!isPlaying) return
        isPlaying = false
        host.parent?.requestDisallowInterceptTouchEvent(false)
    }

    private fun releaseScrollLocks() {
        scrollLockReleases.asReversed().forEach { it() }
        scrollLockReleases.clear()
    }

    private fun cancelChildren() {
        if (childrenCancelled) return
        childrenCancelled = true
        cancelChildTouch()
    }

    private fun renderPose() {
        surface.updatePose(motion)
        if (!returningToRest && isAllowed()) {
            onPose(motion.lightX, motion.lightY, motion.engagement)
        }
    }

    private fun scheduleFrame() {
        if (framePosted || !host.isAttachedToWindow) return
        framePosted = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }
}
