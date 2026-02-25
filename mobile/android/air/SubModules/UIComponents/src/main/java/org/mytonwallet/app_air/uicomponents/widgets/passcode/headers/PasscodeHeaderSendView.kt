package org.mytonwallet.app_air.uicomponents.widgets.passcode.headers

import android.annotation.SuppressLint
import android.graphics.Color
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import android.view.Gravity
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class PasscodeHeaderSendView(
    val viewController: WeakReference<WViewController>,
    val availableHeight: Int
) : LinearLayout(viewController.get()!!.context) {

    private val tokenToSendIconView = WCustomImageView(context)

    private val tokenToSendTextView = WLabel(context).apply {
        textAlignment = TEXT_ALIGNMENT_CENTER
        typeface = WFont.NunitoExtraBold.typeface
        setTextColor(WColor.PrimaryText)
    }

    private val sendingTextView = WLabel(context).apply {
        textAlignment = TEXT_ALIGNMENT_CENTER
        typeface = WFont.Regular.typeface
        setTextColor(WColor.PrimaryText)
        setPaddingDp(8, 2, 8, 2)
    }

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER

        addView(tokenToSendIconView)
        addView(tokenToSendTextView)
        addView(sendingTextView)

        adjustLayoutToFit()
    }

    private fun adjustLayoutToFit() {
        // Original dimensions
        val imageSize = 80.dp
        val imageChainSize = 30.dp
        val imageChainGap = 2f.dp

        val titleSizeSp = 36f
        val titleLineHeightDp = 44.dp
        val titleTopMargin = 24.dp

        val subtitleSizeSp = 16f
        val subtitleLineHeightDp = 24.dp
        val subtitleTopMargin = 10.dp

        val paddingHorizontal = 20.dp
        val paddingVertical = 24.dp
        val totalVerticalPadding = paddingVertical * 2 - 2.dp

        // Total desired height
        val desiredHeight = imageSize + titleTopMargin + titleLineHeightDp +
            subtitleTopMargin + subtitleLineHeightDp + totalVerticalPadding

        val scale = if (desiredHeight > availableHeight) {
            availableHeight.toFloat() / desiredHeight.toFloat()
        } else 1f

        // Scaled values
        val scaledImageSize = (imageSize * scale).toInt()
        val scaledChainSize = (imageChainSize * scale).toInt()
        val scaledChainGap = imageChainGap * scale

        val scaledTitleSizePx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, titleSizeSp * scale, resources.displayMetrics
        )
        val scaledTitleLineHeight = (titleLineHeightDp * scale).toInt()
        val scaledTitleTopMargin = (titleTopMargin * scale).toInt()

        val scaledSubtitleSizePx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, subtitleSizeSp * scale, resources.displayMetrics
        )
        val scaledSubtitleLineHeight = (subtitleLineHeightDp * scale).toInt()
        val scaledSubtitleTopMargin = (subtitleTopMargin * scale).toInt()

        val scaledPaddingVertical = (paddingVertical * scale).toInt()

        setPadding(
            paddingHorizontal,
            scaledPaddingVertical,
            paddingHorizontal,
            scaledPaddingVertical
        )

        // Icon
        tokenToSendIconView.layoutParams = LayoutParams(scaledImageSize, scaledImageSize).apply {
            gravity = Gravity.CENTER
        }
        tokenToSendIconView.chainSize = scaledChainSize
        tokenToSendIconView.chainSizeGap = scaledChainGap

        // Title
        tokenToSendTextView.setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledTitleSizePx)
        tokenToSendTextView.setLineHeight(
            TypedValue.COMPLEX_UNIT_PX,
            scaledTitleLineHeight.toFloat()
        )
        tokenToSendTextView.layoutParams = LayoutParams(
            LayoutParams.MATCH_PARENT,
            scaledTitleLineHeight
        ).apply {
            topMargin = scaledTitleTopMargin
        }

        // Subtitle
        sendingTextView.setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledSubtitleSizePx)
        sendingTextView.setLineHeight(
            TypedValue.COMPLEX_UNIT_PX,
            scaledSubtitleLineHeight.toFloat()
        )
        sendingTextView.layoutParams = LayoutParams(
            LayoutParams.WRAP_CONTENT,
            scaledSubtitleLineHeight + 4.dp
        ).apply {
            topMargin = scaledSubtitleTopMargin
        }
    }

    fun configSendingToken(
        token: ApiTokenWithPrice,
        amountString: String,
        network: MBlockchainNetwork,
        resolvedAddress: String?
    ) {
        val amount = SpannableStringBuilder(amountString)
        CoinUtils.setSpanToFractionalPart(amount, WForegroundColorSpan(WColor.SecondaryText))
        CoinUtils.setSpanToFractionalPart(amount, RelativeSizeSpan(28f / 36f))

        val a = resolvedAddress?.formatStartEndAddress() ?: ""
        val sendingToText = LocaleController.getString("Send to")
        val address = SpannableStringBuilder(sendingToText).apply {
            append(" $a")
            AddressPopupHelpers.configSpannableAddress(
                viewController = viewController,
                title = null,
                spannedString = this,
                startIndex = length - a.length,
                length = a.length,
                network = network,
                blockchain = token.mBlockchain,
                address = resolvedAddress ?: "",
                popupXOffset = 0,
                centerHorizontally = true,
                showTemporaryViewOption = false
            )
            styleDots()
            setSpan(
                WForegroundColorSpan(WColor.SecondaryText),
                length - a.length - 1,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }

        config(Content.of(token, AccountStore.activeAccount?.isMultichain == true), amount, address)
    }

    fun config(
        content: Content,
        title: CharSequence,
        subtitle: CharSequence,
        rounding: Content.Rounding? = null
    ) {
        rounding.let {
            tokenToSendIconView.defaultRounding = Content.Rounding.Radius(12f.dp)
        }
        tokenToSendIconView.set(content)
        tokenToSendTextView.text = title
        sendingTextView.text = subtitle
        sendingTextView.movementMethod =
            ExtraHitLinkMovementMethod(sendingTextView.paddingLeft, sendingTextView.paddingTop)
        sendingTextView.highlightColor = Color.TRANSPARENT
    }

    fun setSubtitleColor(color: WColor) {
        sendingTextView.setTextColor(color)
    }
}
