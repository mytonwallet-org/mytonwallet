package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Region
import android.os.Build
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
         * Attach a pill shadow to [target]. By default it is inserted directly
         * below [target] in z-order. Pass [drawInFront] = true to insert it above
         * [target] instead; the rounded interior is then punched out so only the
         * halo paints, letting the shadow show over an opaque target (e.g. an edge
         * that is otherwise occluded by the target's own body).
         * The caller owns updates: invoke [sync] whenever [target]'s bounds,
         * translation, alpha, or visibility change.
         */
        fun attachTo(target: View, cornerRadius: Float, drawInFront: Boolean = false): PillShadowView {
            val parent = target.parent as? ViewGroup
                ?: throw IllegalStateException("target must be attached to a ViewGroup")
            val shadow = PillShadowView(target.context)
            shadow.cornerRadius = cornerRadius
            shadow.drawInFront = drawInFront
            shadow.target = target
            val targetIndex = parent.indexOfChild(target)
            val insertIndex = if (drawInFront) targetIndex + 1 else targetIndex
            parent.addView(
                shadow,
                insertIndex.coerceAtLeast(0),
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
    private var bottomCornerRadiusOverride: Float? = null
    private var bottomInset: Float = 0f
    private var drawInFront = false
    private var hasTarget = false

    private val shadowPath = Path()
    private val strokePath = Path()
    private val punchOutPath = Path()

    private val bottomCornerRadius: Float
        get() = bottomCornerRadiusOverride ?: cornerRadius

    private var target: View? = null
    private val pad = PAD_DP.dp

    fun setBottomCornerRadius(radius: Float?) {
        if (bottomCornerRadiusOverride == radius) return
        bottomCornerRadiusOverride = radius
        invalidate()
    }

    fun setBottomInset(inset: Float) {
        if (bottomInset == inset) return
        bottomInset = inset
        sync()
        invalidate()
    }

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
     * Sync shadow size, transform, alpha, and visibility from the attached target.
     * Call after any change to target's bounds, translation, scale, alpha, or visibility.
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
        val bottom = pad + h - bottomInset
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
        pivotX = pad + target.pivotX
        pivotY = pad + target.pivotY
        scaleX = target.scaleX
        scaleY = target.scaleY
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

        val topRadius = cornerRadius
        val bottomRadius = bottomCornerRadius

        shadowPath.reset()
        shadowPath.addRoundRect(rect, cornerRadii(topRadius, bottomRadius), Path.Direction.CW)
        if (drawInFront) {
            val inset = strokePaint.strokeWidth
            punchOutPath.reset()
            punchOutPath.addRoundRect(
                rect.left + inset, rect.top + inset,
                rect.right - inset, rect.bottom - inset,
                cornerRadii(
                    (topRadius - inset).coerceAtLeast(0f),
                    (bottomRadius - inset).coerceAtLeast(0f)
                ),
                Path.Direction.CW
            )
            canvas.save()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                canvas.clipOutPath(punchOutPath)
            else
                @Suppress("DEPRECATION")
                canvas.clipPath(punchOutPath, Region.Op.DIFFERENCE)
            canvas.drawPath(shadowPath, shadowPaint)
            canvas.restore()
        } else {
            canvas.drawPath(shadowPath, shadowPaint)
        }

        val isDark = ThemeManager.isDark
        val strokeHalf = strokePaint.strokeWidth / 2f
        val innerTop = (topRadius - strokeHalf).coerceAtLeast(0f)
        val innerBottom = (bottomRadius - strokeHalf).coerceAtLeast(0f)

        strokePath.reset()
        strokePath.addRoundRect(
            rect.left + strokeHalf, rect.top + strokeHalf,
            rect.right - strokeHalf, rect.bottom - strokeHalf,
            cornerRadii(innerTop, innerBottom), Path.Direction.CW
        )

        val topColor = if (isDark) STROKE_TOP_COLOR_DARK else STROKE_TOP_COLOR_LIGHT
        if (Color.alpha(topColor) > 0 && topRadius > 0f) {
            strokePaint.color = topColor
            canvas.withClip(rect.left, rect.top, rect.right, rect.top + topRadius) {
                canvas.drawPath(strokePath, strokePaint)
            }
        }

        val bottomColor = if (isDark) STROKE_BOTTOM_COLOR_DARK else STROKE_BOTTOM_COLOR_LIGHT
        if (Color.alpha(bottomColor) > 0 && bottomRadius > 0f) {
            strokePaint.color = bottomColor
            canvas.withClip(rect.left, rect.bottom - bottomRadius, rect.right, rect.bottom) {
                canvas.drawPath(strokePath, strokePaint)
            }
        }
    }

    private val radiiBuffer = FloatArray(8)

    private fun cornerRadii(topRadius: Float, bottomRadius: Float): FloatArray {
        radiiBuffer[0] = topRadius; radiiBuffer[1] = topRadius   // top-left
        radiiBuffer[2] = topRadius; radiiBuffer[3] = topRadius   // top-right
        radiiBuffer[4] = bottomRadius; radiiBuffer[5] = bottomRadius // bottom-right
        radiiBuffer[6] = bottomRadius; radiiBuffer[7] = bottomRadius // bottom-left
        return radiiBuffer
    }
}
