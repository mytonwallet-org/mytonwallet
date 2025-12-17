package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.HorizontalScrollView

@SuppressLint("ViewConstructor")
class AutoScaleContainerView(
    private val contentView: View
) : HorizontalScrollView(contentView.context) {

    var maxAllowedWidth = 0
    var minPadding = 0
    var additionalRightPadding = 0

    init {
        isHorizontalScrollBarEnabled = false

        contentView.layoutParams =
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        removeAllViews()
        addView(contentView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })
        contentView.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            val oldWidth = oldRight - oldLeft
            val newWidth = right - left
            if (newWidth != oldWidth) {
                updateScale()
            }
        }
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        return false
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(ev: MotionEvent): Boolean {
        return ev.action == MotionEvent.ACTION_MOVE
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateScale()
    }

    fun updateScale() {
        val child = contentView
        val contentWidth = child.width + additionalRightPadding
        val visibleWidth = maxAllowedWidth - minPadding * 2
        if (visibleWidth <= 0)
            return

        if (contentWidth > visibleWidth) {
            contentView.pivotX = contentView.width / 2f + additionalRightPadding / 2
            contentView.pivotY = contentView.height / 2f
            contentView.scaleX = visibleWidth / contentWidth.toFloat()
            contentView.scaleY = contentView.scaleX
        } else {
            contentView.translationX = 0f
            contentView.scaleX = 1f
            contentView.scaleY = 1f
        }
    }
}
