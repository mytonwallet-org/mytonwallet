package org.mytonwallet.app_air.widgets.utils

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.util.TypedValue
import androidx.core.graphics.createBitmap
import org.mytonwallet.app_air.walletbasecontext.utils.colorLightened

object ChartUtils {
    fun chartToBitmap(
        context: Context,
        priceChartData: Array<Array<Double>>,
        baseColor: Int,
        chartWidth: Int = 200.dp,
        chartHeight: Int = 120.dp,
        paddingBottom: Int = 77.dp,
    ): Bitmap {
        val totalHeight = chartHeight + paddingBottom
        val bitmap = createBitmap(chartWidth, totalHeight)
        val canvas = Canvas(bitmap)

        if (priceChartData.isEmpty()) return bitmap

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            strokeWidth = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                1.5f,
                context.resources.displayMetrics
            )
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }

        val prices = priceChartData.map { it[1] }
        val minPrice = prices.minOrNull() ?: 0.0
        val maxPrice = prices.maxOrNull() ?: 0.0
        val priceRange = maxPrice - minPrice
        if (priceRange == 0.0) return bitmap

        val lineChartPath = Path()
        priceChartData.forEachIndexed { index, dataPoint ->
            val x = (index.toFloat() / (priceChartData.size - 1)) * chartWidth
            val normalizedPrice = (dataPoint[1] - minPrice) / priceRange
            val y = (1 - normalizedPrice) * chartHeight

            if (index == 0) lineChartPath.moveTo(x, y.toFloat())
            else lineChartPath.lineTo(x, y.toFloat())
        }

        val fillPath = Path(lineChartPath)
        fillPath.lineTo(chartWidth.toFloat(), totalHeight.toFloat())
        fillPath.lineTo(0f, totalHeight.toFloat())
        fillPath.close()

        val gradientPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            shader = LinearGradient(
                0f, 0f, 0f, totalHeight.toFloat(),
                baseColor.colorLightened(0.4f).colorWithAlpha(191),
                baseColor.colorWithAlpha(51),
                Shader.TileMode.CLAMP
            )
        }

        canvas.drawPath(fillPath, gradientPaint)
        canvas.drawPath(lineChartPath, paint)

        return bitmap
    }
}
