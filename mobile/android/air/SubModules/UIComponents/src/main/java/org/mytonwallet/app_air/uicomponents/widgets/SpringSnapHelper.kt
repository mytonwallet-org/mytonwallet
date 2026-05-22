package org.mytonwallet.app_air.uicomponents.widgets

import android.view.MotionEvent
import androidx.dynamicanimation.animation.FloatPropertyCompat
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSnapHelper
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.abs

/**
 * Spring-animated snap helper for horizontal RecyclerViews. Wraps LinearSnapHelper,
 * intercepting onFling to spring-scroll to a neighboring position, and exposes
 * hooks for the host to react to user interaction.
 *
 * Attach with [attachTo] AFTER the host configures the RecyclerView's layoutManager.
 */
class SpringSnapHelper(
    private val velocityThreshold: Int = 300,
    private val stiffness: Float = 500f,
    private val dampingRatio: Float = SpringForce.DAMPING_RATIO_NO_BOUNCY,
) {

    private var recyclerView: RecyclerView? = null
    private var linearLayoutManager: LinearLayoutManager? = null

    private var springAnim: SpringAnimation? = null
    private var animatedScrollOffset = 0f

    /** Invoked when the user starts dragging or touches down. */
    var onUserDrag: (() -> Unit)? = null

    /** Invoked when scroll settles on a position (after spring or natural idle). */
    var onPositionSettled: ((Int) -> Unit)? = null

    private val scrollProperty = object : FloatPropertyCompat<RecyclerView>("scrollX") {
        override fun getValue(view: RecyclerView): Float {
            animatedScrollOffset = view.computeHorizontalScrollOffset().toFloat()
            return animatedScrollOffset
        }

        override fun setValue(view: RecyclerView, value: Float) {
            val dx = (value - animatedScrollOffset).toInt()
            if (dx != 0) {
                view.scrollBy(dx, 0)
                animatedScrollOffset += dx
            }
        }
    }

    private val snapHelper = object : LinearSnapHelper() {
        override fun onFling(velocityX: Int, velocityY: Int): Boolean {
            val rv = recyclerView ?: return false
            val lm = linearLayoutManager ?: return false
            val itemCount = rv.adapter?.itemCount ?: 0
            if (itemCount == 0) return false
            val currentPos = closestPosition(lm, itemCount)
            val targetPos = when {
                velocityX > velocityThreshold -> currentPos + 1
                velocityX < -velocityThreshold -> currentPos - 1
                else -> currentPos
            }.coerceIn(0, itemCount - 1)
            springScrollTo(targetPos, velocityX.toFloat())
            return true
        }
    }

    private val touchListener = object : RecyclerView.OnItemTouchListener {
        override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
            if (e.actionMasked == MotionEvent.ACTION_DOWN) {
                cancel()
                onUserDrag?.invoke()
            }
            return false
        }

        override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) = Unit
        override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) = Unit
    }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrollStateChanged(rv: RecyclerView, newState: Int) {
            when (newState) {
                RecyclerView.SCROLL_STATE_DRAGGING -> {
                    cancel()
                    onUserDrag?.invoke()
                }

                RecyclerView.SCROLL_STATE_IDLE -> {
                    val lm = linearLayoutManager ?: return
                    val itemCount = rv.adapter?.itemCount ?: 0
                    if (itemCount > 0) onPositionSettled?.invoke(closestPosition(lm, itemCount))
                }
            }
        }
    }

    fun attachTo(recyclerView: RecyclerView) {
        val lm = recyclerView.layoutManager as? LinearLayoutManager
            ?: error("SpringSnapHelper requires a LinearLayoutManager")
        this.recyclerView = recyclerView
        this.linearLayoutManager = lm
        snapHelper.attachToRecyclerView(recyclerView)
        recyclerView.addOnItemTouchListener(touchListener)
        recyclerView.addOnScrollListener(scrollListener)
    }

    fun detach() {
        cancel()
        snapHelper.attachToRecyclerView(null)
        recyclerView?.removeOnItemTouchListener(touchListener)
        recyclerView?.removeOnScrollListener(scrollListener)
        recyclerView = null
        linearLayoutManager = null
    }

    fun cancel() {
        springAnim?.cancel()
        springAnim = null
    }

    fun scrollTo(position: Int, velocityX: Float = 0f) {
        val rv = recyclerView ?: return
        val lm = linearLayoutManager ?: return
        val itemCount = rv.adapter?.itemCount ?: 0
        if (itemCount == 0) return
        springScrollTo(position.coerceIn(0, itemCount - 1), velocityX)
    }

    private fun closestPosition(lm: LinearLayoutManager, itemCount: Int): Int =
        (0 until itemCount).minByOrNull { index ->
            lm.findViewByPosition(index)?.let { abs(it.left) } ?: Int.MAX_VALUE
        } ?: 0

    private fun targetScrollOffset(position: Int): Float {
        val rv = recyclerView ?: return 0f
        val lm = linearLayoutManager ?: return 0f
        return lm.findViewByPosition(position)?.let { view ->
            val distance = snapHelper.calculateDistanceToFinalSnap(lm, view)?.get(0) ?: 0
            rv.computeHorizontalScrollOffset().toFloat() + distance
        } ?: 0f
    }

    private fun springScrollTo(position: Int, velocityX: Float) {
        val rv = recyclerView ?: return
        val lm = linearLayoutManager ?: return
        springAnim?.cancel()
        animatedScrollOffset = rv.computeHorizontalScrollOffset().toFloat()
        val target = targetScrollOffset(position)
        springAnim = SpringAnimation(rv, scrollProperty, target).apply {
            spring.dampingRatio = dampingRatio
            spring.stiffness = stiffness
            if (velocityX != 0f) setStartVelocity(velocityX)
            addEndListener { _, canceled, _, _ ->
                if (canceled) return@addEndListener
                animatedScrollOffset = rv.computeHorizontalScrollOffset().toFloat()
                lm.findViewByPosition(position)?.let { view ->
                    val adj = snapHelper.calculateDistanceToFinalSnap(lm, view)?.get(0) ?: 0
                    if (adj != 0) {
                        rv.scrollBy(adj, 0)
                        animatedScrollOffset = rv.computeHorizontalScrollOffset().toFloat()
                    }
                }
                onPositionSettled?.invoke(position)
            }
            start()
        }
    }
}
