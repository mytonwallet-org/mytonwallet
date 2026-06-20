package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.widget.HorizontalScrollView

// HorizontalScrollView that tracks a coarse scroll state (idle / dragging / settling),
// mirroring WScrollView's vertical implementation. Consumers use scrollState to avoid
// disruptive work (e.g. a full reload) while the user is interacting with the row.
//
// It also preserves the user's scroll position across reloads. The host is laid out inside a
// split (sidebar + detail) layout whose measure cycle produces transient passes where this view
// is measured WIDER than its stable visible width. In those wide passes the content fits and the
// framework's HorizontalScrollView.onLayout() snaps scrollX back to 0; the position then sticks
// at 0 once the view returns to its narrower width. We remember the user's intended position and
// re-apply it on every layout pass (clamped to that pass's range), so the narrow pass restores it.
open class ScrollStateHorizontalScrollView(
    context: Context
) : HorizontalScrollView(context) {

    companion object {
        const val SCROLL_STATE_IDLE = 0
        const val SCROLL_STATE_DRAGGING = 1
        const val SCROLL_STATE_SETTLING = 2
    }

    var onScrollStateChange: ((Int) -> Unit)? = null
    var onScrollChange: (() -> Unit)? = null

    fun horizontalScrollOffset(): Int = computeHorizontalScrollOffset()

    var scrollState = SCROLL_STATE_IDLE
        private set

    private val scrollStateHandler by lazy(LazyThreadSafetyMode.NONE) {
        Handler(Looper.getMainLooper())
    }

    private var lastScrollX = 0

    // The user's intended scroll position, captured while they interact. Re-applied after layout
    // so a spurious wide-measure pass can't permanently reset it. -1 means "no position to keep"
    // (the user has not scrolled, or has explicitly returned to the start).
    private var pendingScrollX = -1

    // True only while super.onLayout() is running, so onScrollChanged can tell a layout-driven
    // reset (to be ignored) from a real user/fling scroll (to be remembered).
    private var inLayout = false

    private val scrollStateRunnable = object : Runnable {
        override fun run() {
            val currentX = scrollX

            if (currentX == lastScrollX) {
                setScrollState(SCROLL_STATE_IDLE)
            } else {
                lastScrollX = currentX
                setScrollState(SCROLL_STATE_SETTLING)
                scrollStateHandler.postDelayed(this, 50)
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {

            MotionEvent.ACTION_DOWN -> {
                scrollStateHandler.removeCallbacks(scrollStateRunnable)
                setScrollState(SCROLL_STATE_DRAGGING)
            }

            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> {
                lastScrollX = scrollX
                scrollStateHandler.postDelayed(scrollStateRunnable, 50)
            }
        }

        return super.onTouchEvent(ev)
    }

    private fun maxScrollX(): Int {
        val child = getChildAt(0) ?: return 0
        return (child.width - (width - paddingLeft - paddingRight)).coerceAtLeast(0)
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        if (!inLayout) {
            pendingScrollX = l
        }
        onScrollChange?.invoke()
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        inLayout = true
        super.onLayout(changed, l, t, r, b)
        inLayout = false
        if (pendingScrollX > 0) {
            val target = pendingScrollX.coerceAtMost(maxScrollX())
            if (target != scrollX) {
                super.scrollTo(target, scrollY)
            }
        }
    }

    fun resetScroll() {
        pendingScrollX = -1
        if (scrollX != 0) {
            super.scrollTo(0, 0)
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        scrollStateHandler.removeCallbacks(scrollStateRunnable)
    }

    private fun setScrollState(state: Int) {
        if (scrollState == state) return

        scrollState = state
        onScrollStateChange?.invoke(state)
    }
}
