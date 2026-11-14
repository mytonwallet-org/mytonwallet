package org.mytonwallet.app_air.uifutures.viewControllers.futuresActivity

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import kotlin.math.abs
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsSide

@SuppressLint("ViewConstructor")
class FuturesActivityHeaderView(
    context: Context,
    asset: MApiPerpsListedAsset?,
    private val side: MApiPerpsSide,
    badgeText: String,
    private val amount: Double,
    private val previousAmount: Double? = null,
    private val showsSign: Boolean = false,
    private val amountColor: WColor? = null,
    isSensitiveData: Boolean = false
) : WView(context, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)),
    WThemedView {

    private val iconView = WCustomImageView(context)

    private val tagLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        setSingleLine()
        gravity = Gravity.CENTER
        setPadding(TAG_HORIZONTAL_PADDING.dp, 0, TAG_HORIZONTAL_PADDING.dp, 0)
        text = badgeText
    }

    private val amountLabel = WLabel(context).apply {
        setStyle(AMOUNT_SIZE, WFont.Balance)
        setSingleLine()
    }

    private val amountView = WSensitiveDataContainer(
        amountLabel,
        WSensitiveDataContainer.MaskConfig(16, 4, Gravity.CENTER, protectContentLayoutSize = false)
    ).apply {
        id = generateViewId()
        this.isSensitiveData = isSensitiveData
    }

    init {
        addView(iconView, LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp))
        addView(tagLabel, LayoutParams(WRAP_CONTENT, TAG_HEIGHT.dp))
        addView(amountView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toTop(iconView)
            toCenterX(iconView)
            topToBottom(tagLabel, iconView, TAG_OVERLAP - TAG_HEIGHT.toFloat())
            toCenterX(tagLabel)
            topToBottom(amountView, iconView, 16f)
            toCenterX(amountView)
            toBottom(amountView)
        }
        asset?.image?.let { iconView.set(Content.ofUrl(it, asset.isRwaStock)) }
        updateTheme()
    }

    override fun updateTheme() {
        val sideColor = if (side == MApiPerpsSide.LONG) WColor.Green else WColor.Red
        tagLabel.setTextColor(Color.WHITE)
        tagLabel.setBackgroundColor(
            sideColor.color,
            TAG_HEIGHT.dp / 2f,
            TAG_HEIGHT.dp / 2f,
            strokeColor = WColor.Background.color,
            strokeWidth = TAG_BORDER.dp
        )
        amountLabel.setTextColor((amountColor ?: WColor.PrimaryText).color)
        amountLabel.text = amountText()
    }

    private fun amountText(): CharSequence {
        val previousAmount = previousAmount ?: return balanceText(amount)
        return SpannableStringBuilder()
            .append(balanceText(previousAmount))
            .append(
                ARROW_PLACEHOLDER,
                VerticalImageSpan(
                    arrowDrawable(),
                    shouldFlipForRTL = LocaleController.isRTL,
                    startPadding = 14.dp,
                    endPadding = 12.dp,
                    isRTL = LocaleController.isRTL
                ),
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            .append(balanceText(amount))
    }

    private fun arrowDrawable() =
        context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_26)!!
            .mutate()
            .apply {
                setTint(WColor.SecondaryText.color)
                setBounds(0, 0, intrinsicWidth, intrinsicHeight)
            }

    private fun balanceText(value: Double): CharSequence {
        val sign = when {
            !showsSign || value == 0.0 -> ""
            value > 0 -> "+"
            else -> "−"
        }
        val text = sign + abs(value).toUsdString()
        val fractionStart = text.indexOf('.').takeIf { it >= 0 } ?: text.length
        return SpannableString(text).apply {
            if (amountColor == null) {
                val secondary = WColor.SecondaryText.color
                setSpan(
                    ForegroundColorSpan(secondary),
                    0,
                    sign.length + 1,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                setSpan(
                    ForegroundColorSpan(secondary),
                    fractionStart,
                    text.length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            if (fractionStart < text.length) {
                setSpan(
                    RelativeSizeSpan(DECIMALS_SIZE / AMOUNT_SIZE),
                    fractionStart,
                    text.length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        }
    }

    private companion object {
        const val ICON_SIZE = 80
        const val TAG_HEIGHT = 28
        const val TAG_BORDER = 2
        const val TAG_HORIZONTAL_PADDING = 8
        const val TAG_OVERLAP = 12f
        const val AMOUNT_SIZE = 36f
        const val DECIMALS_SIZE = 28f
        const val ARROW_PLACEHOLDER = "→"
    }
}
