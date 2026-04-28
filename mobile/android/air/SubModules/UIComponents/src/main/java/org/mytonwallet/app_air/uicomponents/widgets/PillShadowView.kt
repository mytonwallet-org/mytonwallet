package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.View
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import androidx.core.graphics.withClip

@SuppressLint("ViewConstructor")
class PillShadowView(context: Context) : View(context), WThemedView {

    companion object {
        private const val SHADOW_RADIUS_DP = 2.667f
        private const val SHADOW_DX_DP = 0f
        private const val SHADOW_DY_DP = 0.85f
        private const val SHADOW_COLOR_LIGHT = 0x20000000
        private val SHADOW_COLOR_DARK = 0x80000000.toInt()

        private const val STROKE_WIDTH_DP = 0.4f
        private const val STROKE_TOP_COLOR_LIGHT = 0x11000000
        private const val STROKE_TOP_COLOR_DARK = 0x06FFFFFF
        private const val STROKE_BOTTOM_COLOR_LIGHT = 0x20000000
        private const val STROKE_BOTTOM_COLOR_DARK = 0x11FFFFFF

        private val PAD_DP = 6f

        /**
         * Attach a pill shadow to [target] as a sibling directly below it.
         * The caller owns updates: invoke [sync] whenever [target]'s bounds,
         * translation, alpha, or visibility change.
         */
        fun attachTo(target: View, cornerRadius: Float): PillShadowView {
            val parent = target.parent as? ViewGroup
                ?: throw IllegalStateException("target must be attached to a ViewGroup")
            val shadow = PillShadowView(target.context)
            shadow.cornerRadius = cornerRadius
            shadow.target = target
            val targetIndex = parent.indexOfChild(target)
            parent.addView(
                shadow,
                targetIndex.coerceAtLeast(0),
                if (target.layoutParams != null)
                    ViewGroup.LayoutParams(target.layoutParams)
                else
                    ViewGroup.LayoutParams(0, 0)
            )
            return shadow
        }
    }

    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = STROKE_WIDTH_DP.dp
    }
    private val rect = RectF()
    private var cornerRadius: Float = 0f
    private var hasTarget = false

    private var target: View? = null
    private val pad = PAD_DP.dp

    init {
        id = generateViewId()
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        refreshShadowLayer()
    }

    /**
     * Manual rect control in this view's coordinate space. Use when the pill
     * position/size is driven by an animation rather than a target view.
     * Incompatible with [attachTo].
     */
    fun setTargetRect(left: Float, top: Float, right: Float, bottom: Float, cornerRadius: Float) {
        val changed = rect.left != left || rect.top != top ||
            rect.right != right || rect.bottom != bottom ||
            this.cornerRadius != cornerRadius || !hasTarget
        if (!changed) return
        rect.set(left, top, right, bottom)
        this.cornerRadius = cornerRadius
        hasTarget = true
        invalidate()
    }

    /**
     * Sync shadow size, position, alpha, and visibility from the attached target.
     * Call after any change to target's bounds, translation, alpha, or visibility.
     */
    fun sync() {
        val t = target ?: return
        syncSizeFromTarget(t)
        syncPositionFromTarget(t)
    }

    private fun syncSizeFromTarget(target: View) {
        val w = target.width
        val h = target.height
        if (w == 0 || h == 0) return

        val padI = pad.toInt()
        val needW = w + padI * 2
        val needH = h + padI * 2
        val lp = layoutParams
        if (lp.width != needW || lp.height != needH) {
            lp.width = needW
            lp.height = needH
            layoutParams = lp
        }

        val left = pad
        val top = pad
        val right = pad + w
        val bottom = pad + h
        if (rect.left != left || rect.top != top ||
            rect.right != right || rect.bottom != bottom || !hasTarget
        ) {
            rect.set(left, top, right, bottom)
            hasTarget = true
            invalidate()
        }
    }

    private fun syncPositionFromTarget(target: View) {
        val p = parent as? ViewGroup
        if (target.parent !== p) {
            return
        }
        this.x = target.x - pad
        this.y = target.y - pad
        alpha = target.alpha
        visibility = target.visibility
    }

    override fun updateTheme() {
        refreshShadowLayer()
        invalidate()
    }

    private fun refreshShadowLayer() {
        val isDark = ThemeManager.isDark
        val shadowColor = if (isDark) SHADOW_COLOR_DARK else SHADOW_COLOR_LIGHT
        shadowPaint.color = Color.TRANSPARENT
        shadowPaint.setShadowLayer(
            SHADOW_RADIUS_DP.dp, SHADOW_DX_DP.dp, SHADOW_DY_DP.dp, shadowColor
        )
    }

    override fun onDraw(canvas: Canvas) {
        if (!hasTarget || rect.isEmpty) return

        canvas.drawRoundRect(rect, cornerRadius, cornerRadius, shadowPaint)

        val isDark = ThemeManager.isDark
        val strokeHalf = strokePaint.strokeWidth / 2f
        val innerRadius = (cornerRadius - strokeHalf).coerceAtLeast(0f)

        val topColor = if (isDark) STROKE_TOP_COLOR_DARK else STROKE_TOP_COLOR_LIGHT
        if (Color.alpha(topColor) > 0) {
            strokePaint.color = topColor
            canvas.withClip(rect.left, rect.top, rect.right, rect.top + cornerRadius) {
                canvas.drawRoundRect(
                    rect.left + strokeHalf, rect.top + strokeHalf,
                    rect.right - strokeHalf, rect.bottom - strokeHalf,
                    innerRadius, innerRadius,
                    strokePaint
                )
            }
        }

        val bottomColor = if (isDark) STROKE_BOTTOM_COLOR_DARK else STROKE_BOTTOM_COLOR_LIGHT
        if (Color.alpha(bottomColor) > 0) {
            strokePaint.color = bottomColor
            canvas.withClip(rect.left, rect.bottom - cornerRadius, rect.right, rect.bottom) {
                canvas.drawRoundRect(
                    rect.left + strokeHalf, rect.top + strokeHalf,
                    rect.right - strokeHalf, rect.bottom - strokeHalf,
                    innerRadius, innerRadius,
                    strokePaint
                )
            }
        }
    }
}
