package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
open class WAlertLabel(
    context: Context,
    textContents: CharSequence? = null,
    val alertColor: Int = WColor.Orange.color,
    val handleSize: Float = 4f.dp,
    rounding: Float = 12f.dp,
    bgAlpha: Int = 31,
    coloredText: Boolean = false
) : WLabel(context) {

    private val paint = Paint().apply {
        color = alertColor
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawRect(0f, 0f, handleSize, height.toFloat(), paint)
        super.onDraw(canvas)
    }

    init {
        setStyle(14f, WFont.Medium)
        text = textContents
        if (coloredText) {
            setTextColor(alertColor)
        }
        setPaddingDp(16, 10, 12, 8)
        setBackgroundColor(alertColor.colorWithAlpha(bgAlpha), rounding, true)
    }

}
