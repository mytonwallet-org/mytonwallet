package org.mytonwallet.app_air.uicomponents.widgets.passcode.headers

import android.annotation.SuppressLint
import android.graphics.Color
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import java.lang.ref.WeakReference
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.AccountAvatarDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
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
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore

@SuppressLint("ViewConstructor")
class PasscodeHeaderSendView(
    val viewController: WeakReference<WViewController>,
    val availableHeight: Int
) : LinearLayout(viewController.get()!!.context) {

    private val tokenToSendIconView = WCustomImageView(context)

    private val tokenToSendTextView = WLabel(context).apply {
        textAlignment = TEXT_ALIGNMENT_CENTER
        typeface = WFont.Balance.typeface
        setTextColor(WColor.PrimaryText)
        includeFontPadding = false
        maxLines = 2
        ellipsize = TextUtils.TruncateAt.END
    }

    private val sendingTextView = WLabel(context).apply {
        textAlignment = TEXT_ALIGNMENT_CENTER
        gravity = Gravity.CENTER
        typeface = WFont.Regular.typeface
        setTextColor(WColor.PrimaryText)
        setPaddingDp(8, 2, 8, 2)
        includeFontPadding = false
    }

    private var titleTopMarginWithIcon = 0
    private var baseVerticalPadding = 0
    private var baseBottomPadding = 0
    private var customIconView: View? = null

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER

        addView(tokenToSendIconView)
        addView(tokenToSendTextView)
        addView(sendingTextView)

        adjustLayoutToFit()
    }

    private fun adjustLayoutToFit(
        titleTopMargin: Int = DEFAULT_TITLE_TOP_MARGIN_DP.dp,
        subtitleTopMargin: Int = DEFAULT_SUBTITLE_TOP_MARGIN_DP.dp,
        paddingBottom: Int = DEFAULT_VERTICAL_PADDING_DP.dp
    ) {
        // Original dimensions
        val imageSize = 80.dp
        val imageChainSize = 30.dp
        val imageChainGap = 2f.dp

        val titleSizeSp = TITLE_SIZE_SP
        val titleLineHeightDp = 44.dp

        val subtitleSizeSp = 16f
        val subtitleLineHeightDp = 24.dp

        val paddingHorizontal = 20.dp
        val paddingVertical = DEFAULT_VERTICAL_PADDING_DP.dp
        val totalVerticalPadding = paddingVertical + paddingBottom - 2.dp

        // Total desired height
        val desiredHeight = imageSize + titleTopMargin + titleLineHeightDp +
            subtitleTopMargin + subtitleLineHeightDp + totalVerticalPadding

        val scale = if (desiredHeight > availableHeight) {
            availableHeight.toFloat() / desiredHeight.toFloat()
        } else {
            1f
        }

        // Scaled values
        val scaledImageSize = (imageSize * scale).toInt()
        val scaledChainSize = (imageChainSize * scale).toInt()
        val scaledChainGap = imageChainGap * scale

        val scaledTitleSizePx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            titleSizeSp * scale,
            resources.displayMetrics
        )
        val scaledTitleLineHeight = (titleLineHeightDp * scale).toInt()
        val scaledTitleTopMargin = (titleTopMargin * scale).toInt()

        val scaledSubtitleSizePx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            subtitleSizeSp * scale,
            resources.displayMetrics
        )
        val scaledSubtitleLineHeight = (subtitleLineHeightDp * scale).toInt()
        val scaledSubtitleTopMargin = (subtitleTopMargin * scale).toInt()

        val scaledPaddingVertical = (paddingVertical * scale).toInt()
        baseVerticalPadding = scaledPaddingVertical
        baseBottomPadding = (paddingBottom * scale).toInt()

        setPadding(
            paddingHorizontal,
            scaledPaddingVertical,
            paddingHorizontal,
            baseBottomPadding
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
        titleTopMarginWithIcon = scaledTitleTopMargin
        tokenToSendTextView.layoutParams = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT
        ).apply {
            topMargin = scaledTitleTopMargin
        }

        // Subtitle
        sendingTextView.setTextSize(TypedValue.COMPLEX_UNIT_PX, scaledSubtitleSizePx)
        val subtitleFontHeight = sendingTextView.paint.fontMetrics.run { descent - ascent }
        val subtitleBoxShift = ((scaledSubtitleLineHeight - subtitleFontHeight) / 2f).roundToInt()
        sendingTextView.layoutParams = LayoutParams(
            LayoutParams.WRAP_CONTENT,
            scaledSubtitleLineHeight + 4.dp
        ).apply {
            topMargin = scaledSubtitleTopMargin - subtitleBoxShift
            bottomMargin = subtitleBoxShift
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

        val address = buildSendToSubtitle(
            LocaleController.getString("Send to"),
            resolvedAddress,
            token.mBlockchain,
            network
        )

        config(Content.of(token, AccountStore.activeAccount?.isMultichain == true), amount, address)
    }

    fun buildSendToSubtitle(
        prefix: String,
        resolvedAddress: String?,
        blockchain: MBlockchain?,
        network: MBlockchainNetwork
    ): CharSequence {
        val knownAddress = resolvedAddress?.let { AddressStore.getAddress(it, blockchain?.name) }
        val a = knownAddress?.name ?: resolvedAddress?.formatStartEndAddress() ?: ""
        return SpannableStringBuilder(prefix).apply {
            append(" ")
            if (knownAddress != null) {
                val avatarSize = (sendingTextView.textSize * AVATAR_SIZE_EM).roundToInt()
                val avatar = AccountAvatarDrawable(knownAddress.name, knownAddress.address).apply {
                    setBounds(0, 0, avatarSize, avatarSize)
                }
                append(
                    " ",
                    VerticalImageSpan(
                        avatar,
                        startPadding = 2.dp,
                        endPadding = 4.dp,
                        verticalOffsetEm = FontManager.inlineIconVerticalOffsetEm -
                            0.5f.dp / sendingTextView.textSize,
                        isRTL = LocaleController.isRTL
                    ),
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            append(a)
            AddressPopupHelpers.configSpannableAddress(
                viewController = viewController,
                title = null,
                spannedString = this,
                startIndex = length - a.length,
                length = a.length,
                network = network,
                blockchain = blockchain,
                address = resolvedAddress ?: "",
                popupXOffset = 0,
                centerHorizontally = true,
                showTemporaryViewOption = false,
                showExpandIcon = knownAddress == null
            )
            if (knownAddress == null) styleDots()
            setSpan(
                WForegroundColorSpan(WColor.SecondaryText),
                prefix.length,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
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
        val hasIcon = content.image !is Content.Image.Empty
        customIconView?.let { removeView(it) }
        customIconView = null
        tokenToSendIconView.visibility = if (hasIcon) VISIBLE else GONE
        if (hasIcon) tokenToSendIconView.set(content)
        applyTexts(hasIcon, title, subtitle)
    }

    fun config(
        iconView: View,
        title: CharSequence,
        subtitle: CharSequence,
        iconVerticalInset: Int = 0,
        iconVerticalOffset: Int = 0
    ) {
        customIconView?.let { removeView(it) }
        customIconView = iconView
        tokenToSendIconView.visibility = GONE
        adjustLayoutToFit(
            titleTopMargin = CUSTOM_ICON_TITLE_TOP_MARGIN_DP.dp,
            subtitleTopMargin = CUSTOM_ICON_SUBTITLE_TOP_MARGIN_DP.dp,
            paddingBottom = CUSTOM_ICON_BOTTOM_PADDING_DP.dp
        )
        clipChildren = false
        clipToPadding = false
        addView(
            iconView,
            0,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = iconVerticalOffset - iconVerticalInset
                bottomMargin = -iconVerticalOffset - iconVerticalInset
            }
        )
        applyTexts(hasIcon = true, title, subtitle)
    }

    private fun applyTexts(hasIcon: Boolean, title: CharSequence, subtitle: CharSequence) {
        val extraPadding = if (hasIcon) 0 else 20.dp
        setPadding(
            paddingLeft,
            baseVerticalPadding + extraPadding,
            paddingRight,
            baseBottomPadding + extraPadding
        )
        (tokenToSendTextView.layoutParams as? LayoutParams)?.let {
            it.topMargin = if (hasIcon) titleTopMarginWithIcon else 0
            tokenToSendTextView.layoutParams = it
        }
        tokenToSendTextView.text = title
        sendingTextView.text = subtitle
        sendingTextView.movementMethod =
            ExtraHitLinkMovementMethod(sendingTextView.paddingLeft, sendingTextView.paddingTop)
        sendingTextView.highlightColor = Color.TRANSPARENT
    }

    fun setSubtitleColor(color: WColor) {
        sendingTextView.setTextColor(color)
    }

    companion object {
        private const val AVATAR_SIZE_EM = 18f / 16f
        private const val DEFAULT_TITLE_TOP_MARGIN_DP = 28
        private const val CUSTOM_ICON_TITLE_TOP_MARGIN_DP = 28
        private const val DEFAULT_SUBTITLE_TOP_MARGIN_DP = 10
        private const val CUSTOM_ICON_SUBTITLE_TOP_MARGIN_DP = 15
        private const val DEFAULT_VERTICAL_PADDING_DP = 24
        private const val CUSTOM_ICON_BOTTOM_PADDING_DP = 27
        const val TITLE_SIZE_SP = 36f
    }
}
