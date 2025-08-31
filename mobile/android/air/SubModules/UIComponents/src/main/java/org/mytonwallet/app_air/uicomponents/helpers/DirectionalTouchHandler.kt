package org.mytonwallet.app_air.uicomponents.helpers

import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import kotlin.math.abs

class DirectionalTouchHandler(
    private val verticalView: View,
    private val horizontalView: View,
    // Intercepted views will receive cancel touch event on scroll lock
    private val interceptedViews: List<View>,
    private val interceptedByVerticalScrollViews: List<View>,
    private val isVerticalScrollAllowed: () -> Boolean
) {

    private val touchSlop = ViewConfiguration.get(verticalView.context).scaledTouchSlop
    private var initialX = 0f
    private var initialY = 0f
    private var scrollDirectionLocked = false
    private var isVerticalScroll = false
    private var lastDownEvent: MotionEvent? = null

    fun dispatchTouch(view: View, event: MotionEvent): Boolean? {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> handleActionDown(event)

            MotionEvent.ACTION_MOVE -> return handleActionMove(view, event)

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> return handleActionUp(view, event)
        }
        return null
    }

    fun stopScroll() {
        val currentTime = SystemClock.uptimeMillis()
        val cancelEvent = MotionEvent.obtain(
            currentTime, currentTime,
            MotionEvent.ACTION_CANCEL, 0f, 0f, 0
        )

        verticalView.dispatchTouchEvent(cancelEvent)
        horizontalView.dispatchTouchEvent(cancelEvent)
        cancelEvent.recycle()

        scrollDirectionLocked = false
        isVerticalScroll = false
        lastDownEvent?.recycle()
        lastDownEvent = null
    }

    private fun handleActionDown(event: MotionEvent) {
        initialX = event.x
        initialY = event.y
        scrollDirectionLocked = false
        isVerticalScroll = false
        lastDownEvent?.recycle()
        lastDownEvent = MotionEvent.obtain(event)
    }

    private fun handleActionMove(view: View, event: MotionEvent): Boolean? {
        val dx = abs(event.x - initialX)
        val dy = abs(event.y - initialY)

        if (!scrollDirectionLocked) {
            when {
                dy > touchSlop && dy > dx -> {
                    if (!isVerticalScrollAllowed()) {
                        return false
                    }
                    lockScrollDirection(isVertical = true, view = view)
                    interceptViews(event)
                    if (view == verticalView) return null
                }

                dx > touchSlop && dx > dy -> {
                    lockScrollDirection(isVertical = false, view = view)
                    interceptViews(event)
                    if (view == horizontalView) return null
                }
            }
        }

        if (scrollDirectionLocked) {
            val targetView = if (isVerticalScroll) verticalView else horizontalView
            if (view != targetView) {
                targetView.dispatchTouchEvent(event)
                return false
            }
            return null
        }
        return null
    }

    private fun handleActionUp(view: View, event: MotionEvent): Boolean? {
        if (!scrollDirectionLocked) return null

        scrollDirectionLocked = false
        val targetView = if (isVerticalScroll) verticalView else horizontalView
        if (view != targetView) {
            targetView.dispatchTouchEvent(event)
            return false
        }
        return null
    }

    private fun lockScrollDirection(isVertical: Boolean, view: View) {
        scrollDirectionLocked = true
        isVerticalScroll = isVertical
        lastDownEvent?.let {
            val targetView = if (isVertical) verticalView else horizontalView
            if (view != targetView) {
                targetView.dispatchTouchEvent(it)
            }
            it.recycle()
            lastDownEvent = null
        }
    }

    private fun interceptViews(event: MotionEvent) {
        val cancelTime = SystemClock.uptimeMillis()
        val cancelEvent = MotionEvent.obtain(
            cancelTime, cancelTime,
            MotionEvent.ACTION_CANCEL, event.x, event.y, 0
        )
        interceptedViews.forEach { it.dispatchTouchEvent(cancelEvent) }
        if (isVerticalScroll)
            interceptedByVerticalScrollViews.forEach { it.dispatchTouchEvent(cancelEvent) }
    }
}
