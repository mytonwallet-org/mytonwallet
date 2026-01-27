package org.mytonwallet.app_air.uicomponents.extensions

import android.annotation.SuppressLint
import android.view.MotionEvent
import androidx.dynamicanimation.animation.FloatPropertyCompat
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import kotlin.math.abs

fun ViewPager2.setupSpringFling(onScrollingToTarget: (targetIndex: Int) -> Int) {
    val recyclerView = getChildAt(0) as RecyclerView
    val layoutManager = recyclerView.layoutManager as LinearLayoutManager

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

            val targetPosition = when {
                velocityX > 300 -> currentPosition + 1
                velocityX < -300 -> currentPosition - 1
                else -> currentPosition
            }.coerceIn(0, itemCount - 1)
            val finalTargetPosition = onScrollingToTarget(targetPosition)

            val springAnim = SpringAnimation(
                recyclerView,
                object : FloatPropertyCompat<RecyclerView>("scrollX") {
                    override fun getValue(view: RecyclerView): Float {
                        return view.computeHorizontalScrollOffset().toFloat()
                    }

                    override fun setValue(view: RecyclerView, value: Float) {
                        view.scrollBy((value - view.computeHorizontalScrollOffset()).toInt(), 0)
                    }
                },
                finalTargetPosition * width.toFloat()
            )

            springAnim.spring.dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            springAnim.spring.stiffness = 500f
            springAnim.setStartVelocity(velocityX.toFloat())
            springAnim.addEndListener { _, canceled, _, _ ->
                if (!canceled)
                    recyclerView.scrollToPosition(finalTargetPosition)
            }
            springAnim.start()
            @SuppressLint("ClickableViewAccessibility")
            recyclerView.setOnTouchListener { _, event ->
                if (event.action == MotionEvent.ACTION_DOWN)
                    springAnim.cancel()
                recyclerView.setOnTouchListener(null)
                return@setOnTouchListener false
            }

            return true
        }
    }
}

fun ViewPager2.springToItem(targetPosition: Int, velocityX: Float = 0f) {
    val recyclerView = getChildAt(0) as RecyclerView
    val itemCount = recyclerView.adapter?.itemCount ?: return

    val clampedPosition = targetPosition.coerceIn(0, itemCount - 1)
    val offset = clampedPosition * width.toFloat()

    val scrollProperty = object : FloatPropertyCompat<RecyclerView>("scrollX") {
        override fun getValue(view: RecyclerView): Float {
            return view.computeHorizontalScrollOffset().toFloat()
        }

        override fun setValue(view: RecyclerView, value: Float) {
            view.scrollBy((value - view.computeHorizontalScrollOffset()).toInt(), 0)
        }
    }

    val springAnim = SpringAnimation(recyclerView, scrollProperty, offset)
    springAnim.spring.dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
    springAnim.spring.stiffness = 500f
    springAnim.setStartVelocity(velocityX)

    springAnim.addEndListener { _, _, _, _ ->
        this.setCurrentItem(clampedPosition, false)
    }

    springAnim.start()
}
