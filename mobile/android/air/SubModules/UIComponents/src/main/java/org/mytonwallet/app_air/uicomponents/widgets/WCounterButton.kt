package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.TextPaint
import android.view.View
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.drawable.counter.Counter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.sp
import org.mytonwallet.app_air.uicomponents.helpers.CancelableRunnable
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WCounterButton(
    context: Context,
    val drawable: Drawable,
    private val isTrailingButton: Boolean
) : View(context), Counter.Callback,
    WThemedView {
    private val textPaintSecondary = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = WFont.Regular.typeface
        textSize = 14f.sp
    }
    private val counter = Counter(textPaintSecondary, this)
    private val ripple = WRippleDrawable.create(8f.dp)
    var shouldShowDrawable: Boolean = true
        set(value) {
            field = value
            requestLayout()
        }

    init {
        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, HEIGHT.dp)
        setPaddingDp(PADDING_HORIZONTAL, 0, PADDING_HORIZONTAL, 0)
        background = ripple
        updateTheme()
    }

    override fun dispatchDraw(canvas: Canvas) {
        if (isTrailingButton && !LocaleController.isRTL) {
            val leftPadding =
                PADDING_HORIZONTAL.dp + (counter.targetWidth - counter.getVisibleWidth()).toInt()
            setPadding(leftPadding, paddingTop, paddingRight, paddingBottom)
        }
        super.dispatchDraw(canvas)

        if (LocaleController.isRTL) {
            // Draw text normally without animation for RTL
            text?.let {
                val textWidth = textPaintSecondary.measureText(it)
                canvas.drawText(
                    it,
                    paddingLeft.toFloat(),
                    measuredHeight / 2f + 5.dp,
                    textPaintSecondary
                )

                if (shouldShowDrawable) {
                    drawable.let { drawable ->
                        canvas.save()
                        canvas.translate(
                            paddingLeft + textWidth,
                            measuredHeight / 2f - 8f.dp
                        )
                        drawable.alpha = 255
                        drawable.draw(canvas)
                        canvas.restore()
                    }
                }
            }
        } else {
            // Use counter animation for non-RTL
            counter.draw(canvas, paddingLeft.toFloat(), measuredHeight / 2f + 5.dp, 1f)
            if (text != null && shouldShowDrawable) {
                drawable.let {
                    canvas.save()
                    canvas.translate(
                        paddingLeft + counter.getVisibleWidth(),
                        measuredHeight / 2f - 8f.dp
                    )
                    it.alpha =
                        (255 * if (isTrailingButton) 1f - ((counter.targetWidth - counter.getVisibleWidth()) / 10).coerceIn(
                            0f,
                            1f
                        ) else 1f).roundToInt()
                    it.draw(canvas)
                    canvas.restore()
                }
            }
        }
    }

    private var text: String? = null

    private var lastUpdate = 0L
    private var updateRunnable: CancelableRunnable? = null

    fun setText(text: String?) {
        if (this.text == text) {
            return
        }

        updateRunnable?.cancel()
        updateRunnable = null

        this.text = text
        isEnabled = !text.isNullOrEmpty()

        if (LocaleController.isRTL) {
            // For RTL, just invalidate to redraw without animation
            invalidate()
            requestLayout()
        } else {
            // For non-RTL, use counter animation
            val time = SystemClock.uptimeMillis()
            val delay = maxOf(0, 300 - (time - lastUpdate))

            if (delay == 0L) {
                counter.setValue(text, isAttachedToWindow)
                lastUpdate = time
            } else {
                val runnable = CancelableRunnable {
                    counter.setValue(this.text, isAttachedToWindow)
                    lastUpdate = time
                }
                updateRunnable = runnable
                Handler(Looper.getMainLooper()).postDelayed(runnable, delay)
            }
        }
    }

    override fun updateTheme() {
        textPaintSecondary.color = WColor.SecondaryText.color
        ripple.rippleColor = WColor.BackgroundRipple.color
        drawable.setTint(WColor.SecondaryText.color)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = if (LocaleController.isRTL) {
            // For RTL, calculate width based on actual text width
            val textWidth = text?.let { textPaintSecondary.measureText(it).toInt() } ?: 0
            textWidth + paddingLeft + paddingRight + (if (shouldShowDrawable) ICON.dp else 0)
        } else {
            // For non-RTL, use counter's required width
            counter.requiredWidth + paddingLeft + paddingRight + (if (shouldShowDrawable) ICON.dp else 0)
        }

        super.onMeasure(width.exactly, heightMeasureSpec)
        if (shouldShowDrawable)
            drawable.setBounds(0, 0, 16.dp, 16.dp)
    }

    override fun onCounterAppearanceChanged(counter: Counter, sizeChanged: Boolean) {
        invalidate()
    }

    override fun onCounterRequiredWidthChanged(counter: Counter) {
        requestLayout()
    }

    companion object {
        const val PADDING_HORIZONTAL = 6
        const val HEIGHT = 20
        private const val ICON = 16
    }
}
