package org.mytonwallet.app_air.uistake.confirm

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.style.RelativeSizeSpan
import android.util.AttributeSet
import android.util.TypedValue
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

class ConfirmStakingHeaderView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0,
) : WCell(context, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)),
    WThemedView {

    private val sizeSpan = RelativeSizeSpan(28f / 36f)
    private val colorSpan = WForegroundColorSpan()

    private val tokenIconView = WCustomImageView(context).apply {
        layoutParams = LayoutParams(80.dp, 80.dp)
        chainSize = 30.dp
        chainSizeGap = 2f.dp
    }

    private val amountTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, 44.dp)
        textAlignment = TEXT_ALIGNMENT_CENTER
        typeface = WFont.NunitoExtraBold.typeface

        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 44f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 36f)
    }

    private val messageTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, 24.dp)
        textAlignment = TEXT_ALIGNMENT_CENTER
        typeface = WFont.Regular.typeface

        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
    }

    override fun setupViews() {
        super.setupViews()
        setPadding(20.dp, paddingTop, 20.dp, 24.dp)

        addView(tokenIconView)
        addView(amountTextView)
        addView(messageTextView)

        setConstraints {
            toCenterX(tokenIconView)
            toTop(tokenIconView, 24f)

            topToBottom(amountTextView, tokenIconView, 20.5f)
            toCenterX(amountTextView)

            topToBottom(messageTextView, amountTextView, 15.5f)
            toCenterX(messageTextView)
            // toBottom(messageTextView, 24f)
        }

        updateTheme()
    }

    fun config(
        token: MToken,
        amountInCrypto: BigInteger,
        showPositiveSignForAmount: Boolean,
        messageString: String
    ) {
        tokenIconView.set(Content.of(token, true))

        val amount = amountInCrypto.toString(
            decimals = token.decimals,
            currency = TokenStore.getToken(token.unstakedSlug)?.symbol ?: "",
            currencyDecimals = token.decimals,
            showPositiveSign = showPositiveSignForAmount
        )
        amountTextView.text = amount.let {
            val ssb = SpannableStringBuilder(it)
            CoinUtils.setSpanToFractionalPart(ssb, sizeSpan)
            CoinUtils.setSpanToSymbolPart(ssb, colorSpan)
            ssb
        }

        messageTextView.text = messageString
    }

    override fun updateTheme() {
        colorSpan.color = WColor.SecondaryText.color
        amountTextView.setTextColor(WColor.PrimaryText.color)
        messageTextView.setTextColor(WColor.PrimaryText.color)
    }

}
