package org.mytonwallet.app_air.uimarket.viewControllers.market.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketToken
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class MarketMoverItemView(context: Context, private val onTap: (MarketToken) -> Unit) :
    WView(context),
    WThemedView {
    private val ripple = WRippleDrawable.create(26f.dp)
    private val chartView = MarketChartView(context)
    private val iconView = WCustomImageView(context)
    private val nameLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
    }
    private val subtitleLabel = MarketPriceChangeLabel(context)
    private var marketToken: MarketToken? = null

    init {
        id = UIComponentsR.id.market_mover
        background = ripple
        clipToOutline = true
        addView(chartView, LayoutParams(MATCH_PARENT, 42.dp))
        addView(iconView, LayoutParams(48.dp, 48.dp))
        addView(nameLabel, LayoutParams(0, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toBottom(chartView)
            toCenterX(chartView)
            toTop(iconView, 15f)
            toCenterX(iconView)
            topToBottom(nameLabel, iconView, 7f)
            toStart(nameLabel, 8f)
            toEnd(nameLabel, 8f)
            topToBottom(subtitleLabel, nameLabel, 2f)
            toCenterX(subtitleLabel)
        }
        isClickable = true
        setOnClickListener { marketToken?.let(onTap) }
        updateTheme()
    }

    fun configure(token: MarketToken) {
        marketToken = token
        iconView.set(Content.of(token.token, showChain = true))
        nameLabel.text = token.name
        subtitleLabel.configure(token)
        chartView.configure(token.chart)
        contentDescription = "${token.name}, ${token.priceText.orEmpty()}, ${token.changeText}"
        updateTheme()
    }

    override fun updateTheme() {
        val token = marketToken
        ripple.backgroundColor =
            token?.chart?.tint?.colorWithAlpha(15) ?: WColor.TrinaryBackground.color
        ripple.rippleColor = WColor.BackgroundRipple.color
        nameLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.updateTheme()
    }
}

private class MarketChartView(context: Context) : View(context) {
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2f.dp
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val linePath = Path()
    private val fillPath = Path()
    private var chart: MarketToken.Chart? = null

    init {
        id = generateViewId()
    }

    fun configure(value: MarketToken.Chart?) {
        chart = value
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val chart = chart ?: return
        if (chart.points.size < 2 || width == 0 || height == 0) return

        linePaint.color = chart.tint
        fillPaint.color = chart.tint.colorWithAlpha(24)
        linePath.reset()
        fillPath.reset()

        chart.points.forEachIndexed { index, point ->
            val x = index * width.toFloat() / (chart.points.lastIndex)
            val y = point.coerceIn(0f, 1f) * (height - 4.dp) + 2.dp
            if (index == 0) {
                linePath.moveTo(x, y)
                fillPath.moveTo(x, y)
            } else {
                linePath.lineTo(x, y)
                fillPath.lineTo(x, y)
            }
        }
        fillPath.lineTo(width.toFloat(), height.toFloat())
        fillPath.lineTo(0f, height.toFloat())
        fillPath.close()
        canvas.drawPath(fillPath, fillPaint)
        canvas.drawPath(linePath, linePaint)
    }
}
