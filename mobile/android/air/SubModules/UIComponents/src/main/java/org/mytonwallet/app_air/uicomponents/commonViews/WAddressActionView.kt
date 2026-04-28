package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.text.Layout
import android.text.SpannableStringBuilder
import android.util.TypedValue
import android.view.ViewGroup
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setSizeBounds
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.WORD_JOIN
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.replaceSpacesWithNbsp
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcontext.utils.lerpColor
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import kotlin.math.roundToInt

class WAddressActionView(context: Context) : WLabel(context) {
    data class Data(
        val address: String,
        val chain: String,
        val addressName: String? = null,
    )

    private val addressRippleDrawable = WRippleDrawable.create(12f.dp)

    private var data: Data? = null
    private var addressSpans: List<WTypefaceSpan> = emptyList()
    private var accentFadeProgress: Float = 0f

    var onTap: ((WAddressActionView, Data) -> Unit)? = null

    init {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        setStyle(adaptiveFontSize(), WFont.Regular)
        setTextColor(WColor.SecondaryText)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        letterSpacing = -0.015f
        //noinspection WrongConstant
        breakStrategy = Layout.BREAK_STRATEGY_SIMPLE
        hyphenationFrequency = Layout.HYPHENATION_FREQUENCY_NONE
        setPaddingDp(8, 4, 8, 4)
        foreground = addressRippleDrawable

        setOnClickListener {
            data?.let { data -> onTap?.invoke(this, data) }
        }
        setOnLongClickListener {
            val data = data ?: return@setOnLongClickListener false
            val blockchain = MBlockchain.valueOfOrNull(data.chain)
                ?: return@setOnLongClickListener false
            AddressPopupHelpers.copyAddress(context, data.address, blockchain)
            true
        }
    }

    fun configure(data: Data) {
        this.data = data
        updateContent()
    }

    fun setAccentFadeProgress(progress: Float) {
        accentFadeProgress = progress
        updateAddressSpans()
    }

    override fun updateTheme() {
        super.updateTheme()
        addressRippleDrawable.rippleColor = WColor.SubtitleText.color.colorWithAlpha(25)
        updateContent()
    }

    private fun updateContent() {
        val data = data ?: return
        val blockchain = MBlockchain.valueOfOrNull(data.chain)
        val chainIconDrawable = blockchain?.symbolIconPadded?.let { symbol ->
            context.getDrawableCompat(symbol)?.mutate()
        }

        val accentSpans = mutableListOf<WTypefaceSpan>()
        val addressText = buildSpannedString {
            if (chainIconDrawable != null) {
                with(chainIconDrawable) {
                    setTint(WColor.SecondaryText.color)
                    setSizeBounds(16.dp, 16.dp)
                }
                inSpans(
                    VerticalImageSpan(
                        chainIconDrawable,
                        endPadding = 2.dp,
                        verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                    )
                ) { append(" ") }
                append(WORD_JOIN)
            }

            if (data.addressName != null) {
                inSpans(WTypefaceSpan(WFont.Medium, WColor.PrimaryText)) {
                    append(data.addressName)
                }
                append(" · ")
                append(data.address.formatStartEndAddress(6, 6)).styleDots()
            } else {
                appendStyledAddress(data.address, accentSpans)
            }

            val expandDrawable = context.getDrawableCompat(
                org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14
            )?.mutate()?.apply {
                setTint(WColor.SecondaryText.color)
                alpha = 204
                setSizeBounds(7.dp, 14.dp)
            }

            if (expandDrawable != null) {
                append(WORD_JOIN)
                inSpans(
                    VerticalImageSpan(
                        expandDrawable,
                        startPadding = 4.5f.dp.roundToInt(),
                        verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                    )
                ) { append(" ") }
            }
        }

        addressSpans = accentSpans
        text = addressText.replaceSpacesWithNbsp()
        updateAddressSpans()
    }

    private fun SpannableStringBuilder.appendStyledAddress(
        address: String,
        accentSpans: MutableList<WTypefaceSpan>
    ) {
        if (address.length < 12) {
            append(address)
            return
        }

        val prefix = address.take(6)
        val middle = address.substring(6, address.length - 6)
        val suffix = address.takeLast(6)

        inSpans(WTypefaceSpan(WFont.Medium, WColor.PrimaryText).also(accentSpans::add)) {
            append(prefix)
        }
        append(middle)
        inSpans(WTypefaceSpan(WFont.Medium, WColor.PrimaryText).also(accentSpans::add)) {
            append(suffix)
        }
    }

    private fun updateAddressSpans() {
        if (addressSpans.isEmpty()) {
            return
        }
        val dismissAddressHighlightColor = WColor.PrimaryText.color
        val presentAddressHighlightColor = WColor.SecondaryText.color
        val addressHighlightColor = lerpColor(
            dismissAddressHighlightColor,
            presentAddressHighlightColor,
            WInterpolator.emphasized.getInterpolation(accentFadeProgress)
        )
        addressSpans.forEach { it.foregroundColor = addressHighlightColor }
        invalidate()
    }
}
