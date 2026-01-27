package org.mytonwallet.app_air.uicomponents.widgets

import android.view.View
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintSet
import androidx.constraintlayout.widget.Guideline
import androidx.transition.ChangeBounds
import androidx.transition.TransitionManager
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import kotlin.math.roundToInt

class WConstraintSet(private val constraintView: ConstraintLayout) : ConstraintSet() {

    // Create a new constraint set cloned for constraintView
    init {
        clone(constraintView)
    }

    // MUST be called after all the modifications are done
    fun layout() {
        applyTo(constraintView)
    }

    // MUST be called after all the modifications are done
    fun layoutAnimated(duration: Long = AnimationConstants.QUICK_ANIMATION) {
        val transition = ChangeBounds()
        transition.setDuration(AnimationConstants.QUICK_ANIMATION);
        TransitionManager.beginDelayedTransition(constraintView, transition)
        applyTo(constraintView)
    }

    fun toCenterX(v: View, margin: Float = 0F) {
        toStart(v, margin)
        toEnd(v, margin)
    }

    fun toCenterXPx(v: View, margin: Int = 0) {
        toStartPx(v, margin)
        toEndPx(v, margin)
    }

    fun toCenterY(v: View, margin: Float = 0F) {
        toTop(v, margin)
        toBottom(v, margin)
    }

    fun centerYToCenterY(v1: View, v2: View, margin: Float = 0F) {
        topToTop(v1, v2, margin)
        bottomToBottom(v1, v2, margin)
    }

    fun centerXToCenterX(v1: View, v2: View, margin: Float = 0F) {
        startToStart(v1, v2, margin)
        endToEnd(v1, v2, margin)
    }

    fun centerToCenter(v1: View, v2: View, margin: Float = 0F) {
        topToTop(v1, v2, margin)
        bottomToBottom(v1, v2, margin)
        leftToLeft(v1, v2, margin)
        rightToRight(v1, v2, margin)
    }

