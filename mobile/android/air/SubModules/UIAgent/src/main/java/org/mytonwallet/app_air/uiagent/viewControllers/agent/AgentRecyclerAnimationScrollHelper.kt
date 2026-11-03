package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.view.View
import android.view.ViewTreeObserver
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentPreDrawBinding
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * Port of Telegram's `RecyclerAnimationScrollHelper` for scrolling down. The destination lays out at once, and the
 * rows on screen slide out in the list's overlay, where the layout manager never finds them.
 */
internal class AgentRecyclerAnimationScrollHelper(private val recyclerView: RecyclerView) {
    private var pendingLayout: View.OnLayoutChangeListener? = null
    private var animator: ValueAnimator? = null
    private val leavingViews = mutableListOf<View>()
    private val movedViews = mutableSetOf<View>()
    private val heldHolders = mutableListOf<RecyclerView.ViewHolder>()
    private var scrollLength = 0
    private var progress = 0f

    private var stripHead: View? = null
    private var stripHeadTop = 0

    private val frameUpdater = ViewTreeObserver.OnPreDrawListener {
        applyFrame()
        true
    }
    private var frameBinding: AgentPreDrawBinding? = null

    val isRunning: Boolean get() = pendingLayout != null || animator != null

    /** With animations off or nothing on screen, the list just jumps. */
    fun scrollDown(jump: () -> Unit) {
        if (isRunning) return
        val count = recyclerView.childCount
        if (count == 0 || !WGlobalStorage.getAreAnimationsActive() ||
            !recyclerView.isAttachedToWindow || recyclerView.isLayoutSuppressed
        ) {
            jump()
            return
        }
        recyclerView.stopScroll()
        // Kept from the recycler so the destination's layout can't reuse them
        val oldViews = ArrayList<View>(count)
        val oldTops = HashMap<View, Int>(count)
        for (index in 0 until count) {
            val child = recyclerView.getChildAt(index)
            oldViews.add(child)
            oldTops[child] = child.top
            recyclerView.getChildViewHolder(child)?.let { holder ->
                holder.setIsRecyclable(false)
                heldHolders.add(holder)
            }
        }
        jump()
        val listener = object : View.OnLayoutChangeListener {
            override fun onLayoutChange(
                view: View,
                left: Int,
                top: Int,
                right: Int,
                bottom: Int,
                oldLeft: Int,
                oldTop: Int,
                oldRight: Int,
                oldBottom: Int
            ) {
                recyclerView.removeOnLayoutChangeListener(this)
                pendingLayout = null
                animateFrom(oldViews, oldTops)
            }
        }
        pendingLayout = listener
        recyclerView.addOnLayoutChangeListener(listener)
    }

    /** Stops where the rows show and returns whether a scroll ran. */
    fun stop(): Boolean {
        if (!isRunning) return false
        val remaining = if (animator != null) (scrollLength * (1f - progress)).roundToInt() else 0
        endScroll()
        if (remaining != 0) recyclerView.scrollBy(0, -remaining)
        return true
    }

    fun finish() {
        if (isRunning) endScroll()
    }

    private fun animateFrom(oldViews: MutableList<View>, oldTops: Map<View, Int>) {
        var top = Int.MAX_VALUE
        var head: View? = null
        var scrollDiff = 0
        var hasSameViews = false
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            if (child.top < top) {
                top = child.top
                head = child
            }
            val oldTop = oldTops[child] ?: continue
            hasSameViews = true
            oldViews.remove(child)
            val diff = child.top - oldTop
            if (diff != 0) scrollDiff = diff
        }
        var oldBottom = 0
        for (view in oldViews) {
            if (view.parent != null) continue
            oldBottom = max(oldBottom, view.bottom)
            recyclerView.overlay.add(view)
            leavingViews.add(view)
        }
        scrollLength = if (leavingViews.isEmpty()) abs(scrollDiff) else oldBottom - top
        if (head == null || scrollLength <= 0) {
            endScroll()
            return
        }
        stripHead = head
        stripHeadTop = head.top
        progress = 0f
        frameBinding = AgentPreDrawBinding(recyclerView, frameUpdater)
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = calculateDuration(hasSameViews)
            interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
            addUpdateListener {
                progress = it.animatedValue as Float
                applyFrame()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (animator === animation) endScroll()
                }
            })
            start()
        }
    }

    // Telegram's durations: 600 ms on screen, else 200 ms per list height plus 200 ms, within 300 ms to 1.3 s
    private fun calculateDuration(hasSameViews: Boolean): Long {
        if (hasSameViews) return SHARED_ROWS_DURATION_MS
        val height = recyclerView.measuredHeight.takeIf { it > 0 } ?: return MIN_DURATION_MS
        val duration = ((scrollLength.toFloat() / height + 1f) * DURATION_PER_HEIGHT_MS).toLong()
        return duration.coerceIn(MIN_DURATION_MS, MAX_DURATION_MS)
    }

    private fun applyFrame() {
        if (animator == null) return
        val remaining = scrollLength * (1f - progress)
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            child.translationY = remaining
            movedViews.add(child)
        }
        val head = stripHead?.takeIf { it.parent === recyclerView }
        val drift = if (head == null) 0 else head.top - stripHeadTop
        val leavingShift = drift + remaining - scrollLength
        leavingViews.forEach { it.translationY = leavingShift }
        recyclerView.invalidate()
    }

    private fun endScroll() {
        pendingLayout?.let(recyclerView::removeOnLayoutChangeListener)
        pendingLayout = null
        animator?.let {
            animator = null
            it.removeAllListeners()
            it.cancel()
        }
        frameBinding?.release()
        frameBinding = null
        leavingViews.forEach {
            it.translationY = 0f
            recyclerView.overlay.remove(it)
        }
        leavingViews.clear()
        movedViews.forEach { it.translationY = 0f }
        movedViews.clear()
        heldHolders.forEach { it.setIsRecyclable(true) }
        heldHolders.clear()
        stripHead = null
        recyclerView.invalidate()
    }

    private companion object {
        const val SHARED_ROWS_DURATION_MS = 600L
        const val DURATION_PER_HEIGHT_MS = 200L
        const val MIN_DURATION_MS = 300L
        const val MAX_DURATION_MS = 1300L
    }
}
