package org.mytonwallet.app_air.uicomponents.widgets.balance

import androidx.core.graphics.ColorUtils
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt


data class WBalanceViewAnimatingCharacter(
    val prevChar: WBalanceViewCharacter?,
    val nextChar: WBalanceViewCharacter?,
    val change: Change,
    var delay: Int = 0,
    var charAnimationDuration: Int = 0,
) {
    enum class Change {
        INC, DEC, NONE
    }

    var totalSteps: Int
    var startFrom0Alpha: Boolean
    var endWith0Alpha: Boolean
    var startNum = prevChar?.char?.toString()?.toIntOrNull()
    val endNum = nextChar?.char?.toString()?.toIntOrNull()
    var startChar = prevChar?.char

    init {

        val startNum = startNum
        if (startNum != null && endNum != null) {
            totalSteps = if (endNum == startNum) {
                10
            } else {
                if (change == Change.INC) {
                    if (endNum > startNum) {
                        abs(endNum - startNum)
                    } else {
                        abs(endNum + 10 - startNum)
                    }
                } else {
                    if (endNum < startNum) {
                        abs(startNum - endNum)
                    } else {
                        abs(startNum + 10 - endNum)
                    }
                }
            }
            startFrom0Alpha = false
            endWith0Alpha = false
        } else {
            if ((prevChar == null || prevChar.char == ' ') && endNum != null) {
                totalSteps = 5
                this.startNum = if (endNum >= 5) {
                    (endNum - 5)
                } else {
                    (endNum + 5)
                }
                startFrom0Alpha = true
                endWith0Alpha = false
            } else if (nextChar?.char == null && startNum != null) {
                totalSteps = 5
                startFrom0Alpha = false
                endWith0Alpha = true
            } else {
                totalSteps = 1
                startFrom0Alpha = false
                endWith0Alpha = false
            }
        }
    }

    fun normalizedLeft(scale1: Float, scale2: Float, left: Float, integerPartWidth: Float): Float {
        if (left <= integerPartWidth)
            return left * scale1
        return integerPartWidth * scale1 + (left - integerPartWidth) * scale2
    }

    fun currentRectangles(
        elapsed: Int,
        scale1: Float,
        scale2: Float,
        offset2: Float,
        prevIntegerPartWidth: Float,
        integerPartWidth: Float,
        decimalsAlpha: Int,
    ): List<WBalanceViewDrawingCharacterRect> {
        val easedProgress = ((elapsed - delay) / charAnimationDuration.toFloat()).coerceIn(0f, 1f)

        val currentLeftOffset = lerp(
            normalizedLeft(scale1, scale2, prevChar?.left ?: nextChar!!.left, prevIntegerPartWidth),
            normalizedLeft(scale1, scale2, nextChar?.left ?: prevChar!!.left, integerPartWidth),
            easedProgress
        )

        if (change == Change.NONE) {
            return listOf(
                WBalanceViewDrawingCharacterRect(
                    leftOffset = currentLeftOffset,
                    offsetY = if (prevChar!!.isDecimalPart) offset2 else 0f,
                    yOffsetPercent = 0f,
                    char = startChar!!,
                    textSize = prevChar.size,
                    color = prevChar.color,
                    alpha = if (prevChar.isDecimalOrBaseCurrency) decimalsAlpha else 255,
                    scaleMultiplier = if (prevChar.isDecimalPart) 1f else 0f
                )
            )
        }

        val color = ColorUtils.blendARGB(
            prevChar?.color ?: nextChar!!.color,
            nextChar?.color ?: prevChar!!.color,
            easedProgress
        )

        val offsetY = lerp(
            if (prevChar?.isDecimalPart ?: nextChar!!.isDecimalPart) offset2 else 0f,
            if (nextChar?.isDecimalPart ?: prevChar!!.isDecimalPart) offset2 else 0f,
            easedProgress
        )

        val alphaMult = lerp(
            if (prevChar?.isDecimalOrBaseCurrency
                    ?: nextChar!!.isDecimalOrBaseCurrency
            ) decimalsAlpha.toFloat() else 255f,
            if (nextChar?.isDecimalOrBaseCurrency
                    ?: prevChar!!.isDecimalOrBaseCurrency
            ) decimalsAlpha.toFloat() else 255f,
            easedProgress
        )

        val textSize = lerp(
            prevChar?.size ?: nextChar!!.size,
            nextChar?.size ?: prevChar!!.size,
            easedProgress
        )

        val scaleMultiplier = lerp(
            if (prevChar?.isDecimalPart ?: nextChar!!.isDecimalPart) 1f else 0f,
            if (nextChar?.isDecimalPart ?: prevChar!!.isDecimalPart) 1f else 0f,
            easedProgress
        )

        val startNum = startNum
        if (totalSteps <= 1 || startNum == null) {

            val rects = mutableListOf<WBalanceViewDrawingCharacterRect>()

            val rect1 = WBalanceViewDrawingCharacterRect(
                leftOffset = currentLeftOffset,
                offsetY = offsetY,
                yOffsetPercent = if (change == Change.INC) easedProgress else -easedProgress,
                char = prevChar?.char,
                textSize = textSize,
                color = color,
                alpha = (alphaMult * ((if (endWith0Alpha) 1 - easedProgress else 1f) * (1 - easedProgress))).roundToInt(),
                scaleMultiplier = scaleMultiplier
            )
            rects.add(rect1)

            if (easedProgress > 0) {
                val rect2 = WBalanceViewDrawingCharacterRect(
                    leftOffset = currentLeftOffset,
                    offsetY = offsetY,
                    yOffsetPercent = if (change == Change.INC) -1 + easedProgress else 1 - easedProgress,
                    char = nextChar?.char,
                    textSize = textSize,
                    color = color,
                    alpha = (alphaMult * ((if (endWith0Alpha) 1 - easedProgress else 1f) * easedProgress)).roundToInt(),
                    scaleMultiplier = scaleMultiplier
                )
                rects.add(rect2)
            }

            return rects
        }

        val currentStep = easedProgress * totalSteps
        val stepProgress = currentStep - floor(currentStep)
        val currentStepChar =
            ('0'.code + norm(startNum + (currentStep * if (change == Change.INC) 1 else -1).toInt()) % 10).toChar()
        val nextStepChar =
            ('0'.code + norm(startNum + ((currentStep + 1) * if (change == Change.INC) 1 else -1).toInt()) % 10).toChar()

        val rects = mutableListOf<WBalanceViewDrawingCharacterRect>()

        val rect1 = WBalanceViewDrawingCharacterRect(
            leftOffset = currentLeftOffset,
            offsetY = offsetY,
            yOffsetPercent = if (change == Change.INC) stepProgress else -stepProgress,
            char = currentStepChar,
            textSize = textSize,
            color = color,
            alpha = (alphaMult * (if (endWith0Alpha) (1 - easedProgress) else 1f) *
                (if (startFrom0Alpha && currentStep < 1) 0f else 1 - stepProgress)).roundToInt(),
            scaleMultiplier = scaleMultiplier
        )
        rects.add(rect1)

        if (easedProgress > 0) {
            val rect2 = WBalanceViewDrawingCharacterRect(
                leftOffset = currentLeftOffset,
                offsetY = offsetY,
                yOffsetPercent = if (change == Change.INC) -1 + stepProgress else 1 - stepProgress,
                char = nextStepChar,
                textSize = textSize,
                color = color,
                alpha = (alphaMult * (if (endWith0Alpha) (1 - easedProgress) else 1f) * stepProgress).roundToInt(),
                scaleMultiplier = scaleMultiplier
            )
            rects.add(rect2)
        }

        return rects
    }

    private fun norm(value: Int): Int {
        return if (value >= 10) value else 10 + value
    }
}