    fun topToBottom(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id, TOP, v2.id, BOTTOM,
            margin.dp.roundToInt()
        )
    }

    fun topToBottomPx(v1: View, v2: View, margin: Int) {
        connect(
            v1.id, TOP, v2.id, BOTTOM,
            margin
        )
    }

    fun bottomToTop(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id, BOTTOM, v2.id, TOP,
            margin.dp.roundToInt()
        )
    }

    fun bottomToTopPx(v1: View, v2: View, margin: Int = 0) {
        connect(
            v1.id, BOTTOM, v2.id, TOP,
            margin
        )
    }

    fun startToEnd(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id, START, v2.id, END,
            margin.dp.roundToInt()
        )
    }

    fun startToEndPx(v1: View, v2: View, margin: Int = 0) {
        connect(
            v1.id, START, v2.id, END,
            margin
        )
    }

    fun endToStart(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id, END, v2.id, START,
            margin.dp.roundToInt()
        )
    }

    fun endToStartPx(v1: View, v2: View, margin: Int) {
        connect(
            v1.id, END, v2.id, START,
            margin
        )
    }

    fun allEdges(v: View, margin: Float = 0F) {
        edgeToEdge(v, constraintView, margin)
    }

    fun allEdgesPx(v: View, margin: Int = 0) {
        edgeToEdgePx(v, constraintView, margin)
    }

    fun edgeToEdge(v1: View, v2: View, margin: Float = 0F) {
        topToTop(v1, v2, margin)
        startToStart(v1, v2, margin)
        endToEnd(v1, v2, margin)
        bottomToBottom(v1, v2, margin)
    }

    private fun edgeToEdgePx(v1: View, v2: View, margin: Int = 0) {
        topToTopPx(v1, v2, margin)
        startToStartPx(v1, v2, margin)
        endToEndPx(v1, v2, margin)
        bottomToBottomPx(v1, v2, margin)
    }

    fun toTopPx(v: View, margin: Int) {
        topToTopPx(v, constraintView, margin)
    }

    fun toTop(v: View, margin: Float = 0F) {
        topToTop(v, constraintView, margin)
    }

    fun topToTop(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id,
            TOP,
            v2.id,
            TOP,
            margin.dp.roundToInt()
        )
    }

    fun topToTopPx(v1: View, v2: View, margin: Int) {
        connect(
            v1.id,
            TOP,
            v2.id,
            TOP,
            margin
        )
    }

    fun toStart(v: View, margin: Float = 0F) {
        startToStart(v, constraintView, margin)
    }

    fun toStartPx(v: View, margin: Int = 0) {
        startToStartPx(v, constraintView, margin)
    }

    fun startToStart(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id,
            START,
            v2.id,
            START,
            margin.dp.roundToInt()
        )
    }

    private fun startToStartPx(v1: View, v2: View, margin: Int = 0) {
        connect(
            v1.id,
            START,
            v2.id,
            START,
            margin
        )
    }

    fun toEnd(v: View, margin: Float = 0F) {
        endToEnd(v, constraintView, margin)
    }

    fun toEndPx(v: View, margin: Int = 0) {
        endToEndPx(v, constraintView, margin)
    }

    fun endToEnd(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id,
            END,
            v2.id,
            END,
            margin.dp.roundToInt()
        )
    }

    private fun endToEndPx(v1: View, v2: View, margin: Int = 0) {
        connect(
            v1.id,
            END,
            v2.id,
            END,
            margin
        )
    }

    fun toLeft(v: View, margin: Float = 0F) {
        leftToLeft(v, constraintView, margin)
    }

    fun leftToLeft(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id,
            LEFT,
            v2.id,
            LEFT,
            margin.dp.roundToInt()
        )
    }

    fun toRight(v: View, margin: Float = 0F) {
        rightToRight(v, constraintView, margin)
    }

    fun rightToRight(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id,
            RIGHT,
            v2.id,
            RIGHT,
            margin.dp.roundToInt()
        )
    }

    fun leftToRight(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id,
            LEFT,
            v2.id,
            RIGHT,
            margin.dp.roundToInt()
        )
    }

    fun rightToLeft(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id,
            RIGHT,
            v2.id,
            LEFT,
            margin.dp.roundToInt()
        )
    }

    fun toBottomPx(v: View, margin: Int) {
        bottomToBottomPx(v, constraintView, margin)
    }

    fun toBottom(v: View, margin: Float = 0F) {
        bottomToBottom(v, constraintView, margin)
    }

    fun bottomToBottom(v1: View, v2: View, margin: Float = 0F) {
        connect(
            v1.id,
            BOTTOM,
            v2.id,
            BOTTOM,
            margin.dp.roundToInt()
        )
    }

    fun bottomToBottomPx(v1: View, v2: View, margin: Int) {
        connect(
            v1.id,
            BOTTOM,
            v2.id,
            BOTTOM,
            margin
        )
    }

    fun baseLineToBasLine(v1: View, v2: View) {
        connect(
            v1.id,
            BASELINE,
            v2.id,
            BASELINE
        )
    }

    fun guidelineBegin(guideline: Guideline, margin: Float = 0F) {
        guidelineBeginPx(guideline, margin.dp.roundToInt())
    }

    fun guidelineBeginPx(guideline: Guideline, margin: Int) {
        setGuidelineBegin(guideline.id, margin)
    }

    fun guidelineEnd(guideline: Guideline, margin: Float = 0F) {
        guidelineEndPx(guideline, margin.dp.roundToInt())
    }

    fun guidelineEndPx(guideline: Guideline, margin: Int) {
        setGuidelineEnd(guideline.id, margin)
    }

    fun guidelinePercent(guideline: Guideline, ratio: Float = 0F) {
        setGuidelinePercent(guideline.id, ratio)
    }
}
