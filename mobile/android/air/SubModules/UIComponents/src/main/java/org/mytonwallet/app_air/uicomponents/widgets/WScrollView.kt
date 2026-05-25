package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.widget.ScrollView
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import java.lang.ref.WeakReference
import kotlin.math.max

@SuppressLint("ViewConstructor")
open class WScrollView(
    private val viewController: WeakReference<WViewController>
) : ScrollView(viewController.get()!!.context) {

    companion object {
        const val SCROLL_STATE_IDLE = 0
        const val SCROLL_STATE_DRAGGING = 1
        const val SCROLL_STATE_SETTLING = 2
    }

    init {
        id = generateViewId()
        isVerticalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_ALWAYS
    }

    var onScrollChange: ((Int) -> Unit)? = null
    var onScrollStateChange: ((Int) -> Unit)? = null

    var scrollState = SCROLL_STATE_IDLE
        private set

    private val scrollStateHandler by lazy(LazyThreadSafetyMode.NONE) {
        Handler(Looper.getMainLooper())
    }

    private var lastScrollY = 0

    private val scrollStateRunnable = object : Runnable {
        override fun run() {
            val currentY = scrollY

            if (currentY == lastScrollY) {
                setScrollState(SCROLL_STATE_IDLE)
            } else {
                lastScrollY = currentY
                setScrollState(SCROLL_STATE_SETTLING)
                scrollStateHandler.postDelayed(this, 50)
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (onScrollStateChange != null) {

            when (ev.actionMasked) {

                MotionEvent.ACTION_DOWN -> {
                    scrollStateHandler.removeCallbacks(scrollStateRunnable)
                    setScrollState(SCROLL_STATE_DRAGGING)
                }

                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_CANCEL -> {

                    lastScrollY = scrollY

                    scrollStateHandler.postDelayed(
                        scrollStateRunnable,
                        50
                    )
                }
            }
        }

        return super.onTouchEvent(ev)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()

        if (onScrollStateChange != null) {
            scrollStateHandler.removeCallbacks(scrollStateRunnable)
        }
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        onScrollChange?.invoke(t)
    }

    private fun setScrollState(state: Int) {
        if (scrollState == state) return

        scrollState = state
        onScrollStateChange?.invoke(state)
    }

    fun makeViewVisible(view: WView) {
        val vc = viewController.get()
        val topInset = vc?.navigationController?.getSystemBars()?.top ?: 0
        val bottomInset = max(
            vc?.window?.imeInsets?.bottom ?: 0,
            vc?.navigationController?.getSystemBars()?.bottom ?: 0
        )

        val minTopSpace = 100.dp
        val bottomPadding = 100.dp

        val rect = Rect()
        view.getDrawingRect(rect)
        offsetDescendantRectToMyCoords(view, rect)

        val visibleTop = scrollY + topInset + minTopSpace
        val visibleBottom = scrollY + height - bottomInset

        val desiredY = when {
            rect.bottom > visibleBottom ->
                rect.bottom - height + bottomInset + bottomPadding

            rect.top < visibleTop ->
                rect.top - topInset - minTopSpace

            else -> null
        }

        desiredY?.let { target ->
            val maxScroll = max(0, (getChildAt(0)?.height ?: 0) - height)
            post { smoothScrollTo(0, target.coerceIn(0, maxScroll)) }
        }
    }

}
