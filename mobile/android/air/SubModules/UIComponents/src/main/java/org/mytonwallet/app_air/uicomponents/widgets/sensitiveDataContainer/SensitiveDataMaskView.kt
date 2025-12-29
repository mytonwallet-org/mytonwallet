package org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import androidx.core.math.MathUtils.clamp
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import kotlin.math.roundToInt
import kotlin.random.Random

@SuppressLint("ViewConstructor")
class SensitiveDataMaskView(context: Context) : View(context) {

    companion object {
        private val STEPS = arrayOf(
            0.0001f * 0.06f,
            0.0001f * 0.06f,
            0.00001f * 0.06f,
            0.0003f * 0.06f,
            0.0001f * 0.06f,
            0.0025f * 0.06f
        )
        private const val FROM = 0.07f
        private const val TO = 0.25f
        private const val CHANGE_SPEED_INTERVAL = 3000L

        private val SKIN_COLORS = mapOf(
            Skin.LIGHT_THEME to intArrayOf(120, 121, 122),
            Skin.DARK_THEME to intArrayOf(240, 241, 242),
            Skin.GREEN to intArrayOf(83, 163, 13),
            Skin.RED to intArrayOf(255, 59, 48),
        )
    }

    enum class Skin {
        LIGHT_THEME,
        DARK_THEME,
        GREEN,
        RED,
    }

    var skin: Skin? = null
        set(value) {
            field = value
            invalidate()
        }

    private var isIntersecting: Boolean = false
    private var isBackgroundMode: Boolean = false

    private val paint = Paint()
    private val opacityMatrix = mutableListOf<MutableList<Float>>()
    private val stepsMatrix = mutableListOf<MutableList<Float>>()

    private var lastFrameTime: Long = 0
    private var lastSpeedChangeTime: Long = 0
    private var isRendered = false
    private var shouldAnimate = true

    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        repeatCount = ValueAnimator.INFINITE
        duration = 16
        addUpdateListener {
            if (shouldAnimate) {
                invalidate()
            }
        }
    }

    var cols = 10
    var rows = 2
    var cellSize = 8.dp
    var cornerRadius = 16f

    init {
        initMask()
    }

    fun initMask(): Boolean {
        val isAlreadyInitialized =
            stepsMatrix.size == rows &&
                (rows == 0 && cols == 0 || stepsMatrix.firstOrNull()?.size == cols)

        if (isAlreadyInitialized) return false

        opacityMatrix.clear()
        stepsMatrix.clear()

        repeat(rows) {
            opacityMatrix.add(
                MutableList(cols) { FROM + Random.nextFloat() * (TO - FROM) }
            )
            stepsMatrix.add(
                MutableList(cols) { STEPS.random() }
            )
        }

        return true
    }

    val calculatedWidth: Int
        get() {
            return cols * cellSize
        }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = calculatedWidth
        val height = rows * cellSize
        setMeasuredDimension(width, height)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        if ((!isIntersecting && isRendered) || isBackgroundMode) {
            return
        }

        canvas.save()

        val path = Path()
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        path.addRoundRect(rect, cornerRadius, cornerRadius, Path.Direction.CW)

        canvas.clipPath(path)

        val currentTime = System.currentTimeMillis()
        val frameDuration = if (lastFrameTime > 0) currentTime - lastFrameTime else 0
        val shouldChangeSpeed = currentTime - lastSpeedChangeTime >= CHANGE_SPEED_INTERVAL

        if (shouldChangeSpeed || lastSpeedChangeTime == 0L) {
            lastSpeedChangeTime = currentTime
        }

        val currentSkin =
            skin ?: if (ThemeManager.isDark) Skin.DARK_THEME else Skin.LIGHT_THEME
        val colorArray = SKIN_COLORS[currentSkin] ?: SKIN_COLORS[Skin.LIGHT_THEME]!!

        for (row in 0 until rows) {
            for (col in 0 until cols) {
                if (shouldChangeSpeed) {
                    val step = STEPS.random() * if (stepsMatrix[row][col] < 0) -1 else 1
                    stepsMatrix[row][col] = step
                }

                var nextOpacity = opacityMatrix[row][col]
                nextOpacity += stepsMatrix[row][col] * frameDuration

                if (nextOpacity > TO || nextOpacity < FROM) {
                    stepsMatrix[row][col] = -stepsMatrix[row][col]
                    nextOpacity = clamp(nextOpacity, FROM, TO)
                }

                opacityMatrix[row][col] = nextOpacity

                paint.color = Color.argb(
                    (nextOpacity * 255).roundToInt(),
                    colorArray[0],
                    colorArray[1],
                    colorArray[2]
                )

                canvas.drawRect(
                    col * cellSize.toFloat(),
                    row * cellSize.toFloat(),
                    (col + 1) * cellSize.toFloat(),
                    (row + 1) * cellSize.toFloat(),
                    paint
                )

                isRendered = true
            }
        }

        canvas.restore()

        lastFrameTime = currentTime
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        shouldAnimate = true
        if (isIntersecting)
            animator.start()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        shouldAnimate = false
        animator.cancel()
    }

    /* TODO:: override fun onResume(owner: LifecycleOwner) {
        isBackgroundMode = false
        if (isAttachedToWindow) {
            animator.resume()
        }
    }

    TODO:: override fun onPause(owner: LifecycleOwner) {
        isBackgroundMode = true
        animator.pause()
    }*/

    fun setIntersecting(intersecting: Boolean) {
        isIntersecting = intersecting
        if (intersecting && shouldAnimate) {
            if (animator.isPaused)
                animator.resume()
            else
                animator.start()
        } else if (!intersecting && animator.isRunning) {
            animator.pause()
        }
    }
}
