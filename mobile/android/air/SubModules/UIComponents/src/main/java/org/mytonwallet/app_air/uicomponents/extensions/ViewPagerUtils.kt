package org.mytonwallet.app_air.uicomponents.extensions

import android.annotation.SuppressLint
import android.view.MotionEvent
import androidx.dynamicanimation.animation.FloatPropertyCompat
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import java.util.WeakHashMap
import kotlin.math.abs
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

// Only one spring may drive a RecyclerView's scroll at a time; a second one started on the same
// view would fight the first per-frame instead of replacing it.
private val activeSprings = WeakHashMap<RecyclerView, SpringAnimation>()

private fun horizontalScrollProperty() = object : FloatPropertyCompat<RecyclerView>("scrollX") {
    private var animatedOffset = 0f

    override fun getValue(view: RecyclerView): Float {
        animatedOffset = view.computeHorizontalScrollOffset().toFloat()
        return animatedOffset
    }

    override fun setValue(view: RecyclerView, value: Float) {
        val maxScroll =
            (view.computeHorizontalScrollRange() - view.computeHorizontalScrollExtent())
                .coerceAtLeast(0)
        val boundedValue = value.coerceIn(0f, maxScroll.toFloat())
        val dx = (boundedValue - animatedOffset).toInt()
        if (dx != 0) {
            val previousOffset = view.computeHorizontalScrollOffset()
            view.scrollBy(dx, 0)
            animatedOffset += view.computeHorizontalScrollOffset() - previousOffset
        }
    }
}

@SuppressLint("ClickableViewAccessibility")
private fun startSpring(recyclerView: RecyclerView, springAnim: SpringAnimation) {
    activeSprings.remove(recyclerView)?.cancel()
    activeSprings[recyclerView] = springAnim
    springAnim.addEndListener { anim, _, _, _ ->
        if (activeSprings[recyclerView] === anim) activeSprings.remove(recyclerView)
    }
    springAnim.start()
    recyclerView.setOnTouchListener { _, event ->
        if (event.action == MotionEvent.ACTION_DOWN) activeSprings.remove(recyclerView)?.cancel()
        recyclerView.setOnTouchListener(null)
        return@setOnTouchListener false
    }
}

private fun springToVisibleItem(
    recyclerView: RecyclerView,
    layoutManager: LinearLayoutManager,
    targetPosition: Int,
    velocityX: Float,
    onCompletion: () -> Unit
): Boolean {
    if (layoutManager.findViewByPosition(targetPosition) == null) return false
    val isRtl = LocaleController.isRTL
    fun distanceToTarget(): Int {
        val view = layoutManager.findViewByPosition(targetPosition) ?: return 0
        return if (isRtl) {
            view.right - (recyclerView.width - recyclerView.paddingRight)
        } else {
            view.left - recyclerView.paddingLeft
        }
    }

    var animatedOffset = 0f
    val springAnim = SpringAnimation(FloatValueHolder(0f)).apply {
        spring = SpringForce(distanceToTarget().toFloat()).apply {
            dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            stiffness = 500f
        }
        setStartVelocity(velocityX)
        addUpdateListener { _, value, _ ->
            val dx = (value - animatedOffset).toInt()
            if (dx != 0) {
                recyclerView.scrollBy(dx, 0)
                animatedOffset += dx
            }
        }
        addEndListener { _, canceled, _, _ ->
            if (!canceled) {
                recyclerView.scrollBy(distanceToTarget(), 0)
                onCompletion()
            }
        }
    }
    startSpring(recyclerView, springAnim)
    return true
}

