package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.dynamicanimation.animation.FloatPropertyCompat
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSnapHelper
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import kotlin.math.abs

@SuppressLint("ViewConstructor")
class ExploreTrendingCell(
    context: Context,
    private val cellWidth: Int,
    private val onSiteTap: (site: MExploreSite) -> Unit,
) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    companion object {
        private const val AUTO_SCROLL_INTERVAL = 5000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var currentIndex = 0
    private var itemCount = 0
    private var isAutoScrollEnabled = false
    private var isUserScrolling = false
    private var springAnim: SpringAnimation? = null
    private var animatedScrollOffset = 0f

    private val scrollProperty = object : FloatPropertyCompat<RecyclerView>("scrollX") {
        override fun getValue(view: RecyclerView): Float {
            animatedScrollOffset = view.computeHorizontalScrollOffset().toFloat()
            return animatedScrollOffset
        }

        override fun setValue(view: RecyclerView, value: Float) {
            val delta = value - animatedScrollOffset
            val dx = delta.toInt()
            if (dx != 0) {
                view.scrollBy(dx, 0)
                animatedScrollOffset += dx
            }
        }
    }

    private val linearLayoutManager =
        LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)

    private val snapHelper = object : LinearSnapHelper() {
        override fun onFling(velocityX: Int, velocityY: Int): Boolean {
            if (itemCount == 0) return false
            val currentPos = closestPosition()
            val targetPos = when {
                velocityX > 300 -> currentPos + 1
                velocityX < -300 -> currentPos - 1
                else -> currentPos
            }.coerceIn(0, itemCount - 1)
            currentIndex = targetPos
            springScrollTo(targetPos, velocityX.toFloat())
            if (isUserScrolling) {
                isUserScrolling = false
                startAutoScroll()
            }
            return true
        }
    }

    private fun beginUserScroll() {
        if (isUserScrolling) return
        isUserScrolling = true
        springAnim?.cancel()
        stopAutoScroll()
    }

    private val recyclerView = WRecyclerView(context).apply {
        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        isHorizontalScrollBarEnabled = false
        layoutManager = linearLayoutManager
        addItemDecoration(object : RecyclerView.ItemDecoration() {
            override fun getItemOffsets(
                outRect: Rect,
                view: View,
                parent: RecyclerView,
                state: RecyclerView.State
            ) {
                if (parent.getChildAdapterPosition(view) > 0) outRect.left = (-10).dp
            }
        })
        addOnItemTouchListener(object : RecyclerView.OnItemTouchListener {
            override fun onInterceptTouchEvent(rv: RecyclerView, event: MotionEvent): Boolean {
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    beginUserScroll()
                }
                return false
            }

            override fun onTouchEvent(rv: RecyclerView, event: MotionEvent) = Unit

            override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) = Unit
        })
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(rv: RecyclerView, newState: Int) {
                when (newState) {
                    RecyclerView.SCROLL_STATE_DRAGGING -> {
                        beginUserScroll()
                    }

                    RecyclerView.SCROLL_STATE_IDLE -> {
                        if (isUserScrolling) {
                            isUserScrolling = false
                            currentIndex = closestPosition()
                            startAutoScroll()
                        }
                    }
                }
            }
        })
    }

    private val trendingAdapter = object : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        var sites: List<MExploreSite> = emptyList()
            private set

        fun setSites(newSites: List<MExploreSite>) {
            sites = newSites
            recyclerView.recycledViewPool.clear()
            @Suppress("NotifyDataSetChanged")
            notifyDataSetChanged()
        }

        override fun getItemViewType(position: Int) = position

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder =
            object : RecyclerView.ViewHolder(
                ExploreTrendingItemCell(context, cellWidth, sites[viewType], onSiteTap)
            ) {}

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {}

        override fun getItemCount() = sites.size
    }

    private val autoScrollRunnable = object : Runnable {
        override fun run() {
            if (!isAutoScrollEnabled || itemCount <= 1) return
            currentIndex = (currentIndex + 1) % itemCount
            springScrollTo(currentIndex)
            handler.postDelayed(this, AUTO_SCROLL_INTERVAL)
        }
    }

    init {
        snapHelper.attachToRecyclerView(recyclerView)
        recyclerView.adapter = trendingAdapter
        addView(recyclerView)
        setConstraints {
            toTop(recyclerView, 0f)
            toBottom(recyclerView)
            toCenterX(recyclerView)
        }
        updateTheme()
    }

    fun configure(sites: List<MExploreSite>?) {
        if (sites == trendingAdapter.sites)
            return

        stopAutoScroll()

        itemCount = sites?.size ?: 0
        currentIndex = 0

        trendingAdapter.setSites(sites ?: emptyList())
        recyclerView.scrollToPosition(0)

        startAutoScroll()
    }

    private fun closestPosition(): Int =
        (0..itemCount).minByOrNull { index ->
            linearLayoutManager.findViewByPosition(index)?.let { abs(it.left) } ?: Int.MAX_VALUE
        } ?: currentIndex

    private fun targetScrollOffset(position: Int): Float =
        linearLayoutManager.findViewByPosition(position)?.let { view ->
            val distance =
                snapHelper.calculateDistanceToFinalSnap(linearLayoutManager, view)?.get(0) ?: 0
            recyclerView.computeHorizontalScrollOffset().toFloat() + distance
        } ?: (-10f).dp

    private fun springScrollTo(position: Int, velocityX: Float = 0f) {
        springAnim?.cancel()
        animatedScrollOffset = recyclerView.computeHorizontalScrollOffset().toFloat()
        val target = targetScrollOffset(position)
        springAnim = SpringAnimation(recyclerView, scrollProperty, target).apply {
            spring.dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            spring.stiffness = 500f
            if (velocityX != 0f) setStartVelocity(velocityX)
            addEndListener { _, canceled, _, _ ->
                if (canceled) return@addEndListener
                animatedScrollOffset = recyclerView.computeHorizontalScrollOffset().toFloat()
                linearLayoutManager.findViewByPosition(position)?.let { view ->
                    val finalAdjustment =
                        snapHelper.calculateDistanceToFinalSnap(linearLayoutManager, view)?.get(0)
                            ?: 0
                    if (finalAdjustment != 0) {
                        recyclerView.scrollBy(finalAdjustment, 0)
                        animatedScrollOffset =
                            recyclerView.computeHorizontalScrollOffset().toFloat()
                    }
                }
            }
            start()
        }
    }

    private fun startAutoScroll() {
        if (isAutoScrollEnabled || itemCount < 2 || !isAttachedToWindow) return
        isAutoScrollEnabled = true
        handler.postDelayed(autoScrollRunnable, AUTO_SCROLL_INTERVAL)
    }

    private fun stopAutoScroll() {
        if (!isAutoScrollEnabled) return
        isAutoScrollEnabled = false
        handler.removeCallbacks(autoScrollRunnable)
        springAnim?.cancel()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopAutoScroll()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startAutoScroll()
    }

    override fun updateTheme() {
    }
}
