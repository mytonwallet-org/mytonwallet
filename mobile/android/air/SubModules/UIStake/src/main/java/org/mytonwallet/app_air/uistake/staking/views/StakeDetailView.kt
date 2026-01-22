package org.mytonwallet.app_air.uistake.staking.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.View
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.drawable.HighlightGradientBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCounterLabel
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WLinearLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class StakeDetailView(
    context: Context,
    onWhySafeClick: (() -> Unit)? = null
) : WLinearLayout(context), WThemedView {

    private val apyRow: WView by lazy {
        val wView = WView(
            context,
            layoutParams = ConstraintLayout.LayoutParams(
                ConstraintLayout.LayoutParams.MATCH_PARENT,
                50.dp
            )
        )

        wView
    }

    private val apyStartLabel = WLabel(context).apply {
        text = LocaleController.getString("Current APY")
        setStyle(16f, WFont.Regular)
        setLineHeight(24f)
        setTextColor(WColor.SecondaryText.color)
        setPadding(0, 0, 0, 1.dp)
    }

    private val apyEndLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setLineHeight(24f)
        setTextColor(Color.WHITE)
        visibility = View.INVISIBLE

        setPaddingDp(6f, 1f, 6f, 3f)
    }

    private val earningRow: WView by lazy {
        val wView = WView(
            context, layoutParams = ConstraintLayout.LayoutParams(
                ConstraintLayout.LayoutParams.MATCH_PARENT,
                50.dp
            )
        )
        wView
    }

    private val earningStartLabel = WLabel(context).apply {
        layoutParams = ConstraintLayout.LayoutParams(
            ConstraintLayout.LayoutParams.MATCH_CONSTRAINT,
            ConstraintLayout.LayoutParams.WRAP_CONTENT
        )
        text = LocaleController.getString("Est. earning per year")
        setStyle(16f, WFont.Regular)
        setLineHeight(24f)
        setTextColor(WColor.SecondaryText.color)
        setPadding(0, 0, 0, 1.dp)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.MARQUEE
        isSelected = true
        isHorizontalFadingEdgeEnabled = true
    }

    private val earningEndLabel = WCounterLabel(context).apply {
        id = generateViewId()
        setStyle(16f, WFont.Medium)
        layoutParams = ConstraintLayout.LayoutParams(
            ConstraintLayout.LayoutParams.WRAP_CONTENT,
            ConstraintLayout.LayoutParams.WRAP_CONTENT
        )
        setGradientColor(
            arrayOf(
                WColor.EarnGradientLeft,
                WColor.EarnGradientRight
            )
        )
        setPadding(4.dp, 7.dp, 0, 0)
        visibility = INVISIBLE
    }

    private val whySafeRow: WView by lazy {
        val wView = WView(
            context, layoutParams = ConstraintLayout.LayoutParams(
                ConstraintLayout.LayoutParams.MATCH_PARENT,
                50.dp
            )
        )
        wView.addRippleEffect(WColor.SecondaryBackground.color)
        wView.setOnClickListener { onWhySafeClick?.invoke() }
        wView
    }

    private val whySafeStartLabel = WLabel(context).apply {
        text = LocaleController.getString("Why is staking safe?")
        setStyle(16f, WFont.Regular)
        setLineHeight(24f)
        setTextColor(WColor.Tint.color)
        setPadding(0, 5.dp, 0, 1.dp)
    }

    init {
        apyRow.addView(apyStartLabel)
        apyRow.addView(apyEndLabel)
        apyRow.setConstraints {
            toTop(apyStartLabel, 16f)
            toStart(apyStartLabel, 20f)
            toBottom(apyStartLabel, 16f)

            toTop(apyEndLabel, 16f)
            toEnd(apyEndLabel, 20f)
            toBottom(apyEndLabel, 16f)
        }

        earningRow.addView(earningStartLabel)
        earningRow.addView(earningEndLabel)
        earningRow.setConstraints {
            toTop(earningStartLabel, 16f)
            toStart(earningStartLabel, 20f)
            endToStart(earningStartLabel, earningEndLabel, 8f)
            toBottom(earningStartLabel, 16f)

            toTop(earningEndLabel, 16f)
            toEnd(earningEndLabel, 20f)
            toBottom(earningEndLabel, 16f)
        }

        whySafeRow.addView(whySafeStartLabel)
        whySafeRow.setConstraints {
            toTop(whySafeStartLabel, 16f)
            toStart(whySafeStartLabel, 20f)
            toBottom(whySafeStartLabel, 16f)
        }

        addView(apyRow)
        addView(earningRow)
        addView(whySafeRow)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
    }

    override fun updateTheme() {
        apyStartLabel.setTextColor(WColor.Tint.color)
        earningStartLabel.setTextColor(WColor.Tint.color)
        whySafeStartLabel.setTextColor(WColor.Tint.color)
        whySafeRow.addRippleEffect(WColor.SecondaryBackground.color)
    }

    fun setEarning(earningAmount: String) {
        earningEndLabel.setAmount(earningAmount)
        earningEndLabel.visibility = VISIBLE
    }

    @SuppressLint("SetTextI18n")
    fun setApy(apyAmount: String) {
        if (apyAmount.isBlank()) {
            apyEndLabel.text = ""
            apyEndLabel.visibility = GONE
            return
        }

        apyEndLabel.text = "$apyAmount%"
        apyEndLabel.background = HighlightGradientBackgroundDrawable(isHighlighted = true)
        apyEndLabel.visibility = VISIBLE
    }


}
