package org.mytonwallet.app_air.uitransaction.viewControllers

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.TextPaint
import android.text.TextUtils
import android.text.method.LinkMovementMethod
import android.util.TypedValue
import android.view.Gravity
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class NftHeaderView(
    context: Context,
    val transaction: MApiTransaction
) : WView(context, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)),
    WThemedView {
    private val colorSpan = WForegroundColorSpan()

    private val imageView = WImageView(context, 12.dp).apply {
        id = generateViewId()
        layoutParams = LayoutParams(72.dp, 72.dp)
    }

    private val nameTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        textAlignment = TEXT_ALIGNMENT_VIEW_START
        typeface = WFont.Medium.typeface
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        layoutParams = LayoutParams(LayoutParams.MATCH_CONSTRAINT, lineHeight)
    }

    private val addressLabel = WLabel(context).apply {
        setStyle(16f)
        setLineHeight(24f)
        gravity = Gravity.START
        layoutParams = LayoutParams(LayoutParams.MATCH_CONSTRAINT, lineHeight)
    }

    init {
        config()

        addView(imageView)
        addView(nameTextView)
        addView(addressLabel)

        setConstraints {
            toStart(imageView, 20f)
            toCenterY(imageView)

            topToTop(nameTextView, imageView, 7.5f)
            startToEnd(nameTextView, imageView, 16f)
            toEnd(nameTextView, 20f)

            bottomToBottom(addressLabel, imageView, 7.5f)
            startToEnd(addressLabel, imageView, 16f)
            toEnd(addressLabel, 20f)
        }

        updateTheme()
    }

    fun config() {
        if (transaction !is MApiTransaction.Transaction)
            throw Exception()
        val nft = transaction.nft!!

        nameTextView.text = nft.name
        imageView.loadUrl(nft.image ?: "")

        val address = transaction.peerAddress
        val addressToShow = transaction.addressToShow()
        val formattedAddress = addressToShow?.first ?: ""
        val prefixString = LocaleController.getString(
            if (transaction.isIncoming) "from" else "to"
        ) + " "
        val startOffset = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = WFont.Regular.typeface
            textSize = 16f.dp
        }.measureText(prefixString)
        val addressAttr = SpannableStringBuilder(
            prefixString + formattedAddress
        ).apply {
            AddressPopupHelpers.configSpannableAddress(
                context,
                this,
                length - formattedAddress.length,
                formattedAddress.length,
                TONCOIN_SLUG,
                address,
                startOffset.roundToInt()
            )
            setSpan(
                WForegroundColorSpan(WColor.SecondaryText),
                length - formattedAddress.length - 1,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                WTypefaceSpan(WFont.Regular.typeface),
                length - formattedAddress.length,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            if (addressToShow?.second == false) {
                updateDotsTypeface()
            }
        }
        addressLabel.text = addressAttr
        addressLabel.movementMethod = LinkMovementMethod.getInstance()
        addressLabel.highlightColor = Color.TRANSPARENT
    }

    override fun updateTheme() {
        colorSpan.color = WColor.SecondaryText.color
        nameTextView.setTextColor(WColor.PrimaryText.color)
        addressLabel.setTextColor(WColor.PrimaryText.color)
    }

}
