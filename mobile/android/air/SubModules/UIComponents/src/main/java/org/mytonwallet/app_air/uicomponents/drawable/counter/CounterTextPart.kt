package org.mytonwallet.app_air.uicomponents.drawable.counter

import android.graphics.Canvas
import me.vkryl.android.animator.CounterAnimator.TextDrawable


interface CounterTextPart : TextDrawable {
    fun draw(
        c: Canvas,
        startX: Int,
        endX: Int,
        endXBottomPadding: Int,
        startY: Int,
        alpha: Float
    )
}
