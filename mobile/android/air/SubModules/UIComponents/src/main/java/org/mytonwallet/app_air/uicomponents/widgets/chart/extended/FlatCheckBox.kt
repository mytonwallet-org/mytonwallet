package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.text.TextPaint
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.shakeView

class FlatCheckBox(context: Context) : View(context) {
    private var attached = false

    private var checkedState = false
    var style: ChartStyle = ChartStyle.default()
        set(value) {
            field = value
            invalidate()
        }

    private var text: String? = null
    private val textPaint = TextPaint(TextPaint.ANTI_ALIAS_FLAG)
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val outLinePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val checkPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private var colorActive = 0
    private var colorInactive = 0
    private var colorTextActive = 0

    private val height = 28.dp
    private val innerPadding = 22.dp
    private val translateText = 8.dp

    private val rectF = RectF()
    private var progress = 0f
    private var checkAnimator: ValueAnimator? = null
    private var lastW = 0

    init {
        textPaint.textSize = 14.dp.toFloat()
        textPaint.textAlign = Paint.Align.CENTER
        textPaint.typeface = WFont.Medium.typeface

        outLinePaint.strokeWidth = 1.5f.dp
        outLinePaint.style = Paint.Style.STROKE

        checkPaint.style = Paint.Style.STROKE
        checkPaint.strokeCap = Paint.Cap.ROUND
        checkPaint.strokeWidth = 2.dp.toFloat()
    }

    fun recolor(c: Int) {
        colorActive = style.backgroundColor
        colorTextActive = style.checkBoxTextColor
        colorInactive = c
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        attached = true
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        attached = false
    }

    fun setChecked(enabled: Boolean) {
        setChecked(enabled, true)
    }

    fun setChecked(enabled: Boolean, animate: Boolean) {
        checkedState = enabled
        if (!attached || !animate) {
            progress = if (enabled) 1f else 0f
            invalidate()
            return
        }
        checkAnimator?.removeAllListeners()
        checkAnimator?.cancel()
        checkAnimator = ValueAnimator.ofFloat(progress, if (enabled) 1f else 0f).apply {
            addUpdateListener { animation ->
                progress = animation.animatedValue as Float
                invalidate()
            }
            duration = 300
            start()
        }
    }

    fun setText(text: String?) {
        this.text = text
        requestLayout()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        var textW = if (text == null) 0 else textPaint.measureText(text).toInt()
        textW += innerPadding shl 1
        setMeasuredDimension(textW, height)
        if (measuredWidth != lastW) {
            lastW = measuredWidth
            rectF.set(0f, 0f, measuredWidth.toFloat(), measuredHeight.toFloat())
            val inset = outLinePaint.strokeWidth / 2f
            rectF.inset(inset, inset)
        }
    }

    override fun draw(canvas: Canvas) {
        super.draw(canvas)

        val textTranslation: Float
        if (progress <= 0.5f) {
            val checkProgress = progress / 0.5f
            textTranslation = checkProgress

            var rD = ((Color.red(colorInactive) - Color.red(colorActive)) * checkProgress).toInt()
            var gD =
                ((Color.green(colorInactive) - Color.green(colorActive)) * checkProgress).toInt()
            var bD = ((Color.blue(colorInactive) - Color.blue(colorActive)) * checkProgress).toInt()
            var c = Color.rgb(
                Color.red(colorActive) + rD,
                Color.green(colorActive) + gD,
                Color.blue(colorActive) + bD
            )
            fillPaint.color = c

            rD = ((Color.red(colorTextActive) - Color.red(colorInactive)) * checkProgress).toInt()
            gD =
                ((Color.green(colorTextActive) - Color.green(colorInactive)) * checkProgress).toInt()
            bD = ((Color.blue(colorTextActive) - Color.blue(colorInactive)) * checkProgress).toInt()
            c = Color.rgb(
                Color.red(colorInactive) + rD,
                Color.green(colorInactive) + gD,
                Color.blue(colorInactive) + bD
            )
            textPaint.color = c
        } else {
            textTranslation = 1f
            textPaint.color = colorTextActive
            fillPaint.color = colorInactive
        }

        val heightHalf = measuredHeight shr 1
        outLinePaint.color = colorInactive
        canvas.drawRoundRect(rectF, height / 2f, height / 2f, fillPaint)
        canvas.drawRoundRect(rectF, height / 2f, height / 2f, outLinePaint)

        text?.let {
            canvas.drawText(
                it,
                (measuredWidth shr 1) + textTranslation * translateText,
                heightHalf + textPaint.textSize * 0.35f,
                textPaint
            )
        }

        val bounceProgress = 2.0f - progress / 0.5f
        canvas.save()
        canvas.scale(0.9f, 0.9f, 7f.dp, heightHalf.toFloat())
        canvas.translate(12.dp.toFloat(), heightHalf - 9.dp.toFloat())

        if (progress > 0.5f) {
            checkPaint.color = colorTextActive
            var endX = (7f.dp - 4.dp * (1.0f - bounceProgress)).toInt()
            var endY = (13f.dp - 4.dp * (1.0f - bounceProgress)).toInt()
            canvas.drawLine(7f.dp, 13f.dp, endX.toFloat(), endY.toFloat(), checkPaint)
            endX = (7f.dp + 8.dp * (1.0f - bounceProgress)).toInt()
            endY = (13f.dp - 8.dp * (1.0f - bounceProgress)).toInt()
            canvas.drawLine(7f.dp, 13f.dp, endX.toFloat(), endY.toFloat(), checkPaint)
        }
        canvas.restore()
    }

    fun denied() {
        shakeView()
    }
}
