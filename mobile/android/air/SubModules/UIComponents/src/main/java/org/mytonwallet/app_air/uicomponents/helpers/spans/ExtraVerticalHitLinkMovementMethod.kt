@file:Suppress("ktlint:standard:filename")

package org.mytonwallet.app_air.uicomponents.helpers.spans

import android.text.Layout
import android.text.Selection
import android.text.Spannable
import android.text.Spanned
import android.text.method.LinkMovementMethod
import android.text.method.Touch
import android.text.style.ClickableSpan
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.TextView

class ExtraHitLinkMovementMethod(private val extraXPx: Int, private val extraYPx: Int) :
    LinkMovementMethod() {

    private var downTime = 0L

    override fun onTouchEvent(widget: TextView, buffer: Spannable, event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN) {
            downTime = event.eventTime
        }

        if (event.action != MotionEvent.ACTION_DOWN &&
            event.action != MotionEvent.ACTION_UP
        ) {
            return super.onTouchEvent(widget, buffer, event)
        }

        if (widget.layout == null) return false
        val links = findLinks(widget, buffer, event.x, event.y)

        if (links.isNotEmpty()) {
            if (event.action == MotionEvent.ACTION_UP) {
                if (event.eventTime - downTime < ViewConfiguration.getLongPressTimeout()) {
                    links[0].onClick(widget)
                }
            }
            return true
        }

        // Older Android versions' `LinkMovementMethod` opens a link past a line's end, so only its scrolling runs
        Selection.removeSelection(buffer)
        return Touch.onTouchEvent(widget, buffer, event)
    }

    /** The links that a touch at [x], [y] in [widget]'s own coordinates opens, within the drawn line and its extra hit area */
    fun findLinks(widget: TextView, buffer: Spanned, x: Float, y: Float): Array<ClickableSpan> {
        val layout = widget.layout ?: return emptyArray()
        val textX = (x - widget.totalPaddingLeft + widget.scrollX).toInt()
        val textY = (y - widget.totalPaddingTop + widget.scrollY).toInt()

        // A finger just under a line's top may mean the line above it
        val upperLine = layout.getLineForVertical((textY - extraYPx).coerceAtLeast(0))
        val touchedLine = layout.getLineForVertical(textY.coerceAtLeast(0))
        val links = findLinks(layout, buffer, upperLine, textX, textY)
        if (links.isNotEmpty() || touchedLine == upperLine) return links
        return findLinks(layout, buffer, touchedLine, textX, textY)
    }

    private fun findLinks(
        layout: Layout,
        buffer: Spanned,
        line: Int,
        textX: Int,
        textY: Int
    ): Array<ClickableSpan> {
        // `getOffsetForHorizontal` takes a point past the line's ends to its last character
        if (textX < layout.getLineLeft(line) - extraXPx ||
            textX > layout.getLineRight(line) + extraXPx ||
            textY < layout.getLineTop(line) - extraYPx ||
            textY > layout.getLineBottom(line) + extraYPx
        ) {
            return emptyArray()
        }

        val left = (textX - extraXPx).coerceAtLeast(0)
        val right = textX + extraXPx

        val offLeft = layout.getOffsetForHorizontal(line, left.toFloat())
        val offRight = layout.getOffsetForHorizontal(line, right.toFloat())

        return buffer.getSpans(
            offLeft.coerceAtMost(offRight),
            offRight.coerceAtLeast(offLeft),
            ClickableSpan::class.java
        )
    }
}
