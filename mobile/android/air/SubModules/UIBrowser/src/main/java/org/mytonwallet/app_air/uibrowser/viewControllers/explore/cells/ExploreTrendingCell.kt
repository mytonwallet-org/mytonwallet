package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcore.models.MExploreSite

@SuppressLint("ViewConstructor")
class ExploreTrendingCell(
    context: Context,
    private val cellWidth: Int,
    private val onSiteTap: (site: MExploreSite) -> Unit,
) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    companion object {
        private const val AUTO_SCROLL_INTERVAL = 5000L
        private const val MANUAL_SCROLL_PAUSE = 5000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var currentIndex = 0
    private var itemCount = 0
    private var isAutoScrollEnabled = false
    private var springAnimation: SpringAnimation? = null

    @SuppressLint("ClickableViewAccessibility")
    private val horizontalScrollView = HorizontalScrollView(context).apply {
        id = generateViewId()
        layoutParams = ViewGroup.LayoutParams(
            MATCH_PARENT,
            WRAP_CONTENT
        )
        isHorizontalScrollBarEnabled = false
        setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    springAnimation?.cancel()
                    pauseAutoScroll()
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> resumeAutoScrollAfterDelay()
            }
            false
        }
    }

    private val container = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        layoutParams = ViewGroup.LayoutParams(
            MATCH_PARENT,
            WRAP_CONTENT
        )
    }

    private val autoScrollRunnable = object : Runnable {
        override fun run() {
            if (!isAutoScrollEnabled || itemCount <= 1) return
            currentIndex = (currentIndex + 1) % itemCount
            val child = container.getChildAt(currentIndex) ?: return
            animateScrollTo(child.left.toFloat())
            handler.postDelayed(this, AUTO_SCROLL_INTERVAL)
        }
    }

    private fun animateScrollTo(targetX: Float) {
        springAnimation?.cancel()

        val startX = horizontalScrollView.scrollX.toFloat()

        springAnimation = SpringAnimation(FloatValueHolder(startX)).apply {
            setStartValue(startX)
            spring = SpringForce(targetX).apply {
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
                stiffness = 250f
            }
            addUpdateListener { _, value, _ ->
                horizontalScrollView.scrollTo(value.toInt(), 0)
            }
            start()
        }
    }

    init {
        horizontalScrollView.addView(container)
        addView(horizontalScrollView)
        setConstraints {
            toTop(horizontalScrollView, 0f)
            toBottom(horizontalScrollView)
            toCenterX(horizontalScrollView)
        }
        updateTheme()
    }

    fun configure(sites: Array<MExploreSite>?) {
        container.removeAllViews()
        stopAutoScroll()

        val siteList = sites ?: emptyArray()
        itemCount = siteList.size
        currentIndex = 0

        for ((index, site) in siteList.withIndex()) {
            val cell = ExploreTrendingItemCell(
                context,
                cellWidth,
                site,
                onSiteTap
            )
            container.addView(cell)
            if (index > 0) {
                (cell.layoutParams as LinearLayout.LayoutParams).marginStart = -10.dp
            }
        }
        container.setPadding(0, 0, 0, 0)

        if (itemCount > 1) {
            startAutoScroll()
        }
    }

    private fun startAutoScroll() {
        isAutoScrollEnabled = true
        handler.removeCallbacks(autoScrollRunnable)
        handler.postDelayed(autoScrollRunnable, AUTO_SCROLL_INTERVAL)
    }

    private fun stopAutoScroll() {
        isAutoScrollEnabled = false
        handler.removeCallbacks(autoScrollRunnable)
        springAnimation?.cancel()
    }

    private fun pauseAutoScroll() {
        handler.removeCallbacks(autoScrollRunnable)
    }

    private fun resumeAutoScrollAfterDelay() {
        if (!isAutoScrollEnabled) return
        handler.removeCallbacks(autoScrollRunnable)
        syncIndexFromScroll()
        handler.postDelayed(autoScrollRunnable, MANUAL_SCROLL_PAUSE)
    }

    private fun syncIndexFromScroll() {
        if (itemCount == 0) return
        val scrollX = horizontalScrollView.scrollX
        var closestIndex = 0
        var closestDist = Int.MAX_VALUE
        for (i in 0 until itemCount) {
            val child = container.getChildAt(i) ?: continue
            val dist = kotlin.math.abs(child.left - scrollX)
            if (dist < closestDist) {
                closestDist = dist
                closestIndex = i
            }
        }
        currentIndex = closestIndex
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopAutoScroll()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (itemCount > 1) {
            startAutoScroll()
        }
    }

    override fun updateTheme() {
    }
}
