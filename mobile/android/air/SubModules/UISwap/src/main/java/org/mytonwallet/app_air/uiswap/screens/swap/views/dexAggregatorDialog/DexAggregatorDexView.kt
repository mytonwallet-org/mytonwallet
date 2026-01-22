package org.mytonwallet.app_air.uiswap.screens.swap.views.dexAggregatorDialog

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Shader
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.uicomponents.drawable.HighlightGradientBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapDexLabel

@SuppressLint("ViewConstructor")
class DexAggregatorDexView(
    context: Context,
    dex: MApiSwapDexLabel,
) : WView(context), WThemedView {

    private val iconView = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageResource(dex.icon)
    }

    private val nameLabel = WLabel(context).apply {
        setStyle(17f, WFont.SemiBold)
        text = dex.displayName
    }

    private val amountLabel = WLabel(context).apply {
        setStyle(17f, WFont.SemiBold)
        textAlignment = TEXT_ALIGNMENT_TEXT_START
    }

    private val rateLabel = WLabel(context).apply {
        setStyle(12f, WFont.SemiBold)
        textAlignment = TEXT_ALIGNMENT_TEXT_START
    }

    private val badgeLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(12f, WFont.Medium)
            setPadding(2.dp, 0, 2.dp, 2.dp)
            text = LocaleController.getString("Best")
            visibility = GONE
        }
    }

    private val contentView = WView(context).apply {
        clipChildren = false

        addView(iconView, LayoutParams(32.dp, 32.dp))
        addView(nameLabel)
        addView(amountLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(rateLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(badgeLabel)

        setConstraints {
            toTop(iconView, 8f)
            toStart(iconView, 8f)
            centerYToCenterY(nameLabel, iconView)
            startToEnd(nameLabel, iconView, 8f)
            topToBottom(amountLabel, iconView, 12f)
            toCenterX(amountLabel, 8f)
            topToBottom(rateLabel, amountLabel, 4f)
            toCenterX(rateLabel, 8f)
            toBottom(rateLabel, 8f)
            toTop(badgeLabel, -3f)
            toEnd(badgeLabel, -3f)
        }
    }

    var isBest: Boolean = false
        set(value) {
            field = value
            badgeLabel.visibility = if (isBest) VISIBLE else GONE
        }

    var isSelectedDex: Boolean = false
        set(value) {
            field = value
            updateAmountColor()
            updateBackgroundColor()
        }

    override fun setupViews() {
        super.setupViews()

        clipChildren = false
        addView(contentView)
        setConstraints {
            allEdges(contentView, 1f)
        }

        updateTheme()
    }

    override fun updateTheme() {
        contentView.setBackgroundColor(WColor.Background.color, 12f.dp)
        nameLabel.setTextColor(WColor.PrimaryText.color)
        rateLabel.setTextColor(WColor.SecondaryText.color)
        badgeLabel.setBackgroundColor(WColor.Green.color, 5f.dp)
        badgeLabel.setTextColor(Color.WHITE)
        updateAmountColor()
        updateBackgroundColor()
    }

    private fun updateAmountColor() {
        if (isSelectedDex) {
            if (isBest) {
                nameLabel.measure(0, 0)
                val shader = LinearGradient(
                    0f, 0f,
                    nameLabel.measuredWidth.toFloat(), 0f,
                    intArrayOf(
                        WColor.EarnGradientLeft.color,
                        WColor.EarnGradientRight.color
                    ),
                    null, Shader.TileMode.CLAMP
                )

                amountLabel.paint.shader = shader
            } else {
                amountLabel.paint.shader = null
                amountLabel.setTextColor(WColor.Tint.color)
            }
        } else {
            amountLabel.paint.shader = null
            amountLabel.setTextColor(WColor.PrimaryText.color.colorWithAlpha(230))
        }
        amountLabel.invalidate()
    }

    private fun updateBackgroundColor() {
        if (isSelectedDex) {
            if (isBest) {
                background = HighlightGradientBackgroundDrawable(
                    isHighlighted = true,
                    cornerRadius = 12f.dp,
                    reversedColors = true
                )
            } else {
                setBackgroundColor(WColor.Tint.color, 12f.dp)
            }
        } else {
            setBackgroundColor(WColor.SecondaryBackground.color, 12f.dp)
        }
    }

    fun fillValues(amount: String, rate: String) {
        amountLabel.text = amount
        rateLabel.text = rate
    }

}
