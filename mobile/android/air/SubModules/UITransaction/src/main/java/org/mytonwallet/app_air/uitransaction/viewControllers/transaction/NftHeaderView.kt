package org.mytonwallet.app_air.uitransaction.viewControllers.transaction

import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.Paint
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class NftHeaderView(
    val viewController: WeakReference<WViewController>,
    var transaction: MApiTransaction
) : WView(
    viewController.get()!!.context,
    LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
),
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

    private var peerAddress: String? = null

    private val addressLabel = WLabel(context).apply {
        setStyle(16f)
        setLineHeight(24f)
        gravity = Gravity.START
        layoutParams = LayoutParams(WRAP_CONTENT, lineHeight + 8.dp)
        setPaddingDp(8, 4, 8, 4)
        foreground = WRippleDrawable.create(12f.dp).apply {
            rippleColor = WColor.SubtitleText.color.colorWithAlpha(25)
        }
        setOnLongClickListener {
            val address = peerAddress ?: return@setOnLongClickListener false
            val blockchain = (transaction as? MApiTransaction.Transaction)?.nft?.chain
                ?: return@setOnLongClickListener false
            AddressPopupHelpers.copyAddress(context, address, blockchain)
            true
        }
    }

    init {
        reloadData()

        addView(imageView)
        addView(nameTextView)
        addView(addressLabel)

        setConstraints {
            toStart(imageView, 20f)
            toCenterY(imageView)

            topToTop(nameTextView, imageView, 7.5f)
            startToEnd(nameTextView, imageView, 16f)
            toEnd(nameTextView, 20f)

            setHorizontalBias(addressLabel.id, 0f)
            constrainedWidth(addressLabel.id, true)
            bottomToBottom(addressLabel, imageView, 3.5f)
            startToEnd(addressLabel, imageView, 8f)
            toEnd(addressLabel, 20f)
        }

        updateTheme()
    }

    fun reloadData() {
        val transaction = transaction
        if (transaction !is MApiTransaction.Transaction)
            throw Exception()
        val nft = transaction.nft!!

        nameTextView.text = nft.name
        imageView.loadUrl(nft.image ?: "")

        val address = transaction.peerAddress
        peerAddress = address

        val addressToShow = transaction.addressToShow(6, 6)
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
                viewController = viewController,
                title = if (addressToShow?.second == true) formattedAddress else null,
                spannedString = this,
                startIndex = length - formattedAddress.length,
                length = formattedAddress.length,
                network = AccountStore.activeAccount!!.network,
                blockchain = nft.chain,
                address = address,
                popupXOffset = startOffset.roundToInt(),
                centerHorizontally = false,
                showTemporaryViewOption = true
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
                styleDots()
            }
        }
        addressLabel.text = addressAttr
        addressLabel.movementMethod = ExtraHitLinkMovementMethod(addressLabel.paddingLeft, addressLabel.paddingTop)
        addressLabel.highlightColor = Color.TRANSPARENT
    }

    override fun updateTheme() {
        colorSpan.color = WColor.SecondaryText.color
        nameTextView.setTextColor(WColor.PrimaryText.color)
        addressLabel.setTextColor(WColor.PrimaryText.color)
    }

}
