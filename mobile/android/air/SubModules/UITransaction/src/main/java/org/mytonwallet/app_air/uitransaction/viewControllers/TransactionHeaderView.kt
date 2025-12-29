package org.mytonwallet.app_air.uitransaction.viewControllers

import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.Paint
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.method.LinkMovementMethod
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import android.view.Gravity
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uitransaction.viewControllers.views.LabelAndIconView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
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

    private val addressLabel = WLabel(context).apply {
        setStyle(16f)
        setLineHeight(24f)
    }

    override fun setupViews() {
        super.setupViews()
        reloadData()

        addView(tokenIconView, LayoutParams(80.dp, 80.dp))
        addView(amountContainerView)
        addView(addressLabel)

        setConstraints {
            toTop(tokenIconView)
            toCenterX(tokenIconView)

            topToBottom(amountContainerView, tokenIconView, 22f)
            toCenterX(amountContainerView, 8f)

            topToBottom(addressLabel, amountContainerView, 6f)
            toBottom(addressLabel)
            toCenterX(addressLabel)
        }

        if (onTokenClick != null) {
            amountView.isClickable = true
            amountView.isFocusable = true
            amountView.setOnTouchListener { v, event ->
                when (event.action) {
                    android.view.MotionEvent.ACTION_DOWN -> {
                        v.alpha = 0.6f
                    }
                    android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                        v.alpha = 1f
                        if (event.action == android.view.MotionEvent.ACTION_UP) {
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
                Content.of(token, !token.isBlockchainNative)
            )
        } else {
            tokenIconView.setImageDrawable(null)
        }

        if (transaction.shouldShowTransactionAddress) {
            val addressToShow = transaction.addressToShow(6, 6)
            val addressText = addressToShow?.first ?: ""
            val spannedString: SpannableStringBuilder
            if (transaction.isIncoming) {
                val receivedFromString =
                    "${LocaleController.getString("Received from")} "
                val text = receivedFromString + addressText
                val textPaintToMeasure = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    typeface = WFont.Regular.typeface
                    textSize = TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_SP,
                        16f,
                        context.resources.displayMetrics
                    )
                }
                val startOffset =
                    if (LocaleController.isRTL)
                        textPaintToMeasure.measureText(text).roundToInt() -
                            AddressPopupHelpers.POPUP_WIDTH.dp
                    else
                        textPaintToMeasure.measureText(receivedFromString).roundToInt()
                spannedString = SpannableStringBuilder()
                spannedString.append(text)
                AddressPopupHelpers.configSpannableAddress(
                    viewController,
                    if (addressToShow?.second == true) addressText else null,
                    spannedString,
                    text.length - addressText.length,
                    addressText.length,
                    transaction.slug,
                    transaction.fromAddress,
                    startOffset,
                    showTemporaryViewOption = true
                )
            } else {
                val sentToString =
                    "${LocaleController.getString("Sent to")} "
                val text = sentToString + addressText
                val startOffset = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    typeface = WFont.Regular.typeface
                    textSize = TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_SP,
                        16f,
                        context.resources.displayMetrics
                    )
                }.measureText(sentToString)
                spannedString = SpannableStringBuilder()
                spannedString.append(text)
                AddressPopupHelpers.configSpannableAddress(
                    viewController,
                    if (addressToShow?.second == true) addressText else null,
                    spannedString,
                    text.length - addressText.length,
                    addressText.length,
                    transaction.slug,
                    transaction.toAddress ?: "",
                    startOffset.roundToInt(),
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
                spannedString.updateDotsTypeface()
            }
            addressLabel.text = spannedString
            addressLabel.movementMethod = LinkMovementMethod.getInstance()
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
