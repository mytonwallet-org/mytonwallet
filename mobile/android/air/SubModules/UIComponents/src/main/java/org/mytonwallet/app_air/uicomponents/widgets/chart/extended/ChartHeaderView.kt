package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.content.Context
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat

class ChartHeaderView(context: Context) : FrameLayout(context), WThemedView {

    private val dates: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.DemiBold)
            setTextColor(WColor.PrimaryText)
            lineHeight = 24.dp
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
        }
    }

    private val datesTmp: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.DemiBold)
            setTextColor(WColor.PrimaryText)
            lineHeight = 24.dp
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            visibility = GONE
        }
    }

    val back: WLabel by lazy {
        object : WLabel(context) {
            private val ripple = WRippleDrawable.create(20f.dp)

            init {
                background = ripple
            }

            override fun updateTheme() {
                super.updateTheme()
                ripple.rippleColor = WColor.TintRipple.color
                zoomIcon?.setTint(WColor.Tint.color)
            }
        }.apply {
            visibility = GONE
            lineHeight = 24.dp
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setStyle(16f, WFont.DemiBold)
            setTextColor(WColor.Tint)
            text = LocaleController.getString("Zoom Out")
            setCompoundDrawablesWithIntrinsicBounds(zoomIcon, null, null, null)
            compoundDrawablePadding = 4.dp
            setPadding(8.dp, 4.dp, 8.dp, 4.dp)
        }
    }

    private val zoomIcon: Drawable? by lazy {
        context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_zoom_out_24)
    }

    init {
        minimumHeight = 32.dp
        addView(
            back,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                marginStart = 8.dp
                marginEnd = 8.dp
            }
        )

        addView(dates, datesLayoutParams())
        addView(datesTmp, datesLayoutParams())

        datesTmp.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            datesTmp.pivotX = datesTmp.measuredWidth * 0.7f
            dates.pivotX = dates.measuredWidth * 0.7f
        }
        updateTheme()
    }

    override fun updateTheme() {
        dates.updateTheme()
        datesTmp.updateTheme()
        back.updateTheme()
    }

    fun setDates(start: Long, end: Long) {
        val newText = if (end - start >= 86400000L) {
            ChartFormatters.formatDate("d MMM yyyy", start) +
                " — " +
                ChartFormatters.formatDate("d MMM yyyy", end)
        } else {
            ChartFormatters.formatDate("d MMM yyyy", start)
        }
        dates.text = newText
        dates.visibility = VISIBLE
    }

    fun zoomTo(d: Long, animate: Boolean) {
        setDates(d, d)
        back.visibility = VISIBLE
        if (animate) {
            back.alpha = 0f
            back.scaleX = 0.8f
            back.scaleY = 0.8f
            back.animate().alpha(1f).scaleY(1f).scaleX(1f).setDuration(200).start()
        } else {
            back.alpha = 1f
            back.scaleX = 1f
            back.scaleY = 1f
        }
    }

    fun zoomOut(chartView: BaseChartView<*, *>, animated: Boolean) {
        setDates(chartView.getStartDate(), chartView.getEndDate())
        if (animated) {
            back.alpha = 1f
            back.scaleX = 1f
            back.scaleY = 1f
            back.animate().alpha(0f).scaleY(0.8f).scaleX(0.8f).setDuration(200).start()
        } else {
            back.alpha = 0f
        }
    }

    private fun datesLayoutParams(): LayoutParams {
        return LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
            .apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                marginStart = 16.dp
                marginEnd = 16.dp
            }
    }
}