fun ViewPager2.setupSpringFling(onScrollingToTarget: (targetIndex: Int) -> Int) {
    val recyclerView = getChildAt(0) as? RecyclerView ?: return
    val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return

    recyclerView.onFlingListener = object : RecyclerView.OnFlingListener() {
        override fun onFling(velocityX: Int, velocityY: Int): Boolean {
            val itemCount = recyclerView.adapter?.itemCount ?: 0
            if (itemCount == 0) return false

            val currentPosition = if (itemCount == Int.MAX_VALUE) {
                val nearestView = (0 until recyclerView.childCount)
                    .map { recyclerView.getChildAt(it) }
                    .minByOrNull { view ->
                        abs(view.left + view.width / 2 - recyclerView.width / 2)
                    } ?: return false
                val position = recyclerView.getChildAdapterPosition(nearestView)
                if (position == RecyclerView.NO_POSITION) return false
                position
            } else {
                (0 until itemCount).minByOrNull { index ->
                    val view =
                        layoutManager.findViewByPosition(index) ?: return@minByOrNull Int.MAX_VALUE
                    val viewCenter = view.left + view.width / 2
                    val recyclerCenter = recyclerView.width / 2
                    abs(viewCenter - recyclerCenter)
                } ?: 0
            }

            val step = if (LocaleController.isRTL) -1 else 1
            val targetPosition = when {
                velocityX > 300 -> currentPosition + step
                velocityX < -300 -> currentPosition - step
                else -> currentPosition
            }.coerceIn(0, itemCount - 1)
            val finalTargetPosition = onScrollingToTarget(targetPosition)
            if (itemCount == Int.MAX_VALUE) {
                return springToVisibleItem(
                    recyclerView,
                    layoutManager,
                    finalTargetPosition,
                    velocityX.toFloat()
                ) {
                    recyclerView.stopScroll()
                }
            }
            val scrollPosition =
                if (LocaleController.isRTL) {
                    itemCount - 1 - finalTargetPosition
                } else {
                    finalTargetPosition
                }

            val springAnim = SpringAnimation(
                recyclerView,
                horizontalScrollProperty(),
                scrollPosition * width.toFloat()
            )

            springAnim.spring.dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            springAnim.spring.stiffness = 500f
            springAnim.setStartVelocity(velocityX.toFloat())
            springAnim.addEndListener { _, canceled, _, _ ->
                if (!canceled) {
                    recyclerView.scrollBy(
                        scrollPosition * width - recyclerView.computeHorizontalScrollOffset(),
                        0
                    )
                    // Consuming the fling left the RecyclerView in the dragging scroll state, which
                    // blocks ViewPager2 from dispatching page selection and the idle state.
                    // stopScroll() moves it to idle so those callbacks fire.
                    recyclerView.stopScroll()
                }
            }
            startSpring(recyclerView, springAnim)

            return true
        }
    }
}

fun ViewPager2.springToItem(
    targetPosition: Int,
    velocityX: Float = 0f,
    onCompletion: (() -> Unit)? = null
) {
    val recyclerView = getChildAt(0) as? RecyclerView ?: return
    val itemCount = recyclerView.adapter?.itemCount ?: return

    val clampedPosition = targetPosition.coerceIn(0, itemCount - 1)
    if (itemCount == Int.MAX_VALUE) {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return
        if (springToVisibleItem(recyclerView, layoutManager, clampedPosition, velocityX) {
                setCurrentItem(clampedPosition, false)
                onCompletion?.invoke()
            }
        ) {
            return
        }
        setCurrentItem(clampedPosition, false)
        onCompletion?.invoke()
        return
    }
    val scrollPosition =
        if (LocaleController.isRTL) itemCount - 1 - clampedPosition else clampedPosition
    val offset = scrollPosition * width.toFloat()

    val springAnim = SpringAnimation(recyclerView, horizontalScrollProperty(), offset)
    springAnim.spring.dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
    springAnim.spring.stiffness = 500f
    springAnim.setStartVelocity(velocityX)

    springAnim.addEndListener { _, canceled, _, _ ->
        if (!canceled) {
            this.setCurrentItem(clampedPosition, false)
            onCompletion?.invoke()
        }
    }

    startSpring(recyclerView, springAnim)
}
