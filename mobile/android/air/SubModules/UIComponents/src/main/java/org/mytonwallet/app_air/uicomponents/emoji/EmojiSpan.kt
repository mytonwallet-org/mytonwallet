package org.mytonwallet.app_air.uicomponents.emoji

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.Spannable
import android.text.style.ReplacementSpan
import android.view.View
import android.widget.EditText
import android.widget.TextView
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

class EmojiSpan(
    private val unified: String,
    private val viewRef: WeakReference<View?>
) : ReplacementSpan() {

    private val rect = RectF()
    private var loading = false
    private var failed = false

    override fun getSize(
        paint: Paint,
        text: CharSequence,
        start: Int,
        end: Int,
        fm: Paint.FontMetricsInt?
    ): Int {
        if (fm != null) {
            val metrics = paint.fontMetricsInt
            fm.ascent = metrics.ascent
            fm.descent = metrics.descent
            fm.top = metrics.top
            fm.bottom = metrics.bottom
        }
        if (failed) {
            return paint.measureText(text, start, end).roundToInt()
        }
        return emojiSize(paint)
    }

    override fun draw(
        canvas: Canvas,
        text: CharSequence,
        start: Int,
        end: Int,
        x: Float,
        top: Int,
        y: Int,
        bottom: Int,
        paint: Paint
    ) {
        val bitmap = EmojiProvider.get(unified)
        if (bitmap != null) {
            failed = false
            val size = emojiSize(paint)
            val centerY = (top + bottom) / 2f
            rect.set(x, centerY - size / 2f, x + size, centerY + size / 2f)
            canvas.drawBitmap(bitmap, null, rect, null)
        } else if (failed) {
            canvas.drawText(text, start, end, x, y.toFloat(), paint)
            loading = false
        } else if (!loading) {
            loading = true
            EmojiProvider.loadAsync(unified) { bmp ->
                if (bmp == null) {
                    failed = true
                }
                val view = viewRef.get() ?: return@loadAsync
                view.post {
                    when (view) {
                        is EditText -> {
                            val spannable = view.editableText
                            val s = spannable.getSpanStart(this@EmojiSpan)
                            val e = spannable.getSpanEnd(this@EmojiSpan)
                            if (s >= 0 && e >= 0) {
                                spannable.removeSpan(this@EmojiSpan)
                                spannable.setSpan(
                                    this@EmojiSpan, s, e,
                                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                                )
                            }
                        }

                        is TextView -> view.text = view.text
                        else -> view.invalidate()
                    }
                }
            }
        }
    }

    private fun emojiSize(paint: Paint): Int {
        return (paint.textSize * 1.2f).roundToInt()
    }
}
