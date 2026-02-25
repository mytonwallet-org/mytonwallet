package org.mytonwallet.app_air.uitransaction.viewControllers.transaction

import android.annotation.SuppressLint
import android.graphics.Color
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.widget.Space
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uitransaction.viewControllers.transaction.views.LabelAndIconView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TransactionHeaderView(
    val viewController: WeakReference<WViewController>,
    var transaction: MApiTransaction,
    private val onTokenClick: ((String) -> Unit)? = null
) : WView(
    viewController.get()!!.context,
    LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
),
    WThemedView {
    private val sizeSpan = RelativeSizeSpan(28f / 36f)
    private val colorSpan = WForegroundColorSpan()

    private val tokenIconView = IconView(context, 80.dp, chainSize = 26.dp)

    private val amountView = LabelAndIconView(context)
    private val amountContainerView = WSensitiveDataContainer(
        amountView,
        WSensitiveDataContainer.MaskConfig(16, 4, Gravity.CENTER, protectContentLayoutSize = false)
    ).apply {
        textAlignment = TEXT_ALIGNMENT_CENTER
        amountView.lbl.apply {
            typeface = WFont.NunitoExtraBold.typeface
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 36f)
        }
        layoutParams = LayoutParams(0, amountView.lbl.lineHeight)
    }

    private var peerAddress: String? = null
    private var peerBlockchain: MBlockchain? = null

    private val addressLabel = WLabel(context).apply {
        setStyle(16f)
        setLineHeight(24f)
        setPaddingDp(8, 4, 8, 4)
        foreground = WRippleDrawable.create(12f.dp).apply {
            rippleColor = WColor.SubtitleText.color.colorWithAlpha(25)
        }
        setOnLongClickListener {
            val address = peerAddress ?: return@setOnLongClickListener false
            val blockchain = peerBlockchain ?: return@setOnLongClickListener false
            AddressPopupHelpers.copyAddress(context, address, blockchain)
            true
        }
    }

    private val addressSpace = Space(context).apply {
        id = generateViewId()
    }

    override fun setupViews() {
        super.setupViews()
        reloadData()

        addressLabel.measure(0.unspecified, 0.unspecified)
        val addressLabelTranslation = addressLabel.measuredHeight
        addressLabel.translationY = addressLabelTranslation.toFloat()
        addView(tokenIconView, LayoutParams(82.dp, 82.dp))
        addView(amountContainerView)
        addView(addressSpace, LayoutParams(LayoutParams.WRAP_CONTENT, addressLabelTranslation))
        addView(addressLabel)

        setConstraints {
            toTop(tokenIconView)
            toCenterX(tokenIconView)

            topToBottom(amountContainerView, tokenIconView, 20f)
            toCenterX(amountContainerView, 8f)

            bottomToTop(addressLabel, addressSpace)
            topToBottom(addressSpace, amountContainerView, 2f)
            toBottom(addressSpace)
            toCenterX(addressLabel)
        }

        if (onTokenClick != null) {
            amountView.isClickable = true
            amountView.isFocusable = true
            @SuppressLint("ClickableViewAccessibility")
            amountView.setOnTouchListener { v, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        v.alpha = 0.6f
                    }

                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        v.alpha = 1f
                        if (event.action == MotionEvent.ACTION_UP) {
                            val tx = transaction
                            if (tx is MApiTransaction.Transaction) {
                                onTokenClick.invoke(tx.slug)
                            }
                        }
                    }
                }
                true
            }
        }

        updateTheme()
    }

    fun reloadData() {
        val transaction = transaction
        if (transaction !is MApiTransaction.Transaction)
            throw Exception()
        val token = TokenStore.getToken(transaction.slug)
        if (token != null) {
            tokenIconView.config(transaction)
            val amountDouble = transaction.amount.doubleAbsRepresentation(token.decimals)
            val amount = transaction.amount.toString(
                decimals = token.decimals,
                currency = token.symbol,
                currencyDecimals = transaction.amount.smartDecimalsCount(token.decimals),
                showPositiveSign = true,
                forceCurrencyToRight = true,
                roundUp = false,
            )
            amountView.configure(
                amount.let {
                    val ssb = SpannableStringBuilder(it)
                    CoinUtils.setSpanToFractionalPart(ssb, sizeSpan)
                    if (amountDouble >= 10) {
                        CoinUtils.setSpanToFractionalPart(ssb, colorSpan)
                    }
                    ssb
                },
                Content.of(token, showChain = AccountStore.activeAccount?.isMultichain == true)
            )
        } else {
            tokenIconView.setImageDrawable(null)
        }

        if (transaction.shouldShowTransactionAddress) {
            val fullAddress = if (transaction.isIncoming) transaction.fromAddress else transaction.toAddress
            peerAddress = fullAddress
            peerBlockchain = TokenStore.getToken(transaction.slug)?.mBlockchain

            val addressToShow = transaction.addressToShow(6, 6)
            val addressText = addressToShow?.first ?: ""
            val spannedString: SpannableStringBuilder
            if (transaction.isIncoming) {
                val receivedFromString =
                    "${LocaleController.getString("Received from")} "
                val text = receivedFromString + addressText
                spannedString = SpannableStringBuilder()
                spannedString.append(text)
                AddressPopupHelpers.configSpannableAddress(
                    viewController = viewController,
                    title = if (addressToShow?.second == true) addressText else null,
                    spannedString = spannedString,
                    startIndex = text.length - addressText.length,
                    length = addressText.length,
                    network = AccountStore.activeAccount!!.network,
                    blockchain = TokenStore.getToken(transaction.slug)?.mBlockchain,
                    address = transaction.fromAddress ?: "",
                    popupXOffset = 0,
                    centerHorizontally = true,
                    showTemporaryViewOption = true
                )
            } else {
                val sentToString =
                    "${LocaleController.getString("Sent to")} "
                val text = sentToString + addressText
                spannedString = SpannableStringBuilder()
                spannedString.append(text)
                AddressPopupHelpers.configSpannableAddress(
                    viewController = viewController,
                    title = if (addressToShow?.second == true) addressText else null,
                    spannedString = spannedString,
                    startIndex = text.length - addressText.length,
                    length = addressText.length,
                    network = AccountStore.activeAccount!!.network,
                    blockchain = TokenStore.getToken(transaction.slug)?.mBlockchain,
                    address = transaction.toAddress ?: "",
                    popupXOffset = 0,
                    centerHorizontally = true,
                    showTemporaryViewOption = true
                )
            }
            spannedString.setSpan(
                colorSpan,
                spannedString.length - addressText.length - 1,
                spannedString.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            spannedString.setSpan(
                WTypefaceSpan(WFont.Regular.typeface),
                spannedString.length - addressText.length - 1,
                spannedString.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            if (addressToShow?.second == false) {
                spannedString.styleDots()
            }
            addressLabel.text = spannedString
            addressLabel.movementMethod =
                ExtraHitLinkMovementMethod(addressLabel.paddingLeft, addressLabel.paddingTop)
            addressLabel.highlightColor = Color.TRANSPARENT
        } else if (transaction.type == ApiTransactionType.STAKE) {
            val stakingState =
                StakingStore.getStakingState(AccountStore.activeAccountId!!)?.states?.firstOrNull {
                    it?.tokenSlug == transaction.slug
                }
            stakingState?.let { stakingState ->
                val builder = SpannableStringBuilder()
                builder.append(LocaleController.getString("at"))
                builder.append(" ")
                val yieldStart = builder.length
                builder.append(stakingState.yieldType.toString() + " " + stakingState.annualYield + "%")
                builder.setSpan(
                    ForegroundColorSpan(WColor.SecondaryText.color),
                    0,
                    builder.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                builder.setSpan(
                    WTypefaceSpan(WFont.Medium.typeface, WColor.PrimaryDarkText.color),
                    yieldStart,
                    builder.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                builder.setSpan(
                    AbsoluteSizeSpan(16, true),
                    0,
                    builder.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                addressLabel.text = builder
            }
        }
    }

    override fun updateTheme() {
        colorSpan.color = WColor.SecondaryText.color
        amountView.lbl.setTextColor(WColor.PrimaryText.color)
        addressLabel.setTextColor(WColor.PrimaryText.color)
        reloadData()
    }

}
