package org.mytonwallet.app_air.ledger.screens.ledgerConnect.views

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.view.View
import androidx.interpolator.view.animation.FastOutSlowInInterpolator
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class LedgerConnectStepStatusView(context: Context) : View(context) {

    init {
        id = generateViewId()
    }

    enum class State {
        WAITING, IN_PROGRESS, DONE, ERROR
    }

    private val animationDuration = AnimationConstants.SLOW_ANIMATION
    private var currentAnimator: ValueAnimator? = null
    private var animationProgress = 0f
    private var previousState = State.WAITING

    var state = State.WAITING
        set(value) {
            if (field != value) {
                previousState = field
                field = value
                animateStateChange()
            }
        }

    private val roundDrawable = RoundProgressDrawable(12.dp, 0.5f.dp).apply {
        color = WColor.SecondaryText.color
    }

    private val paints = mapOf(
        State.WAITING to Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = WColor.SecondaryText.color
            style = Paint.Style.FILL
        },
        State.ERROR to Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = WColor.Error.color
            style = Paint.Style.FILL
        },
        State.DONE to Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = WColor.Green.color
            style = Paint.Style.FILL
        }
    )

    private val doneTickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 3f
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }

    private val tickPath = Path()
    private val tickPathMeasure = PathMeasure()
    private val animatedTickPath = Path()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(24.dp, 24.dp)
    }

    private fun animateStateChange() {
        currentAnimator?.cancel()
        prepareTickPathIfNeeded()
        currentAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = animationDuration
            interpolator = FastOutSlowInInterpolator()
            addUpdateListener {
                animationProgress = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    private fun prepareTickPathIfNeeded() {
        if (tickPath.isEmpty && (state == State.DONE || previousState == State.DONE)) {
            val centerX = width / 2f
            val centerY = height / 2f
            tickPath.apply {
                moveTo(centerX - 4.dp, centerY)
                lineTo(centerX - 1.dp, centerY + 3.dp)
                lineTo(centerX + 4.dp, centerY - 3.dp)
            }
            tickPathMeasure.setPath(tickPath, false)
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f

        when (state) {
            State.WAITING -> drawWaitingState(canvas, cx, cy)
            State.ERROR -> drawErrorState(canvas, cx, cy)
            State.IN_PROGRESS -> drawInProgressState(canvas, cx, cy)
            State.DONE -> drawDoneState(canvas, cx, cy)
        }
    }

    private fun drawCircle(
        canvas: Canvas,
        paint: Paint,
        cx: Float,
        cy: Float,
        radius: Int,
        alpha: Int = 255
    ) {
        paint.alpha = alpha
        canvas.drawCircle(cx, cy, radius.toFloat(), paint)
    }

    private fun drawTick(canvas: Canvas, progress: Float, alpha: Int) {
        doneTickPaint.alpha = alpha
        animatedTickPath.reset()
        tickPathMeasure.getSegment(
            0f, tickPathMeasure.length * progress, animatedTickPath, true
        )
        canvas.drawPath(animatedTickPath, doneTickPaint)
    }

    private fun drawWaitingState(canvas: Canvas, cx: Float, cy: Float) {
        when (previousState) {
            State.DONE, State.ERROR -> {
                val prevPaint = paints[previousState]!!
                val doneAlpha = (255 * (1 - animationProgress)).toInt()
                val waitAlpha = (255 * animationProgress).toInt()
                if (previousState == State.DONE) {
                    drawCircle(canvas, paints[State.DONE]!!, cx, cy, 8.dp, doneAlpha)
                    drawTick(canvas, 1f, doneAlpha)
                } else drawCircle(canvas, prevPaint, cx, cy, 4.dp, doneAlpha)
                drawCircle(canvas, paints[State.WAITING]!!, cx, cy, 4.dp, waitAlpha)
            }

            State.IN_PROGRESS -> {
                val alpha = (255 * (1 - animationProgress)).toInt()
                canvas.save()
                canvas.scale(1 - animationProgress, 1 - animationProgress, cx, cy)
                roundDrawable.setBounds(6.dp, 6.dp, 18.dp, 18.dp)
                roundDrawable.alpha = alpha
                roundDrawable.draw(canvas)
                canvas.restore()
                drawCircle(
                    canvas,
                    paints[State.WAITING]!!,
                    cx,
                    cy,
                    4.dp,
                    (255 * animationProgress).toInt()
                )
            }

            else -> drawCircle(canvas, paints[State.WAITING]!!, cx, cy, 4.dp)
        }
    }

    private fun drawErrorState(canvas: Canvas, cx: Float, cy: Float) {
        val errorPaint = paints[State.ERROR]!!
        val prevPaint = paints[previousState] ?: errorPaint
        when (previousState) {
            State.WAITING, State.DONE -> {
                val prevAlpha = (255 * (1 - animationProgress)).toInt()
                val errorAlpha = (255 * animationProgress).toInt()
                if (previousState == State.DONE) {
                    drawCircle(canvas, paints[State.DONE]!!, cx, cy, 8.dp, prevAlpha)
                    drawTick(canvas, 1f, prevAlpha)
                } else drawCircle(canvas, prevPaint, cx, cy, 4.dp, prevAlpha)
                drawCircle(canvas, errorPaint, cx, cy, 4.dp, errorAlpha)
            }

            State.IN_PROGRESS -> {
                canvas.save()
                canvas.scale(1 - animationProgress, 1 - animationProgress, cx, cy)
                roundDrawable.setBounds(6.dp, 6.dp, 18.dp, 18.dp)
                roundDrawable.alpha = (255 * (1 - animationProgress)).toInt()
                roundDrawable.draw(canvas)
                canvas.restore()
                drawCircle(canvas, errorPaint, cx, cy, 4.dp, (255 * animationProgress).toInt())
            }

            else -> drawCircle(canvas, errorPaint, cx, cy, 4.dp)
        }
    }

    private fun drawInProgressState(canvas: Canvas, cx: Float, cy: Float) {
        val normalizedProgress =
            if (animationProgress < 0.5f) animationProgress * 2 else (animationProgress - 0.5f) * 2

        when (previousState) {
            State.WAITING, State.ERROR -> {
                val prevPaint = paints[previousState]!!
                if (animationProgress < 0.5f) {
                    drawCircle(
                        canvas,
                        prevPaint,
                        cx,
                        cy,
                        4.dp,
                        (255 * (1 - normalizedProgress)).toInt()
                    )
                } else {
                    roundDrawable.alpha = (255 * normalizedProgress).toInt()
                    roundDrawable.setBounds(6.dp, 6.dp, 18.dp, 18.dp)
                    roundDrawable.draw(canvas)
                    invalidate()
                }
            }

            State.DONE -> {
                if (animationProgress < 0.5f) {
                    val alpha = (255 * (1 - normalizedProgress)).toInt()
                    drawCircle(canvas, paints[State.DONE]!!, cx, cy, 8.dp, alpha)
                    drawTick(canvas, 1f, alpha)
                } else {
                    roundDrawable.alpha = (255 * normalizedProgress).toInt()
                    roundDrawable.setBounds(6.dp, 6.dp, 18.dp, 18.dp)
                    roundDrawable.draw(canvas)
                }
            }

            else -> {
                roundDrawable.setBounds(6.dp, 6.dp, 18.dp, 18.dp)
                roundDrawable.draw(canvas)
                invalidate()
            }
        }
    }

    private fun drawDoneState(canvas: Canvas, cx: Float, cy: Float) {
        val normalizedProgress =
            if (animationProgress < 0.5f) animationProgress * 2 else (animationProgress - 0.5f) * 2

        when (previousState) {
            State.IN_PROGRESS -> {
                if (animationProgress < 0.5f) {
                    canvas.save()
                    canvas.scale(1 - normalizedProgress, 1 - normalizedProgress, cx, cy)
                    roundDrawable.alpha = (255 * (1 - normalizedProgress)).toInt()
                    roundDrawable.setBounds(6.dp, 6.dp, 18.dp, 18.dp)
                    roundDrawable.draw(canvas)
                    canvas.restore()
                } else {
                    drawCircle(
                        canvas,
                        paints[State.DONE]!!,
                        cx,
                        cy,
                        8.dp,
                        (255 * normalizedProgress).toInt()
                    )
                    drawTick(canvas, normalizedProgress, (255 * normalizedProgress).toInt())
                }
            }

            State.WAITING, State.ERROR -> {
                val prevPaint = paints[previousState]!!
                if (animationProgress < 0.5f) {
                    drawCircle(
                        canvas,
                        prevPaint,
                        cx,
                        cy,
                        4.dp,
                        (255 * (1 - normalizedProgress)).toInt()
                    )
                } else {
                    drawCircle(
                        canvas,
                        paints[State.DONE]!!,
                        cx,
                        cy,
                        8.dp,
                        (255 * normalizedProgress).toInt()
                    )
                    drawTick(canvas, normalizedProgress, (255 * normalizedProgress).toInt())
                }
            }

            else -> {
                drawCircle(canvas, paints[State.DONE]!!, cx, cy, 8.dp)
                canvas.drawPath(tickPath, doneTickPaint)
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        currentAnimator?.cancel()
        currentAnimator = null
    }
}
