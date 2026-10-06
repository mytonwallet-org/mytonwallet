package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.view.View
import kotlin.math.roundToInt
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat

class FiatCurrencyIconView(context: Context) : View(context) {

    private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var signDrawable: Drawable? = null

    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    fun configure(currency: MBaseCurrency) {
        signDrawable = signIcon(currency)?.let { context.getDrawableCompat(it)?.mutate() }
        updateSignSize()
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        circlePaint.shader = LinearGradient(
            0f,
            0f,
            0f,
            h.toFloat(),
            Color.rgb(160, 222, 126),
            Color.rgb(84, 203, 104),
            Shader.TileMode.CLAMP
        )
        updateSignSize()
    }

    private fun updateSignSize() {
        signDrawable?.let { drawable ->
            val frame = (minOf(width, height) * ICON_FRAME_RATIO).roundToInt()
            val left = (width - frame) / 2
            val top = (height - frame) / 2
            drawable.setBounds(left, top, left + frame, top + frame)
        }
    }

    override fun onDraw(canvas: Canvas) {
        val radius = minOf(width, height) / 2f
        canvas.drawCircle(width / 2f, height / 2f, radius, circlePaint)
        signDrawable?.draw(canvas)
    }

    private companion object {
        const val ICON_FRAME_RATIO = 26f / 44f

        fun signIcon(currency: MBaseCurrency): Int? = when (currency) {
            MBaseCurrency.USD -> org.mytonwallet.app_air.icons.R.drawable.ic_fiat_usd
            MBaseCurrency.EUR -> org.mytonwallet.app_air.icons.R.drawable.ic_fiat_eur
            MBaseCurrency.RUB -> org.mytonwallet.app_air.icons.R.drawable.ic_fiat_rub
            else -> null
        }
    }
}
