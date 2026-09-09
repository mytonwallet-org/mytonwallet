package org.mytonwallet.app_air.uicomponents.extensions

import android.annotation.SuppressLint
import android.view.MotionEvent
import androidx.dynamicanimation.animation.FloatPropertyCompat
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
    override fun getValue(view: RecyclerView): Float =
        view.computeHorizontalScrollOffset().toFloat()

    override fun setValue(view: RecyclerView, value: Float) {
        view.scrollBy((value - view.computeHorizontalScrollOffset()).toInt(), 0)
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

fun ViewPager2.setupSpringFling(onScrollingToTarget: (targetIndex: Int) -> Int) {
    val recyclerView = getChildAt(0) as? RecyclerView ?: return
    val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return

    recyclerView.onFlingListener = object : RecyclerView.OnFlingListener() {
        override fun onFling(velocityX: Int, velocityY: Int): Boolean {
            val itemCount = recyclerView.adapter?.itemCount ?: 0

            val currentPosition = (0 until itemCount).minByOrNull { index ->
                val view =
                    layoutManager.findViewByPosition(index) ?: return@minByOrNull Int.MAX_VALUE
                val viewCenter = view.left + view.width / 2
                val recyclerCenter = recyclerView.width / 2
                abs(viewCenter - recyclerCenter)
            } ?: 0

            val step = if (LocaleController.isRTL) -1 else 1
            val targetPosition = when {
                velocityX > 300 -> currentPosition + step
                velocityX < -300 -> currentPosition - step
                else -> currentPosition
            }.coerceIn(0, itemCount - 1)
            val finalTargetPosition = onScrollingToTarget(targetPosition)
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
