package org.mytonwallet.app_air.uiswap.views

import android.content.Context
import android.content.res.ColorStateList
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import androidx.appcompat.widget.AppCompatImageView
import androidx.appcompat.widget.AppCompatTextView
import java.math.BigInteger
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

class SwapConfirmView(context: Context) :
    WCell(context, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)),
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

    private val tokenToSendTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        textAlignment = TEXT_ALIGNMENT_CENTER
        typeface = WFont.Balance.typeface
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 28f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.MARQUEE
        isSelected = true
        isHorizontalFadingEdgeEnabled = true
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, lineHeight)
    }

    private val batchNoticeTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        visibility = GONE
        textAlignment = TEXT_ALIGNMENT_CENTER
        typeface = WFont.Medium.typeface
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 18f)
        setPaddingDp(12, 8, 12, 8)
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
    }

    private val tokenToReceiveTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        textAlignment = TEXT_ALIGNMENT_CENTER
        typeface = WFont.Balance.typeface
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 44f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 36f)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.MARQUEE
        isSelected = true
        isHorizontalFadingEdgeEnabled = true
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, lineHeight)
    }

    init {
        setPaddingDp(20, 16, 20, 26)

        addView(tokenToSendIconView)
        addView(iconView)
        addView(tokenToReceiveIconView)
        addView(tokenToSendTextView)
        addView(tokenToReceiveTextView)
        addView(batchNoticeTextView)

        setConstraints {
            toCenterX(iconView)
            centerYToCenterY(iconView, tokenToSendIconView)

            toTop(tokenToSendIconView)
            endToStart(tokenToSendIconView, iconView, 16f)

            toTop(tokenToReceiveIconView)
            startToEnd(tokenToReceiveIconView, iconView, 16f)

            topToBottom(tokenToSendTextView, tokenToReceiveIconView, 22f)
            toCenterX(tokenToSendTextView)

            topToBottom(tokenToReceiveTextView, tokenToSendTextView, 8f)
            toCenterX(tokenToReceiveTextView)

            topToBottom(batchNoticeTextView, tokenToReceiveTextView, 16f)
            toCenterX(batchNoticeTextView)
            toBottom(batchNoticeTextView)
        }

        updateTheme()
    }

    fun setBatchNotice(notice: CharSequence?) {
        if (notice.isNullOrBlank()) {
            batchNoticeTextView.visibility = GONE
            batchNoticeTextView.text = null
            return
        }
        batchNoticeTextView.text = notice
        batchNoticeTextView.visibility = VISIBLE
    }

    fun config(
        fromToken: IApiToken,
        toToken: IApiToken,
        fromAmount: BigInteger?,
        toAmount: BigInteger?
    ) {
        tokenToSendIconView.set(Content.of(fromToken, showChain = true))
        tokenToReceiveIconView.set(Content.of(toToken, showChain = true))

        val sendAmount =
            fromAmount?.negate()?.toString(
                decimals = fromToken.decimals,
                currency = fromToken.symbol ?: "",
                currencyDecimals = fromAmount.smartDecimalsCount(fromToken.decimals),
                showPositiveSign = false
            )
        tokenToSendTextView.text = sendAmount?.let {
            val ssb = SpannableStringBuilder(it)
            CoinUtils.setSpanToFractionalPart(ssb, colorSpan)
            ssb
        }
        val receiveAmount = toAmount?.toString(
            decimals = toToken.decimals,
            currency = toToken.symbol ?: "",
            currencyDecimals = toAmount.smartDecimalsCount(toToken.decimals),
            showPositiveSign = true
        )
        tokenToReceiveTextView.text = receiveAmount?.let {
            val ssb = SpannableStringBuilder(it)
            CoinUtils.setSpanToFractionalPart(ssb, sizeSpan)
            CoinUtils.setSpanToFractionalPart(ssb, colorSpan)
            ssb
        }
    }

    override fun updateTheme() {
        colorSpan.color = WColor.SecondaryText.color
        tokenToSendTextView.setTextColor(WColor.PrimaryText.color)
        tokenToReceiveTextView.setTextColor(WColor.PrimaryText.color)
        iconView.imageTintList = ColorStateList.valueOf(WColor.SecondaryText.color)
        batchNoticeTextView.setTextColor(WColor.SecondaryText.color)
        batchNoticeTextView.setBackgroundColor(
            WColor.SecondaryBackground.color.colorWithAlpha(255),
            12f.dp,
            true
        )
    }
}
