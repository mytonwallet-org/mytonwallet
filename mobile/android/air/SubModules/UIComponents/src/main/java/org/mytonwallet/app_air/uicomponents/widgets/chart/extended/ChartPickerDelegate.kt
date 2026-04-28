package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.ValueAnimator
import android.graphics.Rect
import android.view.MotionEvent
import org.mytonwallet.app_air.uicomponents.extensions.dp
import kotlin.math.sqrt

class ChartPickerDelegate(private val view: Listener) {
    var disabled: Boolean = false
    var pickerWidth: Float = 0f
    var tryMoveTo: Boolean = false
    var moveToX: Float = 0f
    var moveToY: Float = 0f
    var startTapTime: Long = 0L
    var moveToAnimator: ValueAnimator? = null
    val leftPickerArea = Rect()
    val rightPickerArea = Rect()
    val middlePickerArea = Rect()
    var pickerStart: Float = 0.7f
    var pickerEnd: Float = 1f
    var minDistance: Float = 0.1f
    var pickerMode: PickerMode = PickerMode.RANGE

    private val capturedStates = arrayOfNulls<CapturesData>(2)

    fun getMiddleCaptured(): CapturesData? = capturedStates.firstOrNull { it?.state == CAPTURE_MIDDLE }
    fun getLeftCaptured(): CapturesData? = capturedStates.firstOrNull { it?.state == CAPTURE_LEFT }
    fun getRightCaptured(): CapturesData? = capturedStates.firstOrNull { it?.state == CAPTURE_RIGHT }

    inner class CapturesData(val state: Int) {
        var capturedX: Int = 0
        var lastMovingX: Int = 0
        var start: Float = 0f
        var end: Float = 0f
        var a: ValueAnimator? = null
        var jumpToAnimator: ValueAnimator? = null
        var aValue: Float = 0f

        fun captured() {
            a = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 600L
                interpolator = BaseChartView.INTERPOLATOR
                addUpdateListener {
                    aValue = it.animatedValue as Float
                    view.invalidate()
                }
                start()
            }
        }

