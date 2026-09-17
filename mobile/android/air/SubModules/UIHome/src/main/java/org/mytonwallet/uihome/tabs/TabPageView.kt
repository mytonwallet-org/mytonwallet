package org.mytonwallet.uihome.tabs

import android.content.Context
import android.graphics.Rect
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import kotlin.math.abs
import org.mytonwallet.app_air.uicomponents.base.WNavigationController

internal class TabPageView(context: Context, private val tabPager: ViewPager2) :
    FrameLayout(context) {
    init {
        layoutParams = RecyclerView.LayoutParams(MATCH_PARENT, MATCH_PARENT)
    }

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val hitRect = Rect()
    private var initialRawX = 0f
    private var initialRawY = 0f
    private var lastRawX = 0f
    private var trackingGesture = false
    private var horizontalGesture = false
    private var verticalGesture = false
    private var allowParentPager = false
    private var nestedOwnsHorizontalGesture = false

    fun bind(navigationController: WNavigationController) {
        if (childCount == 1 && getChildAt(0) === navigationController) return
        removeAllViews()
        (navigationController.parent as? ViewGroup)?.removeView(navigationController)
        addView(navigationController, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    fun unbind() {
        // Recycling mid-swipe would otherwise strand the fake drag, since only this view's
        // touch stream ends it, and every later beginFakeDrag() would fail.
        if (tabPager.isFakeDragging) tabPager.endFakeDrag()
        resetGestureTracking()
        removeAllViews()
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                initialRawX = event.rawX
                initialRawY = event.rawY
                lastRawX = event.rawX
                trackingGesture = true
                horizontalGesture = false
                verticalGesture = false
                val startedInHorizontalChild =
                    hasTouchedScrollableChild(
                        this,
                        initialRawX.toInt(),
                        initialRawY.toInt(),
                        -1
                    ) ||
                        hasTouchedScrollableChild(
                            this,
                            initialRawX.toInt(),
                            initialRawY.toInt(),
                            1
                        )
                allowParentPager = !startedInHorizontalChild
                super.requestDisallowInterceptTouchEvent(!allowParentPager)
            }

            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - initialRawX
                val dy = event.rawY - initialRawY
                val stepDx = event.rawX - lastRawX
                lastRawX = event.rawX
                if (!horizontalGesture && !verticalGesture) {
                    if (abs(dx) > touchSlop && abs(dx) > abs(dy)) {
                        horizontalGesture = true
                    } else if (abs(dy) > touchSlop && abs(dy) > abs(dx)) {
                        verticalGesture = true
                        allowParentPager = false
                        super.requestDisallowInterceptTouchEvent(true)
                    }
                }
                if (horizontalGesture) {
                    if (tabPager.isFakeDragging) {
                        tabPager.fakeDragBy(stepDx)
                        return true
                    }
                    if (!nestedOwnsHorizontalGesture) {
                        val direction = if (dx < 0f) 1 else -1
                        val nestedCanScroll = hasTouchedScrollableChild(
                            this,
                            initialRawX.toInt(),
                            initialRawY.toInt(),
                            direction
                        )
                        if (!allowParentPager &&
                            !nestedCanScroll &&
                            tabPager.isUserInputEnabled &&
                            tabPager.beginFakeDrag()
                        ) {
                            val cancelEvent = MotionEvent.obtain(event).apply {
                                action = MotionEvent.ACTION_CANCEL
                            }
                            super.dispatchTouchEvent(cancelEvent)
                            cancelEvent.recycle()
                            tabPager.fakeDragBy(stepDx)
                            return true
                        }
                        nestedOwnsHorizontalGesture = nestedCanScroll
                        allowParentPager = !nestedCanScroll
                        super.requestDisallowInterceptTouchEvent(!allowParentPager)
                    }
                }
            }
        }

        if (
            (
                event.actionMasked == MotionEvent.ACTION_UP ||
                    event.actionMasked == MotionEvent.ACTION_CANCEL
                ) &&
            tabPager.isFakeDragging
        ) {
            tabPager.endFakeDrag()
            resetGestureTracking()
            return true
        }
        val handled = super.dispatchTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_UP ||
            event.actionMasked == MotionEvent.ACTION_CANCEL
        ) {
            resetGestureTracking()
        }
        return handled
    }

    private fun resetGestureTracking() {
        trackingGesture = false
        horizontalGesture = false
        verticalGesture = false
        allowParentPager = false
        nestedOwnsHorizontalGesture = false
        super.requestDisallowInterceptTouchEvent(false)
    }

    override fun requestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {
        if (trackingGesture) {
            super.requestDisallowInterceptTouchEvent(!allowParentPager)
        } else {
            super.requestDisallowInterceptTouchEvent(disallowIntercept)
        }
    }

    private fun hasTouchedScrollableChild(
        candidate: View,
        rawX: Int,
        rawY: Int,
        direction: Int
    ): Boolean {
        if (!candidate.isShown ||
            !candidate.getGlobalVisibleRect(hitRect) ||
            !hitRect.contains(rawX, rawY)
        ) {
            return false
        }
        if (candidate is ViewGroup) {
            for (index in candidate.childCount - 1 downTo 0) {
                if (
                    hasTouchedScrollableChild(
                        candidate.getChildAt(index),
                        rawX,
                        rawY,
                        direction
                    )
                ) {
                    return true
                }
            }
        }
        return candidate !== this && candidate.canScrollHorizontally(direction)
    }
}
