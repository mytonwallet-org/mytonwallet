package org.mytonwallet.app_air.uicomponents.helpers.spans

import android.text.Spannable
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.TextView

class ExtraHitLinkMovementMethod(
    private val extraXPx: Int,
    private val extraYPx: Int
) : LinkMovementMethod() {

    private var downTime = 0L

    override fun onTouchEvent(
        widget: TextView,
        buffer: Spannable,
        event: MotionEvent
    ): Boolean {

        if (event.action == MotionEvent.ACTION_DOWN) {
            downTime = event.eventTime
        }

        if (event.action != MotionEvent.ACTION_DOWN &&
            event.action != MotionEvent.ACTION_UP
        ) {
            return super.onTouchEvent(widget, buffer, event)
        }

        val x = (event.x - widget.totalPaddingLeft + widget.scrollX).toInt()
        val y = (event.y - widget.totalPaddingTop + widget.scrollY).toInt()

        val layout = widget.layout ?: return false

        val line = layout.getLineForVertical(
            (y - extraYPx).coerceAtLeast(0)
        )

        val left = (x - extraXPx).coerceAtLeast(0)
        val right = x + extraXPx

        val offLeft = layout.getOffsetForHorizontal(line, left.toFloat())
        val offRight = layout.getOffsetForHorizontal(line, right.toFloat())

        val links = buffer.getSpans(
            offLeft.coerceAtMost(offRight),
            offRight.coerceAtLeast(offLeft),
            ClickableSpan::class.java
        )

        if (links.isNotEmpty()) {
            if (event.action == MotionEvent.ACTION_UP) {
                if (event.eventTime - downTime < ViewConfiguration.getLongPressTimeout()) {
                    links[0].onClick(widget)
                }
            }
            return true
        }

        return super.onTouchEvent(widget, buffer, event)
    }
}
