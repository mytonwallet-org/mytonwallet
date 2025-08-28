package org.mytonwallet.app_air.uitransaction.viewControllers

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.text.SpannableStringBuilder
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import android.view.Gravity
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

@SuppressLint("ViewConstructor")
class SwapHeaderView(
    context: Context,
    val transaction: MApiTransaction
) : WView(context, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)),
    WThemedView {
    private val sizeSpan = RelativeSizeSpan(28f / 36f)
    private val colorSpan = WForegroundColorSpan()

    private val tokenToSendIconView = WCustomImageView(context).apply {
        layoutParams = LayoutParams(80.dp, 80.dp)
        chainSize = 30.dp
        chainSizeGap = 2f.dp
    }

    private val tokenToReceiveIconView = WCustomImageView(context).apply {
        layoutParams = LayoutParams(80.dp, 80.dp)
        chainSize = 30.dp
        chainSizeGap = 2f.dp
    }

    private val iconView = AppCompatImageView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(24.dp, 24.dp)
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_24)
        scaleX = LocaleController.rtlMultiplier.toFloat()
    }

    private val tokenToSendTextView = WSensitiveDataContainer(
        WLabel(context),
        WSensitiveDataContainer.MaskConfig(12, 4, Gravity.CENTER, protectContentLayoutSize = false)
    ).apply {
        textAlignment = TEXT_ALIGNMENT_CENTER
        contentView.apply {
            typeface = WFont.NunitoExtraBold.typeface
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 28f)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        }
        layoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT)
    }

    private val tokenToReceiveTextView = WSensitiveDataContainer(
        WLabel(context),
        WSensitiveDataContainer.MaskConfig(16, 4, Gravity.CENTER, protectContentLayoutSize = false)
    ).apply {
        textAlignment = TEXT_ALIGNMENT_CENTER
        contentView.apply {
            typeface = WFont.NunitoExtraBold.typeface
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 44f)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 36f)
        }
        layoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT)
    }

    init {
        config()

        addView(tokenToSendIconView)
        addView(tokenToReceiveIconView)
        addView(iconView)
        addView(tokenToSendTextView)
        addView(tokenToReceiveTextView)

        setConstraints {
            toCenterX(iconView)
            centerYToCenterY(iconView, tokenToSendIconView)

            toTop(tokenToSendIconView)
            endToStart(tokenToSendIconView, iconView, 16f)

            toTop(tokenToReceiveIconView)
            startToEnd(tokenToReceiveIconView, iconView, 16f)

            topToBottom(tokenToSendTextView, tokenToReceiveIconView, 22f)
            toCenterX(tokenToSendTextView, 8f)

            topToBottom(tokenToReceiveTextView, tokenToSendTextView, 6f)
            toCenterX(tokenToReceiveTextView, 8f)
        }

        updateTheme()
    }

    fun config() {
        if (transaction !is MApiTransaction.Swap)
            throw Exception()
        if (transaction.fromToken != null) {
            tokenToSendIconView.setAsset(
                transaction.fromToken!!,
                !transaction.fromToken!!.isBlockchainNative
            )

            val sendAmount = transaction.fromAmount.toString(
                decimals = transaction.fromToken!!.decimals,
                currency = transaction.fromToken!!.symbol,
                currencyDecimals = transaction.fromToken!!.decimals,
                smartDecimals = true,
                showPositiveSign = false,
                forceCurrencyToRight = true
            )
            tokenToSendTextView.contentView.text = sendAmount.let {
                val ssb = SpannableStringBuilder("-$it")
                CoinUtils.setSpanToFractionalPart(ssb, colorSpan)
                ssb
            }
        } else {
            tokenToSendIconView.clear()
        }
        if (transaction.toToken != null) {
            tokenToReceiveIconView.setAsset(
                transaction.toToken!!,
                !transaction.toToken!!.isBlockchainNative
            )

            val receiveAmount = transaction.toAmount.toDouble().toString(
                decimals = transaction.toToken!!.decimals,
                currency = transaction.toToken!!.symbol,
                currencyDecimals = transaction.toToken!!.decimals,
                smartDecimals = true,
                showPositiveSign = true,
                forceCurrencyToRight = true
            )
            tokenToReceiveTextView.contentView.text = receiveAmount.let {
                val ssb = SpannableStringBuilder(it)
                CoinUtils.setSpanToFractionalPart(ssb, sizeSpan)
                CoinUtils.setSpanToFractionalPart(ssb, colorSpan)
                ssb
            }
        } else {
            tokenToReceiveIconView.clear()
        }
    }

    override fun updateTheme() {
        colorSpan.color = WColor.SecondaryText.color
        tokenToSendTextView.contentView.setTextColor(WColor.PrimaryText.color)
        tokenToReceiveTextView.contentView.setTextColor(WColor.PrimaryText.color)
        iconView.imageTintList = ColorStateList.valueOf(WColor.SecondaryText.color)
    }

}
