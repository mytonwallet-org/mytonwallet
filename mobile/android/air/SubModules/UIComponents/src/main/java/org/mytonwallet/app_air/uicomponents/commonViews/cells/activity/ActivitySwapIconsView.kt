package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.content.Context
import android.graphics.Canvas
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import kotlin.math.roundToInt

class ActivitySwapIconsView(context: Context) : WFrameLayout(context), WThemedView {

    private val viewHeight = 30.dp
    private val iconWidth = 18.dp
    private val iconStrokeWidth = 1.dp
    private val iconBackgroundDrawable = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
    }

    private val fromIconView = WCustomImageView(context)

    private val toIconView = WCustomImageView(context)

    init {
        id = generateViewId()
        setWillNotDraw(false)
        addView(fromIconView, LayoutParams(iconWidth, iconWidth).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })
        addView(toIconView, LayoutParams(iconWidth, iconWidth).apply {
            gravity = Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM
        })
    }

    fun configure(swap: MApiTransaction.Swap) {
        val fromToken = swap.fromToken
        val toToken = swap.toToken
        if (fromToken == null || toToken == null) {
            fromIconView.clear()
            toIconView.clear()
            return
        }
        fromIconView.set(Content.of(fromToken, showChain = false))
        toIconView.set(Content.of(toToken, showChain = false))
        updateTheme()
    }

    override fun updateTheme() {
        iconBackgroundDrawable.setColor(WColor.Background.color)
    }

    override fun drawChild(canvas: Canvas, child: View, drawingTime: Long): Boolean {
        drawIconBackground(canvas, child)
        return super.drawChild(canvas, child, drawingTime)
    }

    private fun drawIconBackground(canvas: Canvas, view: View) {
        val left = view.x.roundToInt()
        val top = view.y.roundToInt()
        iconBackgroundDrawable.setBounds(
            left - iconStrokeWidth,
            top - iconStrokeWidth,
            left + view.width + iconStrokeWidth,
            top + view.height + iconStrokeWidth
        )
        iconBackgroundDrawable.draw(canvas)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            (iconWidth + paddingLeft + paddingRight).exactly,
            (viewHeight + paddingTop + paddingBottom).exactly
        )
    }
}
