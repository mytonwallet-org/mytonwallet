package org.mytonwallet.app_air.uicomponents.widgets.chart

import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import com.github.mikephil.charting.charts.LineChart
import com.github.mikephil.charting.components.XAxis
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.formatter.ValueFormatter
import com.github.mikephil.charting.highlight.Highlight
import com.github.mikephil.charting.interfaces.datasets.ILineDataSet
import com.github.mikephil.charting.listener.ChartTouchListener.ChartGesture
import com.github.mikephil.charting.listener.OnChartGestureListener
import com.github.mikephil.charting.listener.OnChartValueSelectedListener
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@SuppressLint("ViewConstructor")
class WLineChartView(context: Context, labeled: Boolean) : LineChart(context), WThemedView,
    OnChartValueSelectedListener {

    override fun isPinchZoomEnabled(): Boolean {
        return false
    }

    var dateFormat = SimpleDateFormat("MMM dd", Locale(WGlobalStorage.getLangCode()))

    var onHighlightChange: ((h: Highlight?) -> Unit)? = null

    init {
        id = generateViewId()

        description.isEnabled = false

        setTouchEnabled(true)
        setOnChartValueSelectedListener(this)
        setDrawGridBackground(false)
        if (labeled) {
            xAxis.setLabelCount(5)
            xAxis.position = XAxis.XAxisPosition.BOTTOM
            setViewPortOffsets(0f, 0f, 20f.dp, 16f.dp)
            xAxis.valueFormatter = object : ValueFormatter() {
                override fun getFormattedValue(value: Float): String {
                    val date = Date(value.toLong() * 1000)
                    return dateFormat.format(date)
                }
            }
            xAxis.textColor = WColor.SecondaryText.color
            xAxis.setDrawAxisLine(false)
            xAxis.setDrawGridLines(false)
        } else {
            setViewPortOffsets(0f, 0f, 0f, 0f)
            xAxis.isEnabled = false
        }
        axisLeft.isEnabled = false
        axisLeft.spaceTop = 1f.dp
        axisLeft.spaceBottom = 0f
        axisRight.isEnabled = false
        legend.isEnabled = false
        isDoubleTapToZoomEnabled = false

        onChartGestureListener = object : OnChartGestureListener {
            override fun onChartGestureStart(
                me: MotionEvent,
                lastPerformedGesture: ChartGesture
            ) {
                lineData.dataSets[0].isHighlightEnabled = false
                parent.requestDisallowInterceptTouchEvent(true)
                setDrawMarkers(true)
                for (i in 0 until lineData.getDataSetCount()) {
                    val set: ILineDataSet = lineData.getDataSetByIndex(i)
                    set.isHighlightEnabled = true
                }
                highlightValue(getHighlightByTouchPoint(me.x, me.y))
            }

            override fun onChartGestureEnd(
                me: MotionEvent,
                lastPerformedGesture: ChartGesture
            ) {
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
                me1: MotionEvent, me2: MotionEvent, velocityX: Float,
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

    override fun updateTheme() {
        (renderer as WLineChartViewRenderer).grayColor = WColor.GroupedBackground.color
        invalidate()
    }

    override fun onValueSelected(e: Entry?, h: Highlight?) {
    }

    override fun onNothingSelected() {
    }

}