        fun uncapture() {
            a?.cancel()
            jumpToAnimator?.cancel()
        }
    }

    fun capture(x: Int, y: Int, pointerIndex: Int): Boolean {
        if (disabled) return false
        if (pointerIndex == 0) {
            if (pickerMode == PickerMode.SINGLE) {
                when {
                    middlePickerArea.contains(x, y) -> {
                        capturedStates[0] = CapturesData(CAPTURE_MIDDLE).apply {
                            start = pickerStart
                            end = pickerEnd
                            capturedX = x
                            lastMovingX = x
                            captured()
                        }
                        moveToAnimator?.cancel()
                        return true
                    }
                    y < middlePickerArea.bottom && y > middlePickerArea.top -> {
                        tryMoveTo = true
                        moveToX = x.toFloat()
                        moveToY = y.toFloat()
                        startTapTime = System.currentTimeMillis()
                        moveToAnimator?.let {
                            if (it.isRunning) {
                                view.onPickerJumpTo(pickerStart, pickerEnd, true)
                            }
                            it.cancel()
                        }
                        return true
                    }
                }
            } else when {
                leftPickerArea.contains(x, y) -> {
                    if (capturedStates[0] != null) capturedStates[1] = capturedStates[0]
                    capturedStates[0] = CapturesData(CAPTURE_LEFT).apply {
                        start = pickerStart
                        capturedX = x
                        lastMovingX = x
                        captured()
                    }
                    moveToAnimator?.cancel()
                    return true
                }
                rightPickerArea.contains(x, y) -> {
                    if (capturedStates[0] != null) capturedStates[1] = capturedStates[0]
                    capturedStates[0] = CapturesData(CAPTURE_RIGHT).apply {
                        end = pickerEnd
                        capturedX = x
                        lastMovingX = x
                        captured()
                    }
                    moveToAnimator?.cancel()
                    return true
                }
                middlePickerArea.contains(x, y) -> {
                    capturedStates[0] = CapturesData(CAPTURE_MIDDLE).apply {
                        start = pickerStart
                        end = pickerEnd
                        capturedX = x
                        lastMovingX = x
                        captured()
                    }
                    moveToAnimator?.cancel()
                    return true
                }
                y < leftPickerArea.bottom && y > leftPickerArea.top -> {
                    tryMoveTo = true
                    moveToX = x.toFloat()
                    moveToY = y.toFloat()
                    startTapTime = System.currentTimeMillis()
                    moveToAnimator?.let {
                        if (it.isRunning) {
                            view.onPickerJumpTo(pickerStart, pickerEnd, true)
                        }
                        it.cancel()
                    }
                    return true
                }
            }
        } else if (pointerIndex == 1) {
            if (pickerMode == PickerMode.SINGLE) return false
            val primary = capturedStates[0] ?: return false
            if (primary.state == CAPTURE_MIDDLE) return false
            if (leftPickerArea.contains(x, y) && primary.state != CAPTURE_LEFT) {
                capturedStates[1] = CapturesData(CAPTURE_LEFT).apply {
                    start = pickerStart
                    capturedX = x
                    lastMovingX = x
                    captured()
                }
                moveToAnimator?.cancel()
                return true
            }
            if (rightPickerArea.contains(x, y) && primary.state != CAPTURE_RIGHT) {
                capturedStates[1] = CapturesData(CAPTURE_RIGHT).apply {
                    end = pickerEnd
                    capturedX = x
                    lastMovingX = x
                    captured()
                }
                moveToAnimator?.cancel()
                return true
            }
        }
        return false
    }

    fun captured(): Boolean = capturedStates[0] != null || tryMoveTo

    fun move(x: Int, y: Int, pointer: Int): Boolean {
        if (tryMoveTo) return false
        val data = capturedStates[pointer] ?: return false
        data.lastMovingX = x
        var notify = false
        when (data.state) {
            CAPTURE_LEFT -> {
                pickerStart = data.start - (data.capturedX - x) / pickerWidth
                if (pickerStart < 0f) pickerStart = 0f
                if (pickerEnd - pickerStart < minDistance) pickerStart = pickerEnd - minDistance
                notify = true
            }
            CAPTURE_RIGHT -> {
                pickerEnd = data.end - (data.capturedX - x) / pickerWidth
                if (pickerEnd > 1f) pickerEnd = 1f
                if (pickerEnd - pickerStart < minDistance) pickerEnd = pickerStart + minDistance
                notify = true
            }
            CAPTURE_MIDDLE -> {
                pickerStart = data.start - (data.capturedX - x) / pickerWidth
                pickerEnd = data.end - (data.capturedX - x) / pickerWidth
                if (pickerStart < 0f) {
                    pickerStart = 0f
                    pickerEnd = data.end - data.start
                }
                if (pickerEnd > 1f) {
                    pickerEnd = 1f
                    pickerStart = 1f - (data.end - data.start)
                }
                notify = true
            }
        }
        if (notify) view.onPickerDataChanged()
        return true
    }

    fun set(start: Float, end: Float) {
        pickerStart = start
        pickerEnd = end
        view.onPickerDataChanged()
    }

    fun uncapture(event: MotionEvent, pointerIndex: Int): Boolean {
        if (pointerIndex == 0) {
            if (tryMoveTo) {
                tryMoveTo = false
                val dx = moveToX - event.x
                val dy = moveToY - event.y
                if (event.action == MotionEvent.ACTION_UP &&
                    System.currentTimeMillis() - startTapTime < 300 &&
                    sqrt(dx * dx + dy * dy) < 10.dp
                ) {
                    val localMoveToX = (moveToX - BaseChartView.HORIZONTAL_PADDING) / pickerWidth
                    val width = pickerEnd - pickerStart
                    var moveToLeft = localMoveToX - width / 2f
                    var moveToRight = localMoveToX + width / 2f
                    if (moveToLeft < 0f) {
                        moveToLeft = 0f
                        moveToRight = width
                    } else if (moveToRight > 1f) {
                        moveToLeft = 1f - width
                        moveToRight = 1f
                    }
                    val moveFromLeft = pickerStart
                    val moveFromRight = pickerEnd
                    moveToAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                        val finalLeft = moveToLeft
                        val finalRight = moveToRight
                        view.onPickerJumpTo(finalLeft, finalRight, true)
                        addUpdateListener {
                            val value = it.animatedValue as Float
                            pickerStart = moveFromLeft + (finalLeft - moveFromLeft) * value
                            pickerEnd = moveFromRight + (finalRight - moveFromRight) * value
                            view.onPickerJumpTo(finalLeft, finalRight, false)
                        }
                        interpolator = BaseChartView.INTERPOLATOR
                        start()
                    }
                }
                return true
            }
            capturedStates[0]?.uncapture()
            capturedStates[0] = null
            if (capturedStates[1] != null) {
                capturedStates[0] = capturedStates[1]
                capturedStates[1] = null
            }
        } else {
            capturedStates[1]?.uncapture()
            capturedStates[1] = null
        }
        return false
    }

    fun uncapture() {
        capturedStates[0]?.uncapture()
        capturedStates[1]?.uncapture()
        capturedStates[0] = null
        capturedStates[1] = null
    }

    interface Listener {
        fun onPickerDataChanged()
        fun onPickerJumpTo(start: Float, end: Float, force: Boolean)
        fun invalidate()
    }

    enum class PickerMode {
        RANGE,
        SINGLE,
    }

    companion object {
        private const val CAPTURE_LEFT = 1
        private const val CAPTURE_RIGHT = 1 shl 1
        private const val CAPTURE_MIDDLE = 1 shl 2
    }
}
