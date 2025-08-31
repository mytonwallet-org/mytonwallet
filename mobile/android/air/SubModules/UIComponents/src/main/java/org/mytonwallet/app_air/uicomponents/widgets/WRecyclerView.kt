package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
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
