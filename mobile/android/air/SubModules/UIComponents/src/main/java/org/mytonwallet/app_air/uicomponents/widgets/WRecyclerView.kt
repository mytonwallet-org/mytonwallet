package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.ViewConfiguration
import kotlin.math.abs
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import me.everything.android.ui.overscroll.OverScrollBounceEffectDecoratorBase
import me.everything.android.ui.overscroll.VerticalOverScrollBounceEffectDecorator
import me.everything.android.ui.overscroll.adapters.RecyclerViewOverScrollDecorAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
open class WRecyclerView(context: Context) : RecyclerView(context) {
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
                        if (recyclerView.scrollState == SCROLL_STATE_IDLE)
                            viewControllerRef?.get()?.heavyAnimationDone()
                    }, 100)
                } else
                    viewControllerRef?.get()?.heavyAnimationInProgress()
            }
        })
    }

    private fun canScrollDown(): Boolean {
        return ((layoutManager as? LinearLayoutManager)?.findLastCompletelyVisibleItemPosition() !=
            (adapter?.itemCount ?: 0) - 1)
    }

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
        if (overscrollListener != null)
            return
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
                        if (overscrollDetected)
                            return false

                        val deltaX = e.x - startX
                        val deltaY = e.y - startY

                        if (abs(deltaX) > abs(deltaY))
                            return false

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
                override fun isInAbsoluteStart(): Boolean {
                    if (layoutManager?.canScrollVertically() == false)
                        return false
                    return super.isInAbsoluteStart()
                }

                override fun isInAbsoluteEnd(): Boolean {
                    if (layoutManager?.canScrollVertically() == false)
                        return false
                    return super.isInAbsoluteEnd()
                }
            },
            OverScrollBounceEffectDecoratorBase.DEFAULT_DECELERATE_FACTOR
        )

        verticalOverScrollBounceEffectDecorator?.setOverScrollUpdateListener { _, isTouchActive, newState, offset, velocity ->
            onOverScrollListener?.invoke(isTouchActive, newState, offset, velocity)
        }
    }

    fun removeOverScroll() {
        verticalOverScrollBounceEffectDecorator?.detach()
    }

    fun setMaxOverscrollOffset(value: Float) {
        verticalOverScrollBounceEffectDecorator?.setMaxOffset(value)
    }

    fun getOverScrollOffset(): Float {
        return verticalOverScrollBounceEffectDecorator?.overScrollOffset ?: 0f
    }

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
}
