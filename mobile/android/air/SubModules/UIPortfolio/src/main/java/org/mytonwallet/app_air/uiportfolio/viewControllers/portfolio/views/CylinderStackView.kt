package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioBreakdownSlice
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class CylinderStackView(context: Context) : View(context), WThemedView {

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val highlightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = WColor.Background.color
        strokeWidth = 3f.dp
    }
    private val capPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val ellipseRect = RectF()
    private val bodyPath = Path()

    private var slices: List<PortfolioBreakdownSlice> = emptyList()

    fun setSlices(slices: List<PortfolioBreakdownSlice>) {
        this.slices = slices
        invalidate()
    }

    override fun updateTheme() {
        strokePaint.color = WColor.Background.color
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        if (slices.isEmpty()) return

        val sum = slices.sumOf { it.ratio }
        if (sum <= 0.0) return

        val w = width.toFloat()
        val h = height.toFloat()
        // ~45° viewing angle: ry ~ 0.22 * width
        val rY = w * 0.22f
        // bodyTop = ellipse vertical radius (so full top cap fits inside view)
        val bodyTop = rY
        // bodyBottom uses full bottom curve; bottom-most segment cap extends to h
        val bodyBottom = h - rY
        val bodyRange = bodyBottom - bodyTop
        if (bodyRange <= 0f) return

        val heights = slices.map { (it.ratio / sum * bodyRange).toFloat() }

        // draw bottom-up: lower segments first, upper segments paint over their caps
        var topY = bodyBottom
        for (i in slices.indices.reversed()) {
            val segH = heights[i]
            val segTopY = topY - segH
            val color = slices[i].color
            fillPaint.color = color

            // body: straight top edge at segTopY, curved bottom arc at topY
            bodyPath.reset()
            bodyPath.moveTo(0f, segTopY)
            bodyPath.lineTo(0f, topY)
            ellipseRect.set(0f, topY - rY, w, topY + rY)
            bodyPath.arcTo(ellipseRect, 180f, -180f)
            bodyPath.lineTo(w, segTopY)
            bodyPath.close()
            canvas.drawPath(bodyPath, fillPaint)

            // Classic-matching glossy highlight: vertical white gradient from 24% at 16.8% of
            // body height to 0% at 94.5%
            val bodyHeight = (topY + rY) - segTopY
            highlightPaint.shader = LinearGradient(
                0f, segTopY + 0.168f * bodyHeight,
                0f, segTopY + 0.945f * bodyHeight,
                Color.argb((255 * 0.24f).toInt(), 255, 255, 255),
                Color.argb(0, 255, 255, 255),
                Shader.TileMode.CLAMP,
            )
            canvas.drawPath(bodyPath, highlightPaint)

            // top cap: full ellipse with 40% white overlay (matches Classic's topmost cap)
            capPaint.color = lighten(color, 0.4f)
            ellipseRect.set(0f, segTopY - rY, w, segTopY + rY)
            canvas.drawOval(ellipseRect, capPaint)

            // white seam between cap and segment below (skip for topmost — no segment above it)
            if (i > 0) {
                canvas.drawOval(ellipseRect, strokePaint)
            }

            topY = segTopY
        }
    }

    private fun lighten(color: Int, amount: Float): Int {
        val r = Color.red(color)
        val g = Color.green(color)
        val b = Color.blue(color)
        val nr = (r + (255 - r) * amount).toInt().coerceIn(0, 255)
        val ng = (g + (255 - g) * amount).toInt().coerceIn(0, 255)
        val nb = (b + (255 - b) * amount).toInt().coerceIn(0, 255)
        return Color.argb(Color.alpha(color), nr, ng, nb)
    }
}
