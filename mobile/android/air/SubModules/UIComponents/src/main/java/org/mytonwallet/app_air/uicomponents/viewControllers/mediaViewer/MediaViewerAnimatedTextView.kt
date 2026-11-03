package org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.view.View
import android.view.animation.LinearInterpolator
import androidx.core.text.BidiFormatter
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator

/** One line of text that animates only what changes; a port of Telegram's AnimatedTextView. */
@SuppressLint("ViewConstructor")
internal class MediaViewerAnimatedTextView(context: Context, private val motion: Motion) :
    View(context) {
    enum class Motion {
        VERTICAL,

        HORIZONTAL
    }

    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG)

    var text: CharSequence = ""
        private set

    // [opposite]: index of the same run in the other text, or -1
    private class Part(val layout: StaticLayout, val offset: Float, val opposite: Int) {
        private val hasLine = layout.lineCount > 0
        val left = if (hasLine) layout.getLineLeft(0) else 0f
        val width = if (hasLine) layout.getLineWidth(0) else 0f
        val baseline = if (hasLine) layout.getLineBaseline(0).toFloat() else 0f
        val belowBaseline = layout.height - baseline
    }

    private var currentParts = emptyList<Part>()
    private var currentWidth = 0f
    private var currentBaseline = 0f
    private var currentBelowBaseline = 0f
    private var oldParts: List<Part>? = null
    private var oldWidth = 0f
    private var oldBaseline = 0f
    private var oldBelowBaseline = 0f
    private var isRtl = false
    private var direction = 1
    private var progress = 0f
    private var animator: ValueAnimator? = null
    private var pendingText: CharSequence? = null
    private var pendingDirection = 1
    private var laidOutWidth = -1

    /** [direction]: the side new runs come from, 1 the end, -1 the start. */
    fun setText(text: CharSequence?, animated: Boolean, direction: Int = 1) {
        val newText = text ?: ""
        contentDescription = newText.takeIf { it.isNotEmpty() }
        if (!animated || this.text.isEmpty() || newText.isEmpty()) {
            cancelAnimation()
            layOut(newText)
            return
        }
        if (TextUtils.equals(newText, this.text) && pendingText == null) return
        if (animator?.isRunning == true) {
            pendingText = newText
            pendingDirection = direction
            return
        }
        animateTo(newText, direction)
    }

    fun cancelAnimation() {
        pendingText = null
        animator?.cancel()
        animator = null
        clearOldParts()
    }

    private fun layOut(newText: CharSequence) {
        text = newText
        isRtl = isRtl(newText)
        val part = Part(makeLayout(newText, availableWidth()), 0f, -1)
        currentParts = listOf(part)
        currentWidth = part.width
        currentBaseline = part.baseline
        currentBelowBaseline = part.belowBaseline
        clearOldParts()
        invalidate()
    }

    private fun animateTo(newText: CharSequence, direction: Int) {
        val oldText = text
        text = newText
        isRtl = isRtl(newText)
        this.direction = direction
        val width = availableWidth()
        val current = ArrayList<Part>()
        val old = ArrayList<Part>()
        var newWidth = 0f
        var previousWidth = 0f
        // The order of the calls matters: each run is laid out after the ones before it
        diff(
            oldText,
            newText,
            onEqual = { run ->
                val layout = makeLayout(run, width - ceil(min(newWidth, previousWidth)).toInt())
                val currentPart = Part(layout, newWidth, old.size)
                current.add(currentPart)
                old.add(Part(layout, previousWidth, current.size - 1))
                newWidth += currentPart.width
                previousWidth += currentPart.width
            },
            onNew = { run ->
                val part = Part(makeLayout(run, width - ceil(newWidth).toInt()), newWidth, -1)
                current.add(part)
                newWidth += part.width
            },
            onOld = { run ->
                val layout = makeLayout(run, width - ceil(previousWidth).toInt())
                val part = Part(layout, previousWidth, -1)
                old.add(part)
                previousWidth += part.width
            }
        )
        currentParts = current
        currentWidth = newWidth
        currentBaseline = current.maxOfOrNull { it.baseline } ?: 0f
        currentBelowBaseline = current.maxOfOrNull { it.belowBaseline } ?: 0f
        oldParts = old
        oldWidth = previousWidth
        oldBaseline = old.maxOfOrNull { it.baseline } ?: 0f
        oldBelowBaseline = old.maxOfOrNull { it.belowBaseline } ?: 0f
        animator?.cancel()
        progress = 0f
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = DURATION_MS
            interpolator = LinearInterpolator()
            addUpdateListener {
                progress = INTERPOLATOR.getInterpolation(it.animatedValue as Float)
                invalidate()
            }
            addListener(object : AnimatorListenerAdapter() {
                private var isCanceled = false

                override fun onAnimationCancel(animation: Animator) {
                    isCanceled = true
                }

                override fun onAnimationEnd(animation: Animator) {
                    if (animator === animation) animator = null
                    clearOldParts()
                    invalidate()
                    if (isCanceled) return
                    pendingText?.let { next ->
                        pendingText = null
                        setText(next, animated = true, pendingDirection)
                    }
                }
            })
            start()
        }
    }

    private fun clearOldParts() {
        oldParts = null
        oldWidth = 0f
        oldBaseline = 0f
        oldBelowBaseline = 0f
        progress = 0f
    }

    /** Telegram's diff: runs go to [onEqual], [onNew] and [onOld] in layout order. */
    private fun diff(
        oldText: CharSequence,
        newText: CharSequence,
        onEqual: (CharSequence) -> Unit,
        onNew: (CharSequence) -> Unit,
        onOld: (CharSequence) -> Unit
    ) {
        var newStart = 0
        var oldStart = 0
        var isEqual = true
        var newIndex = 0
        var oldIndex = 0
        val minLength = min(newText.length, oldText.length)
        while (newIndex <= minLength) {
            val isThisEqual = newIndex < minLength && oldIndex < oldText.length &&
                newText[newIndex] == oldText[oldIndex]
            if (isEqual != isThisEqual || newIndex == minLength) {
                if (newIndex == minLength) {
                    newIndex = newText.length
                    oldIndex = oldText.length
                }
                val newLength = newIndex - newStart
                val oldLength = oldIndex - oldStart
                if (newLength > 0 || oldLength > 0) {
                    if (newLength == oldLength && isEqual) {
                        onEqual(newText.subSequence(newStart, newIndex))
                    } else {
                        if (newLength > 0) onNew(newText.subSequence(newStart, newIndex))
                        if (oldLength > 0) onOld(oldText.subSequence(oldStart, oldIndex))
                    }
                }
                isEqual = isThisEqual
                newStart = newIndex
                oldStart = oldIndex
                if (newIndex >= newText.length) break
            }
            if (isThisEqual) oldIndex++
            newIndex++
        }
    }

    private fun availableWidth(): Int {
        val width = width - paddingLeft - paddingRight
        if (width > 0) return width
        val display = resources.displayMetrics
        return min(display.widthPixels, display.heightPixels)
    }

    private fun makeLayout(run: CharSequence, width: Int): StaticLayout {
        val layoutWidth = width.coerceAtLeast(1)
        return StaticLayout.Builder.obtain(run, 0, run.length, paint, layoutWidth)
            .setMaxLines(1)
            .setLineSpacing(0f, 1f)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setEllipsize(TextUtils.TruncateAt.END)
            .setEllipsizedWidth(layoutWidth)
            .setIncludePad(true)
            .build()
    }

    private fun isRtl(text: CharSequence) =
        text.isNotEmpty() && BidiFormatter.getInstance().isRtl(text)

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val metrics = paint.fontMetricsInt
        val lineHeight = metrics.bottom - metrics.top
        setMeasuredDimension(
            MeasureSpec.getSize(widthMeasureSpec),
            resolveSize(lineHeight + paddingTop + paddingBottom, heightMeasureSpec)
        )
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val width = right - left
        if (width == laidOutWidth) return
        laidOutWidth = width
        cancelAnimation()
        layOut(text)
    }

    override fun onDraw(canvas: Canvas) {
        val fullWidth = (width - paddingLeft - paddingRight).toFloat()
        val fullHeight = (height - paddingTop - paddingBottom).toFloat()
        canvas.save()
        canvas.translate(paddingLeft.toFloat(), paddingTop.toFloat())
        val old = oldParts
        if (old != null) {
            drawTransition(canvas, old, fullWidth, fullHeight)
        } else {
            canvas.translate(0f, (fullHeight - (currentBaseline + currentBelowBaseline)) / 2f)
            for (part in currentParts) {
                val x = place(part, currentWidth, fullWidth, currentWidth)
                drawPart(canvas, part, x, currentBaseline - part.baseline, 1f)
            }
        }
        canvas.restore()
    }

    private fun drawTransition(
        canvas: Canvas,
        old: List<Part>,
        fullWidth: Float,
        fullHeight: Float
    ) {
        val t = progress
        val width = lerp(oldWidth, currentWidth, t)
        val height = lerp(oldBaseline + oldBelowBaseline, currentBaseline + currentBelowBaseline, t)
        val baseline = lerp(oldBaseline, currentBaseline, t)
        canvas.translate(0f, (fullHeight - height) / 2f)
        val verticalShift = paint.textSize * VERTICAL_AMPLITUDE
        val sideMultiplier = if (layoutDirection == LAYOUT_DIRECTION_RTL) -1f else 1f
        val horizontalShift = HORIZONTAL_AMPLITUDE.dp * direction * sideMultiplier
        for (part in currentParts) {
            var y = baseline - part.baseline
            val x = if (part.opposite >= 0) {
                val previous = old[part.opposite]
                lerp(
                    place(previous, oldWidth, fullWidth, width),
                    place(part, currentWidth, fullWidth, width),
                    t
                )
            } else {
                var x = place(part, currentWidth, fullWidth, currentWidth)
                when (motion) {
                    Motion.VERTICAL -> y -= verticalShift * (1f - t)
                    Motion.HORIZONTAL -> x += horizontalShift * (1f - t)
                }
                x
            }
            drawPart(canvas, part, x, y, if (part.opposite >= 0) 1f else t)
        }
        for (part in old) {
            if (part.opposite >= 0) continue
            var x = place(part, oldWidth, fullWidth, oldWidth)
            var y = baseline - part.baseline
            when (motion) {
                Motion.VERTICAL -> y += verticalShift * t
                Motion.HORIZONTAL -> x -= horizontalShift * t
            }
            drawPart(canvas, part, x, y, 1f - t)
        }
    }

    private fun place(part: Part, textWidth: Float, fullWidth: Float, lineWidth: Float): Float {
        var x = part.offset
        if (isRtl) x = textWidth - (x + part.width)
        x -= part.left
        if (isRtl) x += fullWidth - lineWidth
        return x
    }

    private fun drawPart(canvas: Canvas, part: Part, x: Float, y: Float, alpha: Float) {
        val drawAlpha = (alpha * 255).roundToInt().coerceIn(0, 255)
        if (drawAlpha == 0) return
        canvas.save()
        canvas.translate(x, y)
        if (drawAlpha < 255) {
            val layerWidth = max(part.layout.width, 1).toFloat()
            canvas.saveLayerAlpha(0f, 0f, layerWidth, part.layout.height.toFloat(), drawAlpha)
            part.layout.draw(canvas)
            canvas.restore()
        } else {
            part.layout.draw(canvas)
        }
        canvas.restore()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        cancelAnimation()
    }

    private companion object {
        const val DURATION_MS = 320L
        const val VERTICAL_AMPLITUDE = 0.4f

        const val HORIZONTAL_AMPLITUDE = 8

        val INTERPOLATOR = CubicBezierInterpolator.EASE_OUT_QUINT

        fun lerp(from: Float, to: Float, fraction: Float) = from + (to - from) * fraction
    }
}
