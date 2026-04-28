package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.text.TextPaint
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.animation.AccelerateDecelerateInterpolator
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import java.util.Arrays
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

abstract class BaseChartView<T : ChartData, L : LineViewData>(
    context: Context,
) : View(context), ChartPickerDelegate.Listener, WThemedView {
    protected val HORIZONTAL_PADDING get() = Companion.HORIZONTAL_PADDING
    protected val SIGNATURE_TEXT_HEIGHT get() = Companion.SIGNATURE_TEXT_HEIGHT
    protected val PICKER_PADDING get() = Companion.PICKER_PADDING
    protected val USE_LINES get() = Companion.USE_LINES
    protected val ANIMATE_PICKER_SIZES get() = Companion.ANIMATE_PICKER_SIZES
    protected val INTERPOLATOR get() = Companion.INTERPOLATOR
    protected val TRANSITION_MODE_CHILD get() = Companion.TRANSITION_MODE_CHILD
    protected val TRANSITION_MODE_PARENT get() = Companion.TRANSITION_MODE_PARENT
    protected val TRANSITION_MODE_ALPHA_ENTER get() = Companion.TRANSITION_MODE_ALPHA_ENTER
    protected val TRANSITION_MODE_NONE get() = Companion.TRANSITION_MODE_NONE

    var style: ChartStyle = ChartStyle.default()
        set(value) {
            field = value
            sharedUiComponents.style = value
            linePaint.strokeWidth = value.hintLineWidth
            lines.forEach { it.updateTheme() }
            legendSignatureView.style = value
            updateTheme()
        }

    var sharedUiComponents: SharedUiComponents = SharedUiComponents(style)
    var horizontalLines = ArrayList<ChartHorizontalLinesData>(10)
    var bottomSignatureDate = ArrayList<ChartBottomSignatureData>(25)
    var lines = ArrayList<L>()

    private val ANIM_DURATION = 400L

    protected var drawPointOnSelection = true
    var signaturePaintAlpha = 0f
    var bottomSignaturePaintAlpha = 0f
    var hintLinePaintAlpha = 0
    var chartActiveLineAlpha = 0

    var chartBottom = 0
    var currentMaxHeight = 250f
    var currentMinHeight = 0f
    var animateToMaxHeight = 0f
    var animateToMinHeight = 0f
    var thresholdMaxHeight = 0f

    var startXIndex = 0
    var endXIndex = 0
    var invalidatePickerChart = true
    var isLandscape = false

    val emptyPaint = Paint()
    val linePaint = Paint()
    val selectedLinePaint = Paint()
    val signaturePaint = TextPaint(TextPaint.ANTI_ALIAS_FLAG)
    val signaturePaint2 = TextPaint(TextPaint.ANTI_ALIAS_FLAG)
    val bottomSignaturePaint = TextPaint(TextPaint.ANTI_ALIAS_FLAG)
    val horizontalLabelBackgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    val pickerSelectorPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    val unactiveBottomChartPaint = Paint()
    val selectionBackgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    val ripplePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    val whiteLinePaint = Paint(Paint.ANTI_ALIAS_FLAG)

    val pickerRect = Rect()
    val pathTmp = Path()
    private val horizontalLabelBackgroundRect = RectF()
    private val labelHorizontalPadding = 4f.dp
    private val labelVerticalPadding = 2f.dp

    var maxValueAnimator: Animator? = null
    var alphaAnimator: ValueAnimator? = null
    var alphaBottomAnimator: ValueAnimator? = null
    var pickerAnimator: Animator? = null
    var selectionAnimator: ValueAnimator? = null
    var postTransition = false

    var pickerDelegate = ChartPickerDelegate(this)
    var pickerMode: ChartPickerDelegate.PickerMode = ChartPickerDelegate.PickerMode.RANGE
        set(value) {
            if (field == value) return
            field = value
            pickerDelegate.pickerMode = value
            invalidate()
        }
    protected var chartData: T? = null

    protected var currentBottomSignatures: ChartBottomSignatureData? = null
    protected var pickerMaxHeight = 0f
    protected var pickerMinHeight = 0f
    protected var animatedToPickerMaxHeight = 0f
    protected var animatedToPickerMinHeight = 0f
    protected var tmpN = 0
    protected var tmpI = 0
    protected var bottomSignatureOffset = 0

    private var bottomChartBitmap: Bitmap? = null
    private var bottomChartCanvas: Canvas? = null

    protected var chartCaptured = false
    protected var selectedIndex = -1
    protected var selectedCoordinate = -1f

    lateinit var legendSignatureView: LegendSignatureView
    var legendShowing = false
    var selectionA = 0f
    var superDraw = false
    var useAlphaSignature = false
    var valueFormatter: ChartValueFormatter? = null
        set(value) {
            field = value
            if (this::legendSignatureView.isInitialized) {
                legendSignatureView.valueFormatter = value
            }
        }
    private var horizontalLabelBackgroundAlpha = 0f

    var transitionMode = TRANSITION_MODE_NONE
    var transitionParams: TransitionParams? = null

    private val touchSlop: Int = ViewConfiguration.get(context).scaledTouchSlop

    var pikerHeight = 46.dp
    var pickerWidth = 0f
    var chartStart = 0f
    var chartEnd = 0f
    var chartWidth = 0f
    var chartFullWidth = 0f
    var chartArea = RectF()

    private var vibrationEffect: VibrationEffect? = null

    private val pickerHeightUpdateListener = ValueAnimator.AnimatorUpdateListener { animation ->
        pickerMaxHeight = animation.animatedValue as Float
        invalidatePickerChart = true
        invalidate()
    }

    private val pickerMinHeightUpdateListener = ValueAnimator.AnimatorUpdateListener { animation ->
        pickerMinHeight = animation.animatedValue as Float
        invalidatePickerChart = true
        invalidate()
    }

    private val heightUpdateListener = ValueAnimator.AnimatorUpdateListener { animation ->
        currentMaxHeight = animation.animatedValue as Float
        invalidate()
    }

    private val minHeightUpdateListener = ValueAnimator.AnimatorUpdateListener { animation ->
        currentMinHeight = animation.animatedValue as Float
        invalidate()
    }

    private val selectionAnimatorListener = ValueAnimator.AnimatorUpdateListener { animation ->
        selectionA = animation.animatedValue as Float
        legendSignatureView.alpha = selectionA
        invalidate()
    }

    private val selectorAnimatorEndListener = object : AnimatorListenerAdapter() {
        override fun onAnimationEnd(animation: Animator) {
            if (!animateLegentTo) {
                legendShowing = false
                legendSignatureView.visibility = GONE
                invalidate()
            }
            postTransition = false
        }
    }

    protected var useMinHeight = false
    private var selectionListener: DateSelectionListener? = null
    private var startFromMax = 0f
    private var startFromMin = 0f
    private var startFromMaxH = 0f
    private var startFromMinH = 0f
    private var minMaxUpdateStep = 0f

    private var lastW = 0
    private var lastH = 0

    private val exclusionRect = Rect()
    private val exclusionRects = arrayListOf(exclusionRect)

    private var lastTime = 0L
    private var lastX = 0
    private var lastY = 0
    private var capturedX = 0
    private var capturedY = 0
    private var capturedTime = 0L
    private var lastHeaderStartDate = Long.MIN_VALUE
    private var lastHeaderEndDate = Long.MIN_VALUE
    private var rangePickerLeftDrawable: Drawable? = null
    private var rangePickerRightDrawable: Drawable? = null

    protected var canCaptureChartSelection = false
    var animateLegentTo = false
    private var chartHeaderView: ChartHeaderView? = null

    init {
        init()
    }

    protected open fun init() {
        linePaint.strokeWidth = style.hintLineWidth
        selectedLinePaint.strokeWidth = SELECTED_LINE_WIDTH

        signaturePaint.textSize = SIGNATURE_TEXT_SIZE
        signaturePaint2.textSize = SIGNATURE_TEXT_SIZE
        signaturePaint2.textAlign = Paint.Align.RIGHT
        bottomSignaturePaint.textSize = SIGNATURE_TEXT_SIZE
        bottomSignaturePaint.textAlign = Paint.Align.CENTER

        selectionBackgroundPaint.strokeWidth = 6f.dp
        selectionBackgroundPaint.strokeCap = Paint.Cap.ROUND

        setLayerType(LAYER_TYPE_HARDWARE, null)
        setWillNotDraw(false)

        legendSignatureView = createLegendView()
        legendSignatureView.valueFormatter = valueFormatter
        legendSignatureView.visibility = GONE

        whiteLinePaint.color = Color.WHITE
        whiteLinePaint.strokeWidth = 3f.dp
        whiteLinePaint.strokeCap = Paint.Cap.ROUND

        updatePickerFrameResources()
        updateTheme()
    }

    protected open fun createLegendView(): LegendSignatureView {
        return LegendSignatureView(context).apply {
            this.style = this@BaseChartView.style
        }
    }

    override fun updateTheme() {
        signaturePaint.color =
            if (useAlphaSignature) style.signatureAlphaColor else style.signatureColor
        signaturePaint2.color =
            if (useAlphaSignature) style.signatureAlphaColor else style.signatureColor
        bottomSignaturePaint.color = style.signatureColor
        linePaint.color = style.hintLineColor
        selectedLinePaint.color = style.activeLineColor
        horizontalLabelBackgroundPaint.color = style.backgroundColor.colorWithAlpha(128)
        pickerSelectorPaint.color = style.activePickerColor
        unactiveBottomChartPaint.color = style.inactivePickerColor
        selectionBackgroundPaint.color = style.backgroundColor
        ripplePaint.color = style.rippleColor
        legendSignatureView.recolor()

        hintLinePaintAlpha = linePaint.alpha
        chartActiveLineAlpha = selectedLinePaint.alpha
        signaturePaintAlpha = signaturePaint.alpha / 255f
        bottomSignaturePaintAlpha = bottomSignaturePaint.alpha / 255f
        horizontalLabelBackgroundAlpha = horizontalLabelBackgroundPaint.alpha / 255f
        sharedUiComponents.invalidate()
        updatePickerFrameResources()

        for (line in lines) {
            line.updateTheme()
        }

        val data = chartData
        if (legendShowing && data != null && selectedIndex < data.x.size) {
            @Suppress("UNCHECKED_CAST")
            legendSignatureView.setData(
                selectedIndex,
                data.x[selectedIndex],
                lines as ArrayList<LineViewData>,
                false,
                data.yTooltipFormatter,
                data.yRate
            )
        }

        invalidatePickerChart = true
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        if (!isLandscape) {
            setMeasuredDimension(
                MeasureSpec.getSize(widthMeasureSpec),
                MeasureSpec.getSize(widthMeasureSpec)
            )
        } else {
            setMeasuredDimension(
                MeasureSpec.getSize(widthMeasureSpec),
                ChartFormatters.screenHeightPx - 56.dp
            )
        }

        if (measuredWidth != lastW || measuredHeight != lastH) {
            lastW = measuredWidth
            lastH = measuredHeight
            val bitmapWidth = (measuredWidth - HORIZONTAL_PADDING * 2f).toInt()
            if (bitmapWidth > 0 && pikerHeight > 0) {
                bottomChartBitmap =
                    Bitmap.createBitmap(bitmapWidth, pikerHeight, Bitmap.Config.ARGB_4444)
                bottomChartCanvas = Canvas(bottomChartBitmap!!)
                sharedUiComponents.getPickerMaskBitmap(pikerHeight, bitmapWidth)
            }
            measureSizes()
            if (legendShowing) {
                moveLegend(chartFullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING)
            }
            onPickerDataChanged(false, true, false)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            exclusionRect.set(
                0,
                measuredHeight - (PICKER_PADDING + pikerHeight + PICKER_PADDING),
                measuredWidth,
                measuredHeight
            )
            systemGestureExclusionRects = exclusionRects
        }
    }

    private fun measureSizes() {
        if (measuredHeight <= 0 || measuredWidth <= 0) {
            return
        }
        pickerWidth = measuredWidth - HORIZONTAL_PADDING * 2f
        chartStart = HORIZONTAL_PADDING
        chartEnd =
            measuredWidth - if (isLandscape) LANDSCAPE_END_PADDING.toFloat() else HORIZONTAL_PADDING
        chartWidth = chartEnd - chartStart
        chartFullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)

        updateLineSignature()
        chartBottom = 100.dp
        legendSignatureView.setMaxChartHeight((measuredHeight - chartBottom - 16.dp).coerceAtLeast(0))
        chartArea.set(
            chartStart - HORIZONTAL_PADDING,
            0f,
            chartEnd + HORIZONTAL_PADDING,
            (measuredHeight - chartBottom).toFloat()
        )

        chartData?.let {
            bottomSignatureOffset = (20.dp / (pickerWidth / it.x.size)).toInt()
        }
        measureHeightThreshold()
    }

    private fun measureHeightThreshold() {
        val chartHeight = measuredHeight - chartBottom
        if (animateToMaxHeight == 0f || chartHeight == 0) {
            return
        }
        thresholdMaxHeight = animateToMaxHeight / chartHeight * SIGNATURE_TEXT_SIZE
    }

    protected open fun drawPickerChart(canvas: Canvas) {
    }

    override fun onDraw(canvas: Canvas) {
        if (superDraw) {
            super.onDraw(canvas)
            return
        }
        tick()
        val count = canvas.save()
        canvas.clipRect(0f, chartArea.top, measuredWidth.toFloat(), chartArea.bottom)

        drawBottomLine(canvas)
        tmpN = horizontalLines.size
        for (i in 0 until tmpN) {
            tmpI = i
            drawHorizontalLines(canvas, horizontalLines[i])
        }

        drawChart(canvas)

        for (i in 0 until tmpN) {
            tmpI = i
            drawSignaturesToHorizontalLines(canvas, horizontalLines[i])
        }

        canvas.restoreToCount(count)
        drawBottomSignature(canvas)
        drawPicker(canvas)
        drawSelection(canvas)

        super.onDraw(canvas)
    }

    protected open fun tick() {
        if (minMaxUpdateStep == 0f) {
            return
        }
        if (currentMaxHeight != animateToMaxHeight) {
            startFromMax += minMaxUpdateStep
            if (startFromMax > 1f) {
                startFromMax = 1f
                currentMaxHeight = animateToMaxHeight
            } else {
                currentMaxHeight =
                    startFromMaxH + (animateToMaxHeight - startFromMaxH) * INTERPOLATOR.getInterpolation(
                        startFromMax
                    )
            }
            invalidate()
        }
        if (useMinHeight && currentMinHeight != animateToMinHeight) {
            startFromMin += minMaxUpdateStep
            if (startFromMin > 1f) {
                startFromMin = 1f
                currentMinHeight = animateToMinHeight
            } else {
                currentMinHeight =
                    startFromMinH + (animateToMinHeight - startFromMinH) * INTERPOLATOR.getInterpolation(
                        startFromMin
                    )
            }
            invalidate()
        }
    }

    protected open fun drawBottomSignature(canvas: Canvas) {
        val data = chartData ?: return
        tmpN = bottomSignatureDate.size
        val transitionAlpha = getChartTransitionAlpha()
        for (signatureData in bottomSignatureDate) {
            var step = signatureData.step
            if (step == 0) {
                step = 1
            }

            var start = startXIndex - bottomSignatureOffset
            while (start % step != 0) {
                start--
            }
            var end = endXIndex - bottomSignatureOffset
            while (end % step != 0 || end < data.x.size - 1) {
                end++
            }
            start += bottomSignatureOffset
            end += bottomSignatureOffset

            val offset = chartFullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING
            for (i in start until end step step) {
                if (i < 0 || i >= data.x.size - 1) {
                    continue
                }
                val xPercentage =
                    (data.x[i] - data.x[0]).toFloat() / (data.x[data.x.size - 1] - data.x[0]).toFloat()
                val xPoint = xPercentage * chartFullWidth - offset
                val xPointOffset = xPoint - BOTTOM_SIGNATURE_OFFSET
                if (xPointOffset > 0 && xPointOffset <= chartWidth + HORIZONTAL_PADDING) {
                    bottomSignaturePaint.alpha = when {
                        xPointOffset < BOTTOM_SIGNATURE_START_ALPHA -> {
                            val a =
                                1f - (BOTTOM_SIGNATURE_START_ALPHA - xPointOffset) / BOTTOM_SIGNATURE_START_ALPHA
                            (signatureData.alpha * a * bottomSignaturePaintAlpha * transitionAlpha).toInt()
                        }

                        xPointOffset > chartWidth -> {
                            val a = 1f - (xPointOffset - chartWidth) / HORIZONTAL_PADDING
                            (signatureData.alpha * a * bottomSignaturePaintAlpha * transitionAlpha).toInt()
                        }

                        else -> (signatureData.alpha * bottomSignaturePaintAlpha * transitionAlpha).toInt()
                    }
                    canvas.drawText(
                        data.getDayString(i),
                        xPoint,
                        measuredHeight - chartBottom + BOTTOM_SIGNATURE_TEXT_HEIGHT + 3.dp.toFloat(),
                        bottomSignaturePaint
                    )
                }
            }
        }
    }

    protected open fun drawBottomLine(canvas: Canvas) {
        chartData ?: return
        val transitionAlpha = getChartTransitionAlpha()
        linePaint.alpha = (hintLinePaintAlpha * transitionAlpha).toInt()
        signaturePaint.alpha = (255 * signaturePaintAlpha * transitionAlpha).toInt()
        signaturePaint2.alpha = (255 * signaturePaintAlpha * transitionAlpha).toInt()
        val textOffset = (SIGNATURE_TEXT_HEIGHT - signaturePaint.textSize).toInt()
        val y = measuredHeight - chartBottom - 1
        canvas.drawLine(chartStart, y.toFloat(), chartEnd, y.toFloat(), linePaint)
        if (useMinHeight) {
            return
        }
        val zeroLabel = formatZeroAxisLabel().toString()
        val textX = HORIZONTAL_PADDING
        val textY = (y - textOffset).toFloat()
        //val backgroundAlpha = (signaturePaint.alpha * horizontalLabelBackgroundAlpha).toInt()
        /*if (backgroundAlpha > 0) {
            val textWidth = signaturePaint.measureText(zeroLabel)
            val top = textY + signaturePaint.ascent()
            val bottom = textY + signaturePaint.descent()
            horizontalLabelBackgroundRect.set(textX, top, textX + textWidth, bottom)
            horizontalLabelBackgroundRect.inset(-labelHorizontalPadding, -labelVerticalPadding)
            horizontalLabelBackgroundPaint.alpha = backgroundAlpha
            canvas.drawRoundRect(
                horizontalLabelBackgroundRect,
                16f.dp,
                16f.dp,
                horizontalLabelBackgroundPaint
            )
        }*/
        canvas.drawText(zeroLabel, textX, textY, signaturePaint)
    }

    protected open fun drawSelection(canvas: Canvas) {
        val data = chartData ?: return
        if (selectedIndex < 0 || !legendShowing) {
            return
        }

        val alpha = (chartActiveLineAlpha * selectionA).toInt()
        val fullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)
        val offset = fullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING
        if (selectedIndex >= data.xPercentage.size) {
            return
        }
        val xPoint = data.xPercentage[selectedIndex] * fullWidth - offset

        selectedLinePaint.alpha = alpha
        canvas.drawLine(xPoint, 0f, xPoint, chartArea.bottom, selectedLinePaint)

        if (drawPointOnSelection) {
            for (line in lines) {
                if (!line.enabled && line.alpha == 0f) {
                    continue
                }
                val yPercentage =
                    (line.line.y[selectedIndex] - currentMinHeight) / (currentMaxHeight - currentMinHeight)
                val yPoint =
                    measuredHeight - chartBottom - yPercentage * (measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT)
                line.selectionPaint.alpha = (255 * line.alpha * selectionA).toInt()
                selectionBackgroundPaint.alpha = (255 * line.alpha * selectionA).toInt()
                canvas.drawPoint(xPoint, yPoint, line.selectionPaint)
                canvas.drawPoint(xPoint, yPoint, selectionBackgroundPaint)
            }
        }
    }

    protected open fun drawChart(canvas: Canvas) {
    }

    protected open fun drawHorizontalLines(canvas: Canvas, a: ChartHorizontalLinesData) {
        val n = a.values.size
        var additionalOutAlpha = 1f
        if (n > 2) {
            val v = (a.values[1] - a.values[0]) / (currentMaxHeight - currentMinHeight)
            if (v < 0.1f) {
                additionalOutAlpha = v / 0.1f
            }
        }

        val transitionAlpha = getChartTransitionAlpha()
        linePaint.alpha =
            (a.alpha * (hintLinePaintAlpha / 255f) * transitionAlpha * additionalOutAlpha).toInt()
        signaturePaint.alpha =
            (a.alpha * signaturePaintAlpha * transitionAlpha * additionalOutAlpha).toInt()
        signaturePaint2.alpha =
            (a.alpha * signaturePaintAlpha * transitionAlpha * additionalOutAlpha).toInt()
        val chartHeight = measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT
        val start = if (useMinHeight) 0 else 1
        for (i in start until n) {
            val y =
                (measuredHeight - chartBottom) - chartHeight * ((a.values[i] - currentMinHeight) / (currentMaxHeight - currentMinHeight))
            canvas.drawLine(chartStart, y, chartEnd, y, linePaint)
        }
    }

    protected open fun drawSignaturesToHorizontalLines(
        canvas: Canvas,
        a: ChartHorizontalLinesData
    ) {
        val n = a.values.size
        var additionalOutAlpha = 1f
        if (n > 2) {
            val v = (a.values[1] - a.values[0]) / (currentMaxHeight - currentMinHeight)
            if (v < 0.1f) {
                additionalOutAlpha = v / 0.1f
            }
        }

        val transitionAlpha = getChartTransitionAlpha()
        linePaint.alpha =
            (a.alpha * (hintLinePaintAlpha / 255f) * transitionAlpha * additionalOutAlpha).toInt()
        signaturePaint.alpha =
            (a.alpha * signaturePaintAlpha * transitionAlpha * additionalOutAlpha).toInt()
        signaturePaint2.alpha =
            (a.alpha * signaturePaintAlpha * transitionAlpha * additionalOutAlpha).toInt()
        val chartHeight = measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT
        val textOffset = (SIGNATURE_TEXT_HEIGHT - signaturePaint.textSize).toInt()
        val start = if (useMinHeight) 0 else 1
        for (i in start until n) {
            val y =
                (measuredHeight - chartBottom) - chartHeight * ((a.values[i] - currentMinHeight) / (currentMaxHeight - currentMinHeight))
            drawHorizontalLineSignature(
                canvas = canvas,
                linesData = a,
                axis = 0,
                index = i,
                x = HORIZONTAL_PADDING,
                y = y - textOffset,
                paint = signaturePaint,
            )
            if (a.valuesStr2 != null) {
                drawHorizontalLineSignature(
                    canvas = canvas,
                    linesData = a,
                    axis = 1,
                    index = i,
                    x = measuredWidth - HORIZONTAL_PADDING,
                    y = y - textOffset,
                    paint = signaturePaint2,
                )
            }
        }
    }

    protected fun drawHorizontalLineSignature(
        canvas: Canvas,
        linesData: ChartHorizontalLinesData,
        axis: Int,
        index: Int,
        x: Float,
        y: Float,
        paint: TextPaint,
    ) {
        /*val backgroundAlpha = (paint.alpha * horizontalLabelBackgroundAlpha).toInt()
        if (backgroundAlpha > 0 && linesData.getTextBounds(
                horizontalLabelBackgroundRect,
                axis,
                index,
                x,
                y,
                paint
            )
        ) {
            horizontalLabelBackgroundRect.inset(-labelHorizontalPadding, -labelVerticalPadding)
            horizontalLabelBackgroundPaint.alpha = backgroundAlpha
            canvas.drawRoundRect(
                horizontalLabelBackgroundRect,
                16f.dp,
                16f.dp,
                horizontalLabelBackgroundPaint
            )
        }*/
        linesData.drawText(canvas, axis, index, x, y, paint)
    }

    protected fun drawPicker(canvas: Canvas) {
        val data = chartData
        pickerDelegate.pickerWidth = pickerWidth
        val bottom = measuredHeight - PICKER_PADDING
        val top = measuredHeight - pikerHeight - PICKER_PADDING
        val isSinglePicker = pickerMode == ChartPickerDelegate.PickerMode.SINGLE
        val singleMorphProgress =
            if (isSinglePicker && transitionMode == TRANSITION_MODE_CHILD && transitionParams != null) {
                transitionParams?.progress ?: 1f
            } else if (isSinglePicker) {
                1f
            } else {
                0f
            }
        val singleRangeOverlayAlpha =
            if (isSinglePicker) ((0.85f - singleMorphProgress) / 0.85f).coerceIn(0f, 1f) else 1f
        val singleFullOverlayAlpha =
            if (isSinglePicker) ((singleMorphProgress - 0.15f) / 0.85f).coerceIn(0f, 1f) else 0f
        val singleBarAlpha =
            if (isSinglePicker) ((singleMorphProgress - 0.55f) / 0.45f).coerceIn(0f, 1f) else 0f

        var start = (HORIZONTAL_PADDING + pickerWidth * pickerDelegate.pickerStart).toInt()
        var end = (HORIZONTAL_PADDING + pickerWidth * pickerDelegate.pickerEnd).toInt()

        var transitionAlpha = 1f
        val params = transitionParams
        when (transitionMode) {
            TRANSITION_MODE_CHILD -> if (params != null) {
                val startParent = (HORIZONTAL_PADDING + pickerWidth * params.pickerStartOut).toInt()
                val endParent = (HORIZONTAL_PADDING + pickerWidth * params.pickerEndOut).toInt()
                start += ((startParent - start) * (1f - params.progress)).toInt()
                end += ((endParent - end) * (1f - params.progress)).toInt()
            }

            TRANSITION_MODE_ALPHA_ENTER -> if (params != null) {
                transitionAlpha = params.progress
            }
        }

        var instantDraw = false
        if (data != null) {
            if (transitionMode == TRANSITION_MODE_NONE) {
                if (shouldAnimatePickerDuringLineAnimation()) {
                    for (l in lines) {
                        if ((l.animatorIn?.isRunning == true) || (l.animatorOut?.isRunning == true)) {
                            instantDraw = true
                            break
                        }
                    }
                }
            }
            if (instantDraw) {
                canvas.save()
                canvas.clipRect(
                    HORIZONTAL_PADDING,
                    measuredHeight - PICKER_PADDING - pikerHeight.toFloat(),
                    measuredWidth - HORIZONTAL_PADDING,
                    (measuredHeight - PICKER_PADDING).toFloat()
                )
                canvas.translate(
                    HORIZONTAL_PADDING,
                    (measuredHeight - PICKER_PADDING - pikerHeight).toFloat()
                )
                drawPickerChart(canvas)
                canvas.restore()
            } else if (invalidatePickerChart) {
                bottomChartBitmap?.eraseColor(0)
                bottomChartCanvas?.let { drawPickerChart(it) }
                invalidatePickerChart = false
            }
            if (!instantDraw) {
                emptyPaint.alpha = 255
                bottomChartBitmap?.let {
                    canvas.drawBitmap(
                        it,
                        HORIZONTAL_PADDING,
                        (measuredHeight - PICKER_PADDING - pikerHeight).toFloat(),
                        emptyPaint
                    )
                }
            }

            if (transitionMode == TRANSITION_MODE_PARENT) {
                return
            }

            if (isSinglePicker) {
                if (singleRangeOverlayAlpha > 0f) {
                    drawInactiveRangeOverlay(
                        canvas = canvas,
                        top = top,
                        bottom = bottom,
                        start = start,
                        end = end,
                        alphaFraction = singleRangeOverlayAlpha,
                    )
                }
                if (singleFullOverlayAlpha > 0f) {
                    drawInactiveFullOverlay(
                        canvas = canvas,
                        top = top,
                        bottom = bottom,
                        alphaFraction = singleFullOverlayAlpha,
                    )
                }
            } else {
                drawInactiveRangeOverlay(
                    canvas = canvas,
                    top = top,
                    bottom = bottom,
                    start = start,
                    end = end,
                    alphaFraction = 1f,
                )
            }
        } else {
            canvas.drawRect(
                HORIZONTAL_PADDING,
                top.toFloat(),
                measuredWidth - HORIZONTAL_PADDING,
                bottom.toFloat(),
                unactiveBottomChartPaint
            )
        }

        canvas.drawBitmap(
            sharedUiComponents.getPickerMaskBitmap(
                pikerHeight,
                (measuredWidth - HORIZONTAL_PADDING * 2).toInt()
            ),
            HORIZONTAL_PADDING,
            (measuredHeight - PICKER_PADDING - pikerHeight).toFloat(),
            emptyPaint
        )

        if (data != null) {
            pickerRect.set(start, top, end, bottom)
            if (isSinglePicker) {
                val centerX = pickerRect.exactCenterX()
                val barHalfWidth = max(4f.dp, min(DP_6.toFloat(), pickerRect.width() / 2f))
                val barLeft = centerX - barHalfWidth
                val barRight = centerX + barHalfWidth
                val touchHalfWidth = max(PICKER_CAPTURE_WIDTH.toFloat(), barHalfWidth + DP_8)

                pickerDelegate.middlePickerArea.set(
                    (centerX - touchHalfWidth).toInt(),
                    top,
                    (centerX + touchHalfWidth).toInt(),
                    bottom
                )
                pickerDelegate.leftPickerArea.setEmpty()
                pickerDelegate.rightPickerArea.setEmpty()

                if (singleRangeOverlayAlpha > 0f) {
                    drawRangePickerFrame(canvas, pickerRect, singleRangeOverlayAlpha)
                }
                if (singleBarAlpha > 0f) {
                    drawSinglePickerFrame(
                        canvas = canvas,
                        left = barLeft,
                        top = (pickerRect.top - DP_1).toFloat(),
                        right = barRight,
                        bottom = (pickerRect.bottom + DP_1).toFloat(),
                        alphaFraction = singleBarAlpha,
                    )
                }

                pickerDelegate.getMiddleCaptured()?.let { middleCap ->
                    val rippleRadius =
                        ((pickerRect.bottom - pickerRect.top) shr 1) * middleCap.aValue - DP_2.toFloat()
                    if (rippleRadius > 0f) {
                        canvas.drawCircle(
                            centerX,
                            pickerRect.centerY().toFloat(),
                            rippleRadius,
                            ripplePaint
                        )
                    }
                }
            } else {
                pickerDelegate.middlePickerArea.set(pickerRect)

                canvas.drawPath(
                    RoundedRect(
                        pathTmp,
                        pickerRect.left.toFloat(),
                        (pickerRect.top - DP_1).toFloat(),
                        (pickerRect.left + DP_12).toFloat(),
                        (pickerRect.bottom + DP_1).toFloat(),
                        DP_8.toFloat(),
                        DP_8.toFloat(),
                        true,
                        false,
                        false,
                        true
                    ), pickerSelectorPaint
                )
                canvas.drawPath(
                    RoundedRect(
                        pathTmp,
                        (pickerRect.right - DP_12).toFloat(),
                        (pickerRect.top - DP_1).toFloat(),
                        pickerRect.right.toFloat(),
                        (pickerRect.bottom + DP_1).toFloat(),
                        DP_8.toFloat(),
                        DP_8.toFloat(),
                        false,
                        true,
                        true,
                        false
                    ), pickerSelectorPaint
                )

                canvas.drawRect(
                    (pickerRect.left + DP_12).toFloat(),
                    pickerRect.bottom.toFloat(),
                    (pickerRect.right - DP_12).toFloat(),
                    (pickerRect.bottom + DP_1).toFloat(),
                    pickerSelectorPaint
                )
                canvas.drawRect(
                    (pickerRect.left + DP_12).toFloat(),
                    (pickerRect.top - DP_1).toFloat(),
                    (pickerRect.right - DP_12).toFloat(),
                    pickerRect.top.toFloat(),
                    pickerSelectorPaint
                )

                canvas.drawLine(
                    (pickerRect.left + DP_6).toFloat(),
                    (pickerRect.centerY() - DP_6).toFloat(),
                    (pickerRect.left + DP_6).toFloat(),
                    (pickerRect.centerY() + DP_6).toFloat(),
                    whiteLinePaint
                )
                canvas.drawLine(
                    (pickerRect.right - DP_6).toFloat(),
                    (pickerRect.centerY() - DP_6).toFloat(),
                    (pickerRect.right - DP_6).toFloat(),
                    (pickerRect.centerY() + DP_6).toFloat(),
                    whiteLinePaint
                )

                val middleCap = pickerDelegate.getMiddleCaptured()
                val r = (pickerRect.bottom - pickerRect.top) shr 1
                val cY = pickerRect.top + r
                if (middleCap == null) {
                    val lCap = pickerDelegate.getLeftCaptured()
                    val rCap = pickerDelegate.getRightCaptured()
                    if (lCap != null) {
                        canvas.drawCircle(
                            (pickerRect.left + DP_5).toFloat(),
                            cY.toFloat(),
                            r * lCap.aValue - DP_2.toFloat(),
                            ripplePaint
                        )
                    }
                    if (rCap != null) {
                        canvas.drawCircle(
                            (pickerRect.right - DP_5).toFloat(),
                            cY.toFloat(),
                            r * rCap.aValue - DP_2.toFloat(),
                            ripplePaint
                        )
                    }
                }

                var cX = start
                pickerDelegate.leftPickerArea.set(
                    cX - PICKER_CAPTURE_WIDTH,
                    top,
                    cX + (PICKER_CAPTURE_WIDTH shr 1),
                    bottom
                )
                cX = end
                pickerDelegate.rightPickerArea.set(
                    cX - (PICKER_CAPTURE_WIDTH shr 1),
                    top,
                    cX + PICKER_CAPTURE_WIDTH,
                    bottom
                )
            }
        }
    }

    private fun drawInactiveRangeOverlay(
        canvas: Canvas,
        top: Int,
        bottom: Int,
        start: Int,
        end: Int,
        alphaFraction: Float,
    ) {
        if (alphaFraction <= 0f) return
        val previousAlpha = unactiveBottomChartPaint.alpha
        unactiveBottomChartPaint.alpha = (previousAlpha * alphaFraction).toInt()
        val overlayInset =
            if (style.useTokenChartPickerResources) PICKER_FRAME_HANDLE_WIDTH else DP_12
        canvas.drawRect(
            HORIZONTAL_PADDING,
            top.toFloat(),
            start + overlayInset.toFloat(),
            bottom.toFloat(),
            unactiveBottomChartPaint
        )
        canvas.drawRect(
            end - overlayInset.toFloat(),
            top.toFloat(),
            measuredWidth - HORIZONTAL_PADDING,
            bottom.toFloat(),
            unactiveBottomChartPaint
        )
        unactiveBottomChartPaint.alpha = previousAlpha
    }

    private fun drawInactiveFullOverlay(
        canvas: Canvas,
        top: Int,
        bottom: Int,
        alphaFraction: Float,
    ) {
        if (alphaFraction <= 0f) return
        val previousAlpha = unactiveBottomChartPaint.alpha
        unactiveBottomChartPaint.alpha = (previousAlpha * alphaFraction).toInt()
        canvas.drawRect(
            HORIZONTAL_PADDING,
            top.toFloat(),
            measuredWidth - HORIZONTAL_PADDING,
            bottom.toFloat(),
            unactiveBottomChartPaint
        )
        unactiveBottomChartPaint.alpha = previousAlpha
    }

    private fun drawSinglePickerFrame(
        canvas: Canvas,
        left: Float,
        top: Float,
        right: Float,
        bottom: Float,
        alphaFraction: Float,
    ) {
        if (alphaFraction <= 0f) return
        val previousAlpha = pickerSelectorPaint.alpha
        pickerSelectorPaint.alpha = (previousAlpha * alphaFraction).toInt()
        canvas.drawPath(
            RoundedRect(
                pathTmp,
                left,
                top,
                right,
                bottom,
                DP_8.toFloat(),
                DP_8.toFloat(),
                true,
                true,
                true,
                true
            ),
            pickerSelectorPaint
        )
        pickerSelectorPaint.alpha = previousAlpha
    }

    private fun drawRangePickerFrame(canvas: Canvas, pickerRect: Rect, alphaFraction: Float) {
        if (alphaFraction <= 0f) return

        if (style.useTokenChartPickerResources) {
            drawRangePickerFrameWithResources(canvas, pickerRect, alphaFraction)
            return
        }

        val previousPickerAlpha = pickerSelectorPaint.alpha
        val previousWhiteAlpha = whiteLinePaint.alpha
        pickerSelectorPaint.alpha = (previousPickerAlpha * alphaFraction).toInt()
        whiteLinePaint.alpha = (previousWhiteAlpha * alphaFraction).toInt()

        canvas.drawPath(
            RoundedRect(
                pathTmp,
                pickerRect.left.toFloat(),
                (pickerRect.top - DP_1).toFloat(),
                (pickerRect.left + DP_12).toFloat(),
                (pickerRect.bottom + DP_1).toFloat(),
                DP_8.toFloat(),
                DP_8.toFloat(),
                true,
                false,
                false,
                true
            ), pickerSelectorPaint
        )
        canvas.drawPath(
            RoundedRect(
                pathTmp,
                (pickerRect.right - DP_12).toFloat(),
                (pickerRect.top - DP_1).toFloat(),
                pickerRect.right.toFloat(),
                (pickerRect.bottom + DP_1).toFloat(),
                DP_8.toFloat(),
                DP_8.toFloat(),
                false,
                true,
                true,
                false
            ), pickerSelectorPaint
        )

        canvas.drawRect(
            (pickerRect.left + DP_12).toFloat(),
            pickerRect.bottom.toFloat(),
            (pickerRect.right - DP_12).toFloat(),
            (pickerRect.bottom + DP_1).toFloat(),
            pickerSelectorPaint
        )
        canvas.drawRect(
            (pickerRect.left + DP_12).toFloat(),
            (pickerRect.top - DP_1).toFloat(),
            (pickerRect.right - DP_12).toFloat(),
            pickerRect.top.toFloat(),
            pickerSelectorPaint
        )

        canvas.drawLine(
            (pickerRect.left + DP_6).toFloat(),
            (pickerRect.centerY() - DP_6).toFloat(),
            (pickerRect.left + DP_6).toFloat(),
            (pickerRect.centerY() + DP_6).toFloat(),
            whiteLinePaint
        )
        canvas.drawLine(
            (pickerRect.right - DP_6).toFloat(),
            (pickerRect.centerY() - DP_6).toFloat(),
            (pickerRect.right - DP_6).toFloat(),
            (pickerRect.centerY() + DP_6).toFloat(),
            whiteLinePaint
        )

        pickerSelectorPaint.alpha = previousPickerAlpha
        whiteLinePaint.alpha = previousWhiteAlpha
    }

    private fun drawRangePickerFrameWithResources(
        canvas: Canvas,
        pickerRect: Rect,
        alphaFraction: Float,
    ) {
        val alpha = (255 * alphaFraction).toInt()
        val top = (pickerRect.top - DP_1).toFloat()
        val bottom = (pickerRect.bottom + DP_1).toFloat()
        val leftHandleRight = pickerRect.left + PICKER_FRAME_HANDLE_WIDTH
        val rightHandleLeft = pickerRect.right - PICKER_FRAME_HANDLE_WIDTH
        rangePickerLeftDrawable?.let { drawable ->
            drawable.alpha = alpha
            drawable.setBounds(
                pickerRect.left,
                top.toInt(),
                leftHandleRight,
                bottom.toInt()
            )
            drawable.draw(canvas)
        }

        rangePickerRightDrawable?.let { drawable ->
            drawable.alpha = alpha
            drawable.setBounds(
                rightHandleLeft,
                top.toInt(),
                pickerRect.right,
                bottom.toInt()
            )
            drawable.draw(canvas)
        }

        val previousPickerAlpha = pickerSelectorPaint.alpha
        pickerSelectorPaint.alpha = (previousPickerAlpha * alphaFraction).toInt()
        canvas.drawRect(
            leftHandleRight.toFloat(),
            pickerRect.bottom.toFloat(),
            rightHandleLeft.toFloat(),
            (pickerRect.bottom + DP_1).toFloat(),
            pickerSelectorPaint
        )
        canvas.drawRect(
            leftHandleRight.toFloat(),
            (pickerRect.top - DP_1).toFloat(),
            rightHandleLeft.toFloat(),
            pickerRect.top.toFloat(),
            pickerSelectorPaint
        )
        pickerSelectorPaint.alpha = previousPickerAlpha
    }

    private fun setMaxMinValue(newMaxHeight: Long, newMinHeight: Long, animated: Boolean) {
        setMaxMinValue(newMaxHeight, newMinHeight, animated, false, false)
    }

    protected fun setMaxMinValue(
        newMaxHeightIn: Long,
        newMinHeightIn: Long,
        animated: Boolean,
        force: Boolean,
        useAnimator: Boolean
    ) {
        var newMaxHeight = newMaxHeightIn
        var newMinHeight = newMinHeightIn
        var heightChanged = true
        if (abs(ChartHorizontalLinesData.lookupHeight(newMaxHeight) - animateToMaxHeight) < thresholdMaxHeight || newMaxHeight == 0L) {
            heightChanged = false
        }
        if (!heightChanged && newMaxHeight.toFloat() == animateToMinHeight) {
            return
        }

        val data = chartData ?: return
        val newData = createHorizontalLinesData(newMaxHeight, newMinHeight, data.yTickFormatter)
        newMaxHeight = newData.values[newData.values.size - 1]
        newMinHeight = newData.values[0]

        if (!useAnimator) {
            var k = (currentMaxHeight - currentMinHeight) / (newMaxHeight - newMinHeight).toFloat()
            if (k > 1f) {
                k = (newMaxHeight - newMinHeight).toFloat() / (currentMaxHeight - currentMinHeight)
            }
            var s = 0.045f
            if (k > 0.7f) {
                s = 0.1f
            } else if (k < 0.1f) {
                s = 0.03f
            }

            var update = newMaxHeight.toFloat() != animateToMaxHeight
            if (useMinHeight && newMinHeight.toFloat() != animateToMinHeight) {
                update = true
            }
            if (update) {
                maxValueAnimator?.removeAllListeners()
                maxValueAnimator?.cancel()
                startFromMaxH = currentMaxHeight
                startFromMinH = currentMinHeight
                startFromMax = 0f
                startFromMin = 0f
                minMaxUpdateStep = s
            }
        }

        animateToMaxHeight = newMaxHeight.toFloat()
        animateToMinHeight = newMinHeight.toFloat()
        measureHeightThreshold()

        val t = System.currentTimeMillis()
        if (t - lastTime < 320 && !force) {
            return
        }
        lastTime = t

        alphaAnimator?.removeAllListeners()
        alphaAnimator?.cancel()

        if (!animated) {
            currentMaxHeight = newMaxHeight.toFloat()
            currentMinHeight = newMinHeight.toFloat()
            horizontalLines.clear()
            horizontalLines.add(newData)
            newData.alpha = 255
            return
        }

        horizontalLines.add(newData)

        if (useAnimator) {
            maxValueAnimator?.removeAllListeners()
            maxValueAnimator?.cancel()
            minMaxUpdateStep = 0f
            val animatorSet = AnimatorSet()
            val animators = mutableListOf<Animator>(
                createAnimator(
                    currentMaxHeight,
                    newMaxHeight.toFloat(),
                    heightUpdateListener
                )
            )
            if (useMinHeight) {
                animators += createAnimator(
                    currentMinHeight,
                    newMinHeight.toFloat(),
                    minHeightUpdateListener
                )
            }
            animatorSet.playTogether(animators)
            maxValueAnimator = animatorSet
            maxValueAnimator?.start()
        }

        for (a in horizontalLines) {
            if (a !== newData) {
                a.fixedAlpha = a.alpha
            }
        }

        alphaAnimator = createAnimator(0f, 255f, ValueAnimator.AnimatorUpdateListener { animation ->
            newData.alpha = (animation.animatedValue as Float).toInt()
            for (a in horizontalLines) {
                if (a !== newData) {
                    a.alpha = ((a.fixedAlpha / 255f) * (255 - newData.alpha)).toInt()
                }
            }
            invalidate()
        }).apply {
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    horizontalLines.clear()
                    horizontalLines.add(newData)
                }
            })
            start()
        }
    }

    protected open fun createHorizontalLinesData(
        newMaxHeight: Long,
        newMinHeight: Long,
        formatter: Int
    ): ChartHorizontalLinesData {
        val data = chartData
            ?: throw IllegalStateException("Chart data must be set before creating horizontal lines")
        return ChartHorizontalLinesData(
            newMaxHeight,
            newMinHeight,
            useMinHeight,
            data.yRate,
            formatter,
            valueFormatter,
            signaturePaint,
            signaturePaint2
        )
    }

    protected open fun formatZeroAxisLabel(): CharSequence {
        return valueFormatter?.formatZeroAxisValue(signaturePaint) ?: "0"
    }

    protected open fun shouldAnimatePickerDuringLineAnimation(): Boolean = true

    protected fun createAnimator(
        f1: Float,
        f2: Float,
        listener: ValueAnimator.AnimatorUpdateListener
    ): ValueAnimator {
        return ValueAnimator.ofFloat(f1, f2).apply {
            duration = ANIM_DURATION
            interpolator = INTERPOLATOR
            addUpdateListener(listener)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        chartData ?: return false
        if (!isEnabled) {
            pickerDelegate.uncapture(event, event.actionIndex)
            parent.requestDisallowInterceptTouchEvent(false)
            chartCaptured = false
            return false
        }

        val pointerIndex = event.actionIndex
        var x = event.getX(pointerIndex).toInt()
        var y = event.getY(pointerIndex).toInt()

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                capturedTime = System.currentTimeMillis()
                parent.requestDisallowInterceptTouchEvent(true)
                if (pickerDelegate.capture(x, y, pointerIndex)) {
                    return true
                }
                capturedX = x
                lastX = x
                capturedY = y
                lastY = y
                if (chartArea.contains(x.toFloat(), y.toFloat())) {
                    if (selectedIndex < 0 || !animateLegentTo) {
                        chartCaptured = true
                        selectXOnChart(x, y)
                    }
                    return true
                }
                return false
            }

            MotionEvent.ACTION_POINTER_DOWN -> return pickerDelegate.capture(x, y, pointerIndex)

            MotionEvent.ACTION_MOVE -> {
                val dx = x - lastX
                val dy = y - lastY

                if (pickerDelegate.captured()) {
                    val result = pickerDelegate.move(x, y, pointerIndex)
                    if (event.pointerCount > 1) {
                        x = event.getX(1).toInt()
                        y = event.getY(1).toInt()
                        pickerDelegate.move(x, y, 1)
                    }
                    parent.requestDisallowInterceptTouchEvent(result)
                    return true
                }

                if (chartCaptured) {
                    val disable =
                        if (canCaptureChartSelection && System.currentTimeMillis() - capturedTime > 200) {
                            true
                        } else {
                            abs(dx) > abs(dy) || abs(dy) < touchSlop
                        }
                    lastX = x
                    lastY = y
                    parent.requestDisallowInterceptTouchEvent(disable)
                    selectXOnChart(x, y)
                } else if (chartArea.contains(capturedX.toFloat(), capturedY.toFloat())) {
                    val dxCaptured = capturedX - x
                    val dyCaptured = capturedY - y
                    if (sqrt((dxCaptured * dxCaptured + dyCaptured * dyCaptured).toDouble()) > touchSlop || System.currentTimeMillis() - capturedTime > 200) {
                        chartCaptured = true
                        selectXOnChart(x, y)
                    }
                }
                return true
            }

            MotionEvent.ACTION_POINTER_UP -> {
                pickerDelegate.uncapture(event, pointerIndex)
                return true
            }

            MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_UP -> {
                if (pickerDelegate.uncapture(event, pointerIndex)) {
                    return true
                }
                if (chartArea.contains(
                        capturedX.toFloat(),
                        capturedY.toFloat()
                    ) && !chartCaptured
                ) {
                    animateLegend(false)
                }
                pickerDelegate.uncapture()
                updateLineSignature()
                parent.requestDisallowInterceptTouchEvent(false)
                chartCaptured = false
                onActionUp()
                invalidate()
                val minValue = if (useMinHeight) findMinValue(startXIndex, endXIndex) else 0L
                setMaxMinValue(findMaxValue(startXIndex, endXIndex), minValue, true, true, false)
                return true
            }
        }

        return super.onTouchEvent(event)
    }

    protected open fun onActionUp() {
    }

    protected open fun selectXOnChart(x: Int, y: Int) {
        val oldSelectedX = selectedIndex
        val data = chartData ?: return
        val offset = chartFullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING
        val xP = (offset + x) / chartFullWidth
        selectedCoordinate = xP
        if (xP < 0) {
            selectedIndex = 0
            selectedCoordinate = 0f
        } else if (xP > 1) {
            selectedIndex = data.x.size - 1
            selectedCoordinate = 1f
        } else {
            selectedIndex = data.findIndex(startXIndex, endXIndex, xP)
            if (selectedIndex + 1 < data.xPercentage.size) {
                val dx = abs(data.xPercentage[selectedIndex] - xP)
                val dx2 = abs(data.xPercentage[selectedIndex + 1] - xP)
                if (dx2 < dx) {
                    selectedIndex++
                }
            }
        }

        if (selectedIndex > endXIndex) {
            selectedIndex = endXIndex
        }
        if (selectedIndex < startXIndex) {
            selectedIndex = startXIndex
        }

        if (oldSelectedX != selectedIndex) {
            legendShowing = true
            animateLegend(true)
            moveLegend(offset)
            notifyDateSelectionChanged()
            runSmoothHaptic()
            invalidate()
        }
    }

    protected open fun runSmoothHaptic() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (vibrationEffect == null) {
                vibrationEffect = VibrationEffect.createWaveform(longArrayOf(0, 2), -1)
            }
            vibrator.cancel()
            vibrator.vibrate(vibrationEffect)
        }
    }

    fun animateLegend(show: Boolean) {
        moveLegend()
        if (animateLegentTo == show) {
            return
        }
        animateLegentTo = show
        selectionAnimator?.removeAllListeners()
        selectionAnimator?.cancel()
        selectionAnimator =
            createAnimator(selectionA, if (show) 1f else 0f, selectionAnimatorListener).apply {
                duration = 200
                addListener(selectorAnimatorEndListener)
                start()
            }
    }

    fun moveLegend(offset: Float) {
        val data = chartData ?: return
        if (selectedIndex < 0 || selectedIndex >= data.x.size || !legendShowing) {
            return
        }
        @Suppress("UNCHECKED_CAST")
        legendSignatureView.setData(
            selectedIndex,
            data.x[selectedIndex],
            lines as ArrayList<LineViewData>,
            false,
            data.yTooltipFormatter,
            data.yRate
        )
        legendSignatureView.visibility = VISIBLE
        legendSignatureView.measure(
            MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.AT_MOST),
            MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.AT_MOST)
        )

        var legendX = data.xPercentage[selectedIndex] * chartFullWidth - offset
        legendX = if (legendX > (chartStart + chartWidth) / 2f) {
            legendX - (legendSignatureView.width + DP_5)
        } else {
            legendX + DP_5
        }
        if (legendX < 0) {
            legendX = 0f
        } else if (legendX + legendSignatureView.measuredWidth > measuredWidth) {
            legendX = (measuredWidth - legendSignatureView.measuredWidth).toFloat()
        }
        legendSignatureView.translationX = legendX
    }

    open fun findMaxValue(startXIndex: Int, endXIndex: Int): Long {
        var maxValue = 0L
        for (line in lines) {
            if (!line.enabled) {
                continue
            }
            val lineMax = line.line.segmentTree?.rMaxQ(startXIndex, endXIndex) ?: continue
            if (lineMax > maxValue) {
                maxValue = lineMax
            }
        }
        return maxValue
    }

    open fun findMinValue(startXIndex: Int, endXIndex: Int): Long {
        var minValue = Long.MAX_VALUE
        for (line in lines) {
            if (!line.enabled) {
                continue
            }
            val lineMin = line.line.segmentTree?.rMinQ(startXIndex, endXIndex) ?: continue
            if (lineMin < minValue) {
                minValue = lineMin
            }
        }
        return minValue
    }

    open fun setData(chartData: T?): Boolean {
        var updated = false
        if (this.chartData !== chartData) {
            updated = true
            invalidate()
            lines.clear()
            chartData?.lines?.forEach { lines.add(createLineViewData(it)) }
            clearSelection()
            this.chartData = chartData
            lastHeaderStartDate = Long.MIN_VALUE
            lastHeaderEndDate = Long.MIN_VALUE
            if (chartData != null) {
                if (chartData.x[0] == 0L) {
                    pickerDelegate.pickerStart = 0f
                    pickerDelegate.pickerEnd = 1f
                } else {
                    pickerDelegate.minDistance = getMinDistance()
                    if (pickerDelegate.pickerEnd - pickerDelegate.pickerStart < pickerDelegate.minDistance) {
                        pickerDelegate.pickerStart =
                            pickerDelegate.pickerEnd - pickerDelegate.minDistance
                        if (pickerDelegate.pickerStart < 0f) {
                            pickerDelegate.pickerStart = 0f
                            pickerDelegate.pickerEnd = 1f
                        }
                    }
                }
            }
        }
        measureSizes()

        if (chartData != null) {
            updateIndexes()
            val minValue = if (useMinHeight) findMinValue(startXIndex, endXIndex) else 0L
            setMaxMinValue(findMaxValue(startXIndex, endXIndex), minValue, false)
            pickerMaxHeight = 0f
            pickerMinHeight = Int.MAX_VALUE.toFloat()
            initPickerMaxHeight()
            if (chartData.yTooltipFormatter == ChartData.FORMATTER_TON || chartData.yTooltipFormatter == ChartData.FORMATTER_XTR) {
                legendSignatureView.setSize(2 * lines.size)
            } else {
                legendSignatureView.setSize(lines.size)
            }
            invalidatePickerChart = true
            updateLineSignature()
        } else {
            pickerDelegate.pickerStart = 0.7f
            pickerDelegate.pickerEnd = 1f
            pickerMaxHeight = 0f
            pickerMinHeight = 0f
            horizontalLines.clear()
            maxValueAnimator?.cancel()
            alphaAnimator?.removeAllListeners()
            alphaAnimator?.cancel()
        }
        return updated
    }

    protected open fun getMinDistance(): Float {
        val data = chartData ?: return 0.1f
        val n = data.x.size
        if (n < 5) {
            return 1f
        }
        val r = 5f / n
        return if (r < 0.1f) 0.1f else r
    }

    protected open fun initPickerMaxHeight() {
        for (line in lines) {
            if (line.enabled && line.line.maxValue > pickerMaxHeight) {
                pickerMaxHeight = line.line.maxValue.toFloat()
            }
            if (line.enabled && line.line.minValue < pickerMinHeight) {
                pickerMinHeight = line.line.minValue.toFloat()
            }
            if (pickerMaxHeight == pickerMinHeight) {
                pickerMaxHeight++
                pickerMinHeight--
            }
        }
    }

    abstract fun createLineViewData(line: ChartData.Line): L

    override fun onPickerDataChanged() {
        onPickerDataChanged(true, false, false)
    }

    open fun onPickerDataChanged(animated: Boolean, force: Boolean, useAniamtor: Boolean) {
        chartData ?: return
        chartFullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)
        updateIndexes()
        val minValue = if (useMinHeight) findMinValue(startXIndex, endXIndex) else 0L
        setMaxMinValue(findMaxValue(startXIndex, endXIndex), minValue, animated, force, useAniamtor)
        if (legendShowing && !force) {
            animateLegend(false)
            moveLegend(chartFullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING)
        }
        invalidate()
    }

    override fun onPickerJumpTo(start: Float, end: Float, force: Boolean) {
        val data = chartData ?: return
        if (force) {
            val startIndex = data.findStartIndex(max(start, 0f))
            val endIndex = data.findEndIndex(startIndex, min(end, 1f))
            setMaxMinValue(
                findMaxValue(startIndex, endIndex),
                findMinValue(startIndex, endIndex),
                true,
                true,
                false
            )
            animateLegend(false)
        } else {
            updateIndexes()
            invalidate()
        }
    }

    protected open fun updateIndexes() {
        val data = chartData ?: return
        startXIndex = data.findStartIndex(max(pickerDelegate.pickerStart, 0f))
        endXIndex = data.findEndIndex(startXIndex, min(pickerDelegate.pickerEnd, 1f))
        if (endXIndex < startXIndex) {
            endXIndex = startXIndex
        }
        val headerStartDate = data.x[startXIndex]
        val headerEndDate = data.x[endXIndex]
        if (headerStartDate != lastHeaderStartDate || headerEndDate != lastHeaderEndDate) {
            lastHeaderStartDate = headerStartDate
            lastHeaderEndDate = headerEndDate
            chartHeaderView?.setDates(headerStartDate, headerEndDate)
        }
        updateLineSignature()
    }

    private fun updateLineSignature() {
        val data = chartData ?: return
        if (chartWidth == 0f) {
            return
        }
        val d = chartFullWidth * data.oneDayPercentage
        val k = chartWidth / d
        val step = (k / BOTTOM_SIGNATURE_COUNT).toInt()
        updateDates(step)
    }

    private fun updateDates(stepIn: Int) {
        var step = stepIn
        val current = currentBottomSignatures
        if (current == null || step >= current.stepMax || step <= current.stepMin) {
            step = Integer.highestOneBit(step) shl 1
            if (current != null && current.step == step) {
                return
            }

            alphaBottomAnimator?.removeAllListeners()
            alphaBottomAnimator?.cancel()

            val stepMax = (step + step * 0.2f).toInt()
            val stepMin = (step - step * 0.2f).toInt()
            val data = ChartBottomSignatureData(step, stepMax, stepMin).apply {
                alpha = 255
            }

            if (currentBottomSignatures == null) {
                currentBottomSignatures = data
                bottomSignatureDate.add(data)
                return
            }

            currentBottomSignatures = data
            for (a in bottomSignatureDate) {
                a.fixedAlpha = a.alpha
            }

            bottomSignatureDate.add(data)
            if (bottomSignatureDate.size > 2) {
                bottomSignatureDate.removeAt(0)
            }

            alphaBottomAnimator =
                createAnimator(0f, 1f, ValueAnimator.AnimatorUpdateListener { animation ->
                    val alpha = animation.animatedValue as Float
                    for (a in bottomSignatureDate) {
                        if (a === data) {
                            data.alpha = (255 * alpha).toInt()
                        } else {
                            a.alpha = ((1f - alpha) * a.fixedAlpha).toInt()
                        }
                    }
                    invalidate()
                }).apply {
                    duration = 200
                    addListener(object : AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: Animator) {
                            bottomSignatureDate.clear()
                            bottomSignatureDate.add(data)
                        }
                    })
                    start()
                }
        }
    }

    open fun onCheckChanged() {
        val data = chartData ?: return
        onPickerDataChanged(true, true, true)
        val startAlpha = FloatArray(lines.size)
        val endAlpha = FloatArray(lines.size)
        var hasAlphaAnimation = false

        for (i in lines.indices) {
            val lineViewData = lines[i]
            lineViewData.animatorIn?.cancel()
            lineViewData.animatorOut?.cancel()
            lineViewData.animatorIn = null
            lineViewData.animatorOut = null

            startAlpha[i] = lineViewData.alpha
            endAlpha[i] = if (lineViewData.enabled) 1f else 0f
            if (kotlin.math.abs(startAlpha[i] - endAlpha[i]) > 0.001f) {
                hasAlphaAnimation = true
            }
        }

        if (hasAlphaAnimation) {
            invalidatePickerChart = true
            val sharedAnimator = createAnimator(
                0f,
                1f,
                ValueAnimator.AnimatorUpdateListener { animation ->
                    val progress = animation.animatedValue as Float
                    for (i in lines.indices) {
                        lines[i].alpha = startAlpha[i] + (endAlpha[i] - startAlpha[i]) * progress
                    }
                    invalidate()
                }
            ).apply {
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        for (i in lines.indices) {
                            lines[i].alpha = endAlpha[i]
                            lines[i].animatorIn = null
                            lines[i].animatorOut = null
                        }
                        invalidatePickerChart = true
                        invalidate()
                    }
                })
                start()
            }

            for (i in lines.indices) {
                val lineViewData = lines[i]
                if (endAlpha[i] > startAlpha[i]) {
                    lineViewData.animatorIn = sharedAnimator
                } else if (endAlpha[i] < startAlpha[i]) {
                    lineViewData.animatorOut = sharedAnimator
                }
            }
        }

        updatePickerMinMaxHeight()
        if (legendShowing) {
            @Suppress("UNCHECKED_CAST")
            legendSignatureView.setData(
                selectedIndex,
                data.x[selectedIndex],
                lines as ArrayList<LineViewData>,
                false,
                data.yTooltipFormatter,
                data.yRate
            )
        }
    }

    protected open fun updatePickerMinMaxHeight() {
        if (!ANIMATE_PICKER_SIZES) {
            return
        }
        var maxValue = 0L
        var minValue = Long.MAX_VALUE
        for (line in lines) {
            if (line.enabled && line.line.maxValue > maxValue) {
                maxValue = line.line.maxValue
            }
            if (line.enabled && line.line.minValue < minValue) {
                minValue = line.line.minValue
            }
        }
        if ((minValue != Int.MAX_VALUE.toLong() && minValue.toFloat() != animatedToPickerMinHeight) || (maxValue > 0 && maxValue.toFloat() != animatedToPickerMaxHeight)) {
            animatedToPickerMaxHeight = maxValue.toFloat()
            animatedToPickerMinHeight = minValue.toFloat()
            pickerAnimator?.cancel()
            val animatorSet = AnimatorSet()
            animatorSet.playTogether(
                createAnimator(
                    pickerMaxHeight,
                    animatedToPickerMaxHeight,
                    pickerHeightUpdateListener
                ),
                createAnimator(
                    pickerMinHeight,
                    animatedToPickerMinHeight,
                    pickerMinHeightUpdateListener
                )
            )
            pickerAnimator = animatorSet
            pickerAnimator?.start()
        }
    }

    fun saveState(outState: Bundle?) {
        if (outState == null) {
            return
        }
        outState.putFloat("chart_start", pickerDelegate.pickerStart)
        outState.putFloat("chart_end", pickerDelegate.pickerEnd)
        if (lines.isNotEmpty()) {
            val array = BooleanArray(lines.size)
            for (i in lines.indices) {
                array[i] = lines[i].enabled
            }
            outState.putBooleanArray("chart_line_enabled", array)
        }
    }

    fun setHeader(chartHeaderView: ChartHeaderView?) {
        this.chartHeaderView = chartHeaderView
    }

    fun getSelectedDate(): Long {
        val data = chartData ?: return -1
        if (selectedIndex < 0) {
            return -1
        }
        return data.x[selectedIndex]
    }

    fun getPickerStartIndex(): Int = startXIndex

    fun getPickerEndIndex(): Int = endXIndex

    fun getPickerCenterIndex(): Int {
        val data = chartData ?: return -1
        return ((startXIndex + endXIndex) / 2).coerceIn(0, data.x.lastIndex)
    }

    fun getPickerCenterDate(): Long {
        val data = chartData ?: return -1
        val centerIndex = getPickerCenterIndex()
        return if (centerIndex < 0) -1 else data.x[centerIndex]
    }

    fun getPickerWindowSpan(): Int = (endXIndex - startXIndex).coerceAtLeast(0)

    fun setPickerByIndices(startIndex: Int, endIndex: Int, animated: Boolean = false) {
        val data = chartData ?: return
        if (data.xPercentage.isEmpty()) return

        val maxIndex = data.xPercentage.lastIndex
        if (maxIndex < 0) return
        if (maxIndex == 0) {
            pickerDelegate.pickerStart = 0f
            pickerDelegate.pickerEnd = 1f
            onPickerDataChanged(animated, true, false)
            invalidate()
            return
        }

        var safeStart = startIndex.coerceIn(0, maxIndex)
        var safeEnd = endIndex.coerceIn(0, maxIndex)
        if (safeEnd < safeStart) {
            val tmp = safeStart
            safeStart = safeEnd
            safeEnd = tmp
        }
        if (safeStart == safeEnd && maxIndex > 0) {
            if (safeEnd < maxIndex) {
                safeEnd += 1
            } else {
                safeStart -= 1
            }
        }

        pickerDelegate.pickerStart = data.xPercentage[safeStart]
        pickerDelegate.pickerEnd = data.xPercentage[safeEnd]
        onPickerDataChanged(animated, true, false)
        invalidate()
    }

    fun clearSelection() {
        selectedIndex = -1
        legendShowing = false
        animateLegentTo = false
        legendSignatureView.visibility = GONE
        selectionA = 0f
    }

    fun selectDate(activeZoom: Long) {
        val data = chartData ?: return
        selectedIndex = Arrays.binarySearch(data.x, activeZoom)
        legendShowing = true
        legendSignatureView.visibility = VISIBLE
        selectionA = 1f
        moveLegend(chartFullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING)
        try {
            performHapticFeedback(
                HapticFeedbackConstants.KEYBOARD_TAP,
                HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
            )
        } catch (_: Exception) {
        }
    }

    fun getStartDate(): Long = chartData?.x?.get(startXIndex) ?: -1

    fun getEndDate(): Long = chartData?.x?.get(endXIndex) ?: -1

    open fun updatePicker(chartData: ChartData, d: Long) {
        val n = chartData.x.size
        val startOfDay = d - d % 86400000L
        val endOfDay = startOfDay + 86400000L - 1
        var startIndex = 0
        var endIndex = 0
        for (i in 0 until n) {
            if (startOfDay > chartData.x[i]) {
                startIndex = i
            }
            if (endOfDay > chartData.x[i]) {
                endIndex = i
            }
        }
        pickerDelegate.pickerStart = chartData.xPercentage[startIndex]
        pickerDelegate.pickerEnd = chartData.xPercentage[endIndex]
    }

    fun moveLegend() {
        moveLegend(chartFullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING)
    }

    protected fun notifyDateSelectionChanged() {
        selectionListener?.onDateSelected(getSelectedDate())
    }

    fun setDateSelectionListener(dateSelectionListener: DateSelectionListener?) {
        this.selectionListener = dateSelectionListener
    }

    open fun fillTransitionParams(params: TransitionParams) {
    }

    private fun getChartTransitionAlpha(): Float {
        val params = transitionParams
        return when (transitionMode) {
            TRANSITION_MODE_PARENT -> 1f - (params?.progress ?: 0f)
            TRANSITION_MODE_CHILD, TRANSITION_MODE_ALPHA_ENTER -> params?.progress ?: 1f
            else -> 1f
        }
    }

    interface DateSelectionListener {
        fun onDateSelected(date: Long)
    }

    class SharedUiComponents(
        var style: ChartStyle = ChartStyle.default(),
    ) {
        private var pickerRoundBitmap: Bitmap? = null
        private var canvas: Canvas? = null
        private val rectF = RectF()
        private val xRefP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0
            xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
        }

        private var k = 0
        private var invalidate = true

        fun getPickerMaskBitmap(h: Int, w: Int): Bitmap {
            if (((h + w) shl 10) != k || invalidate) {
                invalidate = false
                k = (h + w) shl 10
                pickerRoundBitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                canvas = Canvas(pickerRoundBitmap!!)
                rectF.set(0f, 0f, w.toFloat(), h.toFloat())
                canvas?.drawColor(style.backgroundColor)
                canvas?.drawRoundRect(
                    rectF,
                    6.dp.toFloat(),
                    6.dp.toFloat(),
                    xRefP
                )
            }
            return pickerRoundBitmap!!
        }

        fun invalidate() {
            invalidate = true
        }
    }

    private fun updatePickerFrameResources() {
        if (!style.useTokenChartPickerResources) {
            rangePickerLeftDrawable = null
            rangePickerRightDrawable = null
            return
        }

        rangePickerLeftDrawable = context.getDrawableCompat(
            if (style.isDark) R.drawable.ic_chart_thumb_dark else R.drawable.ic_chart_thumb
        )?.mutate()
        rangePickerRightDrawable = context.getDrawableCompat(
            if (style.isDark) R.drawable.ic_chart_thumb_right_dark else R.drawable.ic_chart_thumb_right
        )?.mutate()
    }

    companion object {
        val HORIZONTAL_PADDING: Float = 16f.dp
        private val LINE_WIDTH = 1f.dp
        private val SELECTED_LINE_WIDTH = 1.5f.dp
        val SIGNATURE_TEXT_SIZE: Float = 12f.dp
        val SIGNATURE_TEXT_HEIGHT: Int = 18.dp
        private val BOTTOM_SIGNATURE_TEXT_HEIGHT = 14.dp
        val BOTTOM_SIGNATURE_START_ALPHA: Int = 10.dp
        protected val PICKER_PADDING = 16.dp
        private val PICKER_CAPTURE_WIDTH = 24.dp
        private val LANDSCAPE_END_PADDING = 16.dp
        private val BOTTOM_SIGNATURE_OFFSET = 10.dp
        private val DP_12 = 12.dp
        private val DP_8 = 8.dp
        private val DP_6 = 6.dp
        private val DP_5 = 5.dp
        private val DP_2 = 2.dp
        private val DP_1 = 1.dp
        private val PICKER_FRAME_HANDLE_WIDTH = 10.dp

        val USE_LINES: Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.P

        protected val ANIMATE_PICKER_SIZES: Boolean =
            Build.VERSION.SDK_INT > Build.VERSION_CODES.LOLLIPOP

        var INTERPOLATOR = AccelerateDecelerateInterpolator()

        const val TRANSITION_MODE_CHILD = 1
        const val TRANSITION_MODE_PARENT = 2
        const val TRANSITION_MODE_ALPHA_ENTER = 3
        const val TRANSITION_MODE_NONE = 0
        private const val BOTTOM_SIGNATURE_COUNT = 6

        fun RoundedRect(
            path: Path,
            left: Float,
            top: Float,
            right: Float,
            bottom: Float,
            rx: Float,
            ry: Float,
            tl: Boolean,
            tr: Boolean,
            br: Boolean,
            bl: Boolean
        ): Path {
            var localRx = rx
            var localRy = ry
            path.reset()
            if (localRx < 0) {
                localRx = 0f
            }
            if (localRy < 0) {
                localRy = 0f
            }
            val width = right - left
            val height = bottom - top
            if (localRx > width / 2) {
                localRx = width / 2
            }
            if (localRy > height / 2) {
                localRy = height / 2
            }
            val widthMinusCorners = width - 2 * localRx
            val heightMinusCorners = height - 2 * localRy

            path.moveTo(right, top + localRy)
            if (tr) {
                path.rQuadTo(0f, -localRy, -localRx, -localRy)
            } else {
                path.rLineTo(0f, -localRy)
                path.rLineTo(-localRx, 0f)
            }
            path.rLineTo(-widthMinusCorners, 0f)
            if (tl) {
                path.rQuadTo(-localRx, 0f, -localRx, localRy)
            } else {
                path.rLineTo(-localRx, 0f)
                path.rLineTo(0f, localRy)
            }
            path.rLineTo(0f, heightMinusCorners)
            if (bl) {
                path.rQuadTo(0f, localRy, localRx, localRy)
            } else {
                path.rLineTo(0f, localRy)
                path.rLineTo(localRx, 0f)
            }
            path.rLineTo(widthMinusCorners, 0f)
            if (br) {
                path.rQuadTo(localRx, 0f, localRx, -localRy)
            } else {
                path.rLineTo(localRx, 0f)
                path.rLineTo(0f, -localRy)
            }
            path.rLineTo(0f, -heightMinusCorners)
            path.close()
            return path
        }
    }
}
