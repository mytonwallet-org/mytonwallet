package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.drawable.ColorDrawable
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.EdgeEffect
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import kotlin.math.abs
import me.everything.android.ui.overscroll.OverScrollBounceEffectDecoratorBase
import me.everything.android.ui.overscroll.VerticalOverScrollBounceEffectDecorator
import me.everything.android.ui.overscroll.adapters.RecyclerViewOverScrollDecorAdapter
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.glass.GlassCaptureHost
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
open class WRecyclerView(context: Context) :
    RecyclerView(context),
    GlassCaptureHost {

    override fun glassDrawChild(canvas: Canvas, child: View, drawingTime: Long): Boolean =
        drawChild(canvas, child, drawingTime)
    init {
        id = generateViewId()
        isVerticalScrollBarEnabled = false
        setHasFixedSize(true)
    }

    private var viewControllerRef: WeakReference<WViewController>? = null

    constructor(viewController: WViewController) : this(viewController.context) {
        this.viewControllerRef = WeakReference(viewController)
        this.addOnScrollListener(object : OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (newState == SCROLL_STATE_IDLE) {
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (recyclerView.scrollState == SCROLL_STATE_IDLE) {
                            viewControllerRef?.get()?.heavyAnimationDone()
                        }
                    }, 100)
                } else {
                    viewControllerRef?.get()?.heavyAnimationInProgress()
                }
            }
        })
    }

    private fun canScrollDown(): Boolean = (
        (layoutManager as? LinearLayoutManager)?.findLastCompletelyVisibleItemPosition() !=
            (adapter?.itemCount ?: 0) - 1
        )

    override fun canScrollVertically(direction: Int): Boolean {
        if (direction == 1) {
            return super.canScrollVertically(direction) && canScrollDown()
        }
        return super.canScrollVertically(direction)
    }

    private var verticalOverScrollBounceEffectDecorator: VerticalOverScrollBounceEffectDecorator? =
        null

    override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
        // Reject any multi-touch events
        return if (e.pointerCount > 1) {
            true
        } else {
            super.onInterceptTouchEvent(e)
        }
    }

    private var overscrollListener: OnItemTouchListener? = null

    fun disallowInterceptOnOverscroll() {
        if (overscrollListener != null) return
        overscrollListener = object : OnItemTouchListener {
            private var startX = 0f
            private var startY = 0f
            private var overscrollDetected = false
            private val mSwipeSlop = ViewConfiguration.get(context).scaledTouchSlop

            override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = e.x
                        startY = e.y
                    }

                    MotionEvent.ACTION_MOVE -> {
                        if (overscrollDetected) return false

                        val deltaX = e.x - startX
                        val deltaY = e.y - startY

                        if (abs(deltaX) > abs(deltaY)) return false

                        val atTop = !rv.canScrollVertically(-1)
                        val atBottom = !rv.canScrollVertically(1)

                        if ((atTop && deltaY > mSwipeSlop) || (atBottom && deltaY < -mSwipeSlop)) {
                            if (!overscrollDetected) {
                                overscrollDetected = true
                                parent?.requestDisallowInterceptTouchEvent(true)
                            }
                        }
                    }

                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        overscrollDetected = false
                        rv.parent?.requestDisallowInterceptTouchEvent(false)
                    }
                }
                return false
            }

            override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) {}
            override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {}
        }
        addOnItemTouchListener(overscrollListener!!)
    }

    fun onDestroy() {
        clearOnScrollListeners()
        overscrollListener?.let { it ->
            removeOnItemTouchListener(it)
        }
        adapter = null
    }

    fun cancelActiveGesture() {
        suppressLayout(true)
        suppressLayout(false)
    }

    // OVERSCROLL //////////////////////////////////////////////////////////////////////////////////
    fun setupOverScroll() {
        verticalOverScrollBounceEffectDecorator?.detach()
        verticalOverScrollBounceEffectDecorator = VerticalOverScrollBounceEffectDecorator(
            object : RecyclerViewOverScrollDecorAdapter(this) {
                // canScrollVertically() works off the estimated scroll range, which is unreliable
                // with mixed item heights (smooth scrollbar); the edges are decided from the laid-out
                // children instead.
                override fun isInAbsoluteStart(): Boolean {
                    if (layoutManager?.canScrollVertically() == false) return false
                    val lm = layoutManager as? LinearLayoutManager
                        ?: return super.isInAbsoluteStart()
                    if ((adapter?.itemCount ?: 0) == 0) return true
                    val first = lm.findFirstVisibleItemPosition()
                    if (first == NO_POSITION) return super.isInAbsoluteStart()
                    if (first != 0) return false
                    val child = lm.findViewByPosition(0) ?: return super.isInAbsoluteStart()
                    return lm.getDecoratedTop(child) >= paddingTop
                }

                // The decorator only bounces at the top; the bottom edge keeps the system
                // stretch effect.
                override fun isInAbsoluteEnd(): Boolean = false
            },
            OverScrollBounceEffectDecoratorBase.DEFAULT_DECELERATE_FACTOR
        )

        verticalOverScrollBounceEffectDecorator?.setOverScrollUpdateListener {
                _,
                isTouchActive,
                newState,
                offset,
                velocity
            ->
            onOverScrollListener?.invoke(isTouchActive, newState, offset, velocity)
        }

        // The decorator disables native over-scroll entirely; re-enable it with the top edge
        // suppressed so the bottom edge keeps the system stretch effect while the decorator
        // owns the top.
        overScrollMode = OVER_SCROLL_ALWAYS
        if (edgeEffectFactory !== topSuppressedEdgeEffectFactory) {
            edgeEffectFactory = topSuppressedEdgeEffectFactory
        }
    }

    // Suppresses the top edge effect only while the decorator is attached; the factory stays
    // installed after the decorator is removed, because replacing it destroys glows that may
    // still be animating a release.
    private val topSuppressedEdgeEffectFactory = object : EdgeEffectFactory() {
        override fun createEdgeEffect(view: RecyclerView, direction: Int): EdgeEffect {
            if (direction != DIRECTION_TOP) return super.createEdgeEffect(view, direction)
            return object : EdgeEffect(view.context) {
                override fun onPull(deltaDistance: Float) {
                    if (!hasOverScroll) super.onPull(deltaDistance)
                }

                override fun onPull(deltaDistance: Float, displacement: Float) {
                    if (!hasOverScroll) super.onPull(deltaDistance, displacement)
                }

                override fun onPullDistance(deltaDistance: Float, displacement: Float): Float =
                    if (hasOverScroll) 0f else super.onPullDistance(deltaDistance, displacement)

                override fun onAbsorb(velocity: Int) {
                    if (!hasOverScroll) super.onAbsorb(velocity)
                }
            }
        }
    }

    fun removeOverScroll() {
        verticalOverScrollBounceEffectDecorator?.detach()
        verticalOverScrollBounceEffectDecorator = null
    }

    val hasOverScroll: Boolean
        get() = verticalOverScrollBounceEffectDecorator != null

    fun setMaxOverscrollOffset(value: Float) {
        verticalOverScrollBounceEffectDecorator?.setMaxOffset(value)
    }

    fun getOverScrollOffset(): Float =
        verticalOverScrollBounceEffectDecorator?.overScrollOffset ?: 0f

    private var onOverScrollListener: ((Boolean, Int, Float, Float) -> Unit)? = null
    fun setOnOverScrollListener(onOverScrollListener: ((Boolean, Int, Float, Float) -> Unit)?) {
        this.onOverScrollListener = onOverScrollListener
    }

    fun setBounceBackSkipValue(value: Int) {
        verticalOverScrollBounceEffectDecorator?.setBounceBackSkipValue(value)
    }

    fun comeBackFromOverScrollValue(value: Int) {
        verticalOverScrollBounceEffectDecorator?.comeBackFromOverScrollValue(value)
    }

    fun scrollToOverScroll(value: Int) {
        verticalOverScrollBounceEffectDecorator?.scrollTo(value)
    }

    private var backgroundAnimator: ValueAnimator? = null

    override fun setBackgroundColor(color: Int) {
        backgroundAnimator?.cancel()
        backgroundAnimator = null
        super.setBackgroundColor(color)
    }

    fun animateBackgroundColor(toColor: Int, duration: Long = AnimationConstants.QUICK_ANIMATION) {
        val fromColor = (background as? ColorDrawable)?.color ?: toColor
        if (fromColor == toColor) return
        backgroundAnimator?.cancel()
        backgroundAnimator = null
        if (!WGlobalStorage.getAreAnimationsActive()) {
            setBackgroundColor(toColor)
            return
        }
        backgroundAnimator = ValueAnimator.ofArgb(fromColor, toColor).apply {
            this.duration = duration
            addUpdateListener { super.setBackgroundColor(it.animatedValue as Int) }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    backgroundAnimator = null
                }
            })
            start()
        }
    }
}
