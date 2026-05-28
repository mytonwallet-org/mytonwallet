package org.mytonwallet.app_air.uicomponents.widgets.chart

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.data.LineData
import com.github.mikephil.charting.data.LineDataSet
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import java.util.Collections
import kotlin.math.max
import kotlin.math.min

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class WChartTimeLineView(
    context: Context,
    val startPercentageChanged: (value: Float) -> Unit,
    val endPercentageChanged: (value: Float) -> Unit,
) : FrameLayout(context), WThemedView {

    private val chartView = WLineChartView(context, false).apply {
        setTouchEnabled(false)
    }
    private val leftOverlay = View(context)
    private val rightOverlay = View(context)
    private val thumbCenterDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(Color.TRANSPARENT)
    }
    private val thumbTouchView = View(context).apply {
        background = thumbCenterDrawable
    }
    private val imgLeft = AppCompatImageView(context).apply {
        setPadding(20.dp, 0, 0, 0)
    }
    private val imgRight = AppCompatImageView(context).apply {
        setPadding(20.dp, 0, 0, 0)
        rotation = 180f
    }

    private var startPercentage = 0f
    private var endPercentage = 1f

    private var isDraggingLeft = false
    private var isDraggingRight = false
    private var isDraggingThumb = false

    private var initialX = 0f
    private var initialPosition = 0f
    private var initialStartPercent = 0f
    private var initialEndPercent = 0f

    init {
        id = generateViewId()
        layoutDirection = LAYOUT_DIRECTION_LTR

        addView(chartView, LayoutParams(MATCH_PARENT, MATCH_PARENT).apply {
            leftMargin = 21.dp
            rightMargin = 21.dp
            topMargin = 2.dp
            bottomMargin = 2.dp
        })
        addView(leftOverlay, LayoutParams(0.dp, MATCH_PARENT).apply {
            leftMargin = 20.dp
            gravity = Gravity.LEFT
        })
        addView(rightOverlay, LayoutParams(0.dp, MATCH_PARENT).apply {
            rightMargin = 20.dp
            gravity = Gravity.RIGHT
        })
        addView(thumbTouchView, LayoutParams(0.dp, MATCH_PARENT))
        addView(imgLeft, LayoutParams(30.dp, MATCH_PARENT))
        addView(imgRight, LayoutParams(30.dp, MATCH_PARENT).apply {
            gravity = Gravity.RIGHT
        })

        imgLeft.setOnTouchListener { _, event ->
            parent.requestDisallowInterceptTouchEvent(true)

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    isDraggingLeft = true
                    initialX = event.rawX
                    initialPosition = imgLeft.x
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    if (isDraggingLeft) {
                        val deltaX = event.rawX - initialX
                        val newX = initialPosition + deltaX
                        var newStartPercentage = newX / (width - 40.dp)
                        if (newStartPercentage < 0f)
                            newStartPercentage = 0f
                        if (isRangeAcceptable(newStartPercentage, endPercentage)) {
                            startPercentage = newStartPercentage
                            imgLeft.x =
                                min((width - 40.dp) * newStartPercentage, imgRight.x - 30.dp)
                            updateOverlays()
                            startPercentage = newStartPercentage
                            startPercentageChanged(startPercentage)
                        }
                    }
                    true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    isDraggingLeft = false
                    true
                }

                else -> false
            }
        }

        imgRight.setOnTouchListener { _, event ->
            parent.requestDisallowInterceptTouchEvent(true)

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    isDraggingRight = true
                    initialX = event.rawX
                    initialPosition = imgRight.x
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    if (isDraggingRight) {
                        val deltaX = event.rawX - initialX
                        val newX = initialPosition + deltaX
                        var newEndPercentage = (newX - 10.dp) / (width - 40.dp)
                        if (newEndPercentage > 1f)
                            newEndPercentage = 1f
                        if (isRangeAcceptable(startPercentage, newEndPercentage)) {
                            imgRight.x = max(
                                imgLeft.x + 30.dp,
                                (width - 40.dp) * newEndPercentage + 10.dp
                            )
                            updateOverlays()
                            endPercentage = newEndPercentage
                            endPercentageChanged(newEndPercentage)
                        }
                    }
                    true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    isDraggingRight = false
                    true
                }

                else -> false
            }
        }

        thumbTouchView.setOnTouchListener { _, event ->
            parent.requestDisallowInterceptTouchEvent(true)

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    isDraggingThumb = true
                    initialX = event.rawX
                    initialStartPercent = startPercentage
                    initialEndPercent = endPercentage
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    if (isDraggingThumb) {
                        val deltaX = event.rawX - initialX
                        val deltaPercentage = deltaX / (width - 40.dp)
                        var newStartPercentage = initialStartPercent + deltaPercentage
                        var newEndPercentage = initialEndPercent + deltaPercentage
                        if (newStartPercentage < 0) {
                            newEndPercentage = endPercentage - startPercentage
                            newStartPercentage = 0f
                        } else if (newEndPercentage > 1) {
                            newStartPercentage = 1 - (endPercentage - startPercentage)
                            newEndPercentage = 1f
                        }
                        if (isRangeAcceptable(newStartPercentage, newEndPercentage)) {
                            imgLeft.x = (width - 40.dp) * newStartPercentage
                            imgRight.x =
                                max(
                                    imgLeft.x + 30.dp,
                                    20.dp + (width - 40.dp) * newEndPercentage - 10.dp
                                )
                            updateOverlays()
                            startPercentage = newStartPercentage
                            endPercentage = newEndPercentage
                            startPercentageChanged(newStartPercentage)
                            endPercentageChanged(newEndPercentage)
                        }
                    }
                    true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    isDraggingThumb = false
                    true
                }

                else -> false
            }
        }

        post {
            thumbTouchView.x = 28f.dp
            thumbTouchView.layoutParams = thumbTouchView.layoutParams.apply {
                width = this@WChartTimeLineView.width - 56.dp
            }
        }
        updateTheme()
    }

    private fun updateOverlays() {
        leftOverlay.layoutParams.width = max(8.dp, imgLeft.x.toInt() + 10.dp)
        rightOverlay.layoutParams.width = max(8.dp, (width - imgRight.x - 20.dp).toInt())
        thumbTouchView.x = imgLeft.x + 28.dp
        thumbTouchView.layoutParams = thumbTouchView.layoutParams.apply {
            width = (imgRight.x - imgLeft.x - 26.dp).toInt()
        }
        setFilledDataset()
    }

    override val isTinted = true
    override fun updateTheme() {
        chartView.setBackgroundColor(Color.TRANSPARENT, 8f.dp, true)
        val overlayAlpha = if (ThemeManager.isDark) 50 else 10
        leftOverlay.setBackgroundColor(
            Color.BLACK.colorWithAlpha(overlayAlpha),
            topLeft = 8f.dp, 0f, 0f, bottomLeft = 8f.dp
        )
        rightOverlay.setBackgroundColor(
            Color.BLACK.colorWithAlpha(overlayAlpha),
            0f, 12f.dp, 12f.dp, 0f
        )
        thumbCenterDrawable.setStroke(1.dp, WColor.Thumb.color)
        val thumbDrawable = ContextCompat.getDrawable(
            context,
            if (ThemeManager.isDark)
                org.mytonwallet.app_air.uicomponents.R.drawable.ic_chart_thumb_dark
            else
                org.mytonwallet.app_air.uicomponents.R.drawable.ic_chart_thumb
        )
        imgLeft.setImageDrawable(thumbDrawable)
        imgRight.setImageDrawable(thumbDrawable)
    }

    private var historyData: Array<Array<Double>>? = null
    fun configure(historyData: Array<Array<Double>>?) {
        this.historyData = historyData
        val entries = mutableListOf<Entry>()

        historyData?.forEach { pair ->
            val timestamp = pair[0].toFloat()
            val value = pair[1].toFloat()
            entries.add(Entry(timestamp, value))
        }

        val dataSet = LineDataSet(entries, "")
        dataSet.lineWidth = 1.0f
        dataSet.color = WColor.Tint.color
        dataSet.setDrawCircles(false)
        dataSet.setDrawValues(false)
        dataSet.setDrawHorizontalHighlightIndicator(false)
        dataSet.setDrawVerticalHighlightIndicator(false)
        dataSet.mode = LineDataSet.Mode.CUBIC_BEZIER
        val lineData = LineData(dataSet)
        chartView.data = lineData
        chartView.invalidate()
        setFilledDataset()
    }

    fun periodChanged() {
        imgLeft.x = 0f.dp
        imgRight.x = 10f.dp + (width - 40.dp)
        updateOverlays()
        startPercentage = 0f
        endPercentage = 1f
    }

    private fun setFilledDataset() {
        val dataSize = historyData?.size ?: return
        if (dataSize < 2)
            return
        val startIndex = (startPercentage * dataSize).toInt().coerceIn(0, dataSize - 1)
        val endIndex = (endPercentage * dataSize).toInt().coerceIn(0, dataSize - 1)
        val filledEntries = mutableListOf<Entry>()
        historyData?.forEachIndexed { index, pair ->
            if (index in startIndex..endIndex) {
                val timestamp = pair[0].toFloat()
                val value = pair[1].toFloat()
                filledEntries.add(Entry(timestamp, value))
            }
        }
        val dataSet = LineDataSet(filledEntries, "")
        dataSet.lineWidth = 1.0f
        dataSet.color = WColor.Tint.color
        dataSet.setDrawCircles(false)
        dataSet.setDrawValues(false)
        dataSet.setDrawHorizontalHighlightIndicator(false)
        dataSet.setDrawVerticalHighlightIndicator(false)
        dataSet.setDrawFilled(true)
        val gradient = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(WColor.Tint.color.colorWithAlpha(51), Color.TRANSPARENT)
        )
        gradient.setGradientType(GradientDrawable.LINEAR_GRADIENT)
        dataSet.fillDrawable = gradient
        dataSet.mode = LineDataSet.Mode.CUBIC_BEZIER
        val lineData = LineData(chartView.lineData.dataSets.first(), dataSet)
        chartView.data = lineData
        chartView.invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, 36.dp.exactly)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            setSystemGestureExclusionRects(Collections.singletonList(Rect(0, 0, width, height)))
    }

    private fun isRangeAcceptable(startPercentage: Float, endPercentage: Float): Boolean {
        val data = historyData ?: return false
        if (data.isEmpty()) return false
        if (startPercentage < 0 || endPercentage < 0 ||
            startPercentage > 1 || endPercentage > 1
        )
            return false

        val dataSize = data.size
        val startIndex = (startPercentage * dataSize).toInt().coerceIn(0, dataSize - 1)
        val endIndex = (endPercentage * dataSize).toInt().coerceIn(0, dataSize - 1)

        return (endIndex - startIndex) > 5
    }
}
