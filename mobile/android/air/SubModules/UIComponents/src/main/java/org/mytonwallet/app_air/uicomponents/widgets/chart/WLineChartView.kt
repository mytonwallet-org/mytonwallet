package org.mytonwallet.app_air.uicomponents.widgets.chart

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Rect
import android.view.MotionEvent
import com.github.mikephil.charting.charts.LineChart
import com.github.mikephil.charting.components.XAxis
import com.github.mikephil.charting.components.YAxis
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.formatter.ValueFormatter
import com.github.mikephil.charting.highlight.Highlight
import com.github.mikephil.charting.interfaces.datasets.ILineDataSet
import com.github.mikephil.charting.listener.ChartTouchListener.ChartGesture
import com.github.mikephil.charting.listener.OnChartGestureListener
import com.github.mikephil.charting.listener.OnChartValueSelectedListener
import com.github.mikephil.charting.renderer.XAxisRenderer
import com.github.mikephil.charting.utils.MPPointF
import java.util.Date
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.WDateFormatter
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class WLineChartView(context: Context, labeled: Boolean) :
    LineChart(context),
    WThemedView,
    OnChartValueSelectedListener {

    override fun isPinchZoomEnabled(): Boolean = false

    var dateFormat = WGlobalStorage.getLangCode().let { langCode ->
        val pattern = if (WDateFormatter.isDayBeforeMonth(langCode)) "dd MMM" else "MMM dd"
        WDateFormatter.of(pattern, langCode)
    }

    var onHighlightChange: ((h: Highlight?) -> Unit)? = null

    private val viewPortOffsetRight = if (labeled) 20f.dp else 0f
    private val viewPortOffsetBottom = if (labeled) 16f.dp else 0f

    init {
        id = generateViewId()

        description.isEnabled = false

        setTouchEnabled(true)
        setOnChartValueSelectedListener(this)
        setDrawGridBackground(false)
        if (labeled) {
            xAxis.setLabelCount(5)
            xAxis.position = XAxis.XAxisPosition.BOTTOM
            xAxis.valueFormatter = object : ValueFormatter() {
                override fun getFormattedValue(value: Float): String {
                    val date = Date(value.toLong() * 1000)
                    return dateFormat.format(date)
                }
            }
            xAxis.textColor = WColor.SecondaryText.color
            xAxis.typeface = WFont.Regular.typeface
            xAxis.setDrawAxisLine(false)
            xAxis.setDrawGridLines(false)
            setXAxisRenderer(object : XAxisRenderer(
                viewPortHandler,
                xAxis,
                getTransformer(YAxis.AxisDependency.LEFT)
            ) {
                private val labelBounds = Rect()
                private val fadeDistance = 12f.dp

                override fun drawLabel(
                    c: Canvas,
                    formattedLabel: String,
                    x: Float,
                    y: Float,
                    anchor: MPPointF,
                    angleDegrees: Float
                ) {
                    mAxisLabelPaint.getTextBounds(
                        formattedLabel,
                        0,
                        formattedLabel.length,
                        labelBounds
                    )
                    val labelWidth = labelBounds.width()
                    val left = x - labelWidth * anchor.x
                    val edgeDistance = minOf(left, width - left - labelWidth)
                    if (edgeDistance <= 0f) return
                    val originalAlpha = mAxisLabelPaint.alpha
                    mAxisLabelPaint.alpha =
                        (originalAlpha * (edgeDistance / fadeDistance).coerceIn(0f, 1f)).toInt()
                    super.drawLabel(c, formattedLabel, x, y, anchor, angleDegrees)
                    mAxisLabelPaint.alpha = originalAlpha
                }
            })
        } else {
            xAxis.isEnabled = false
        }
        setViewPortOffsets(0f, 0f, viewPortOffsetRight, viewPortOffsetBottom)
        axisLeft.isEnabled = false
        axisLeft.spaceTop = 1f.dp
        axisLeft.spaceBottom = 0f
        axisRight.isEnabled = false
        legend.isEnabled = false
        isDoubleTapToZoomEnabled = false

        onChartGestureListener = object : OnChartGestureListener {
            override fun onChartGestureStart(me: MotionEvent, lastPerformedGesture: ChartGesture) {
                lineData.dataSets[0].isHighlightEnabled = false
                parent.requestDisallowInterceptTouchEvent(true)
                setDrawMarkers(true)
                for (i in 0 until lineData.getDataSetCount()) {
                    val set: ILineDataSet = lineData.getDataSetByIndex(i)
                    set.isHighlightEnabled = true
                }
                highlightValue(getHighlightByTouchPoint(me.x, me.y))
            }

            override fun onChartGestureEnd(me: MotionEvent, lastPerformedGesture: ChartGesture) {
                setDrawMarkers(false)
                for (i in 0 until lineData.getDataSetCount()) {
                    val set: ILineDataSet = lineData.getDataSetByIndex(i)
                    set.isHighlightEnabled = false
                }
                highlightValue(null)
                onHighlightChange?.invoke(null)
                invalidate()
            }

            override fun onChartLongPressed(me: MotionEvent) {
            }

            override fun onChartDoubleTapped(me: MotionEvent) {
            }

            override fun onChartSingleTapped(me: MotionEvent) {
            }

            override fun onChartFling(
                me1: MotionEvent,
                me2: MotionEvent,
                velocityX: Float,
                velocityY: Float
            ) {
            }

            override fun onChartScale(me: MotionEvent, scaleX: Float, scaleY: Float) {
            }

            override fun onChartTranslate(me: MotionEvent, dX: Float, dY: Float) {
            }
        }

        val customRenderer =
            WLineChartViewRenderer(
                this,
                animator,
                viewPortHandler
            )
        renderer = customRenderer
        setOnChartValueSelectedListener(object : OnChartValueSelectedListener {
            override fun onValueSelected(e: Entry, h: Highlight) {
                Haptics.play(this@WLineChartView, HapticType.SELECTION)
                invalidate()
                onHighlightChange?.invoke(h)
            }

            override fun onNothingSelected() {
                invalidate()
            }
        })

        val marker = WDashedLineMarker(context)
        marker.chartView = this
        setMarker(marker)

        updateTheme()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        mViewPortHandler.restrainViewPort(0f, 0f, viewPortOffsetRight, viewPortOffsetBottom)
        prepareOffsetMatrix()
        prepareValuePxMatrix()
    }

    override fun updateTheme() {
        (renderer as WLineChartViewRenderer).grayColor = WColor.GroupedBackground.color
        invalidate()
    }

    override fun onValueSelected(e: Entry?, h: Highlight?) {
    }

    override fun onNothingSelected() {
    }
}
