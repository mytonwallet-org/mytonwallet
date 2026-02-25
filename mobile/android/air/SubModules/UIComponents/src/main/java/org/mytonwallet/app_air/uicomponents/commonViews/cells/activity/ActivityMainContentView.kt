package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import androidx.core.text.buildSpannedString
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ScamLabelSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.formatTime
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import kotlin.math.abs
import kotlin.math.absoluteValue

class ActivityMainContentView(context: Context) : WView(context), WProtectedView {

    init {
        id = generateViewId()
    }

    private val iconView = IconView(context, ApplicationContextHolder.adaptiveIconSize.dp).apply {
        id = generateViewId()
    }

    private val topLeftLabel = WLabel(context).apply {
        setStyle(ApplicationContextHolder.adaptiveFontSize, WFont.DemiBold)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    private val scamLabelSpan by lazy {
        ScamLabelSpan(LocaleController.getString("Scam").uppercase())
    }

    private val topRightView: ActivityAmountView by lazy {
        ActivityAmountView(context)
    }

    private val bottomLeftLabel = WLabel(context).apply {
        setStyle(13f, WFont.Regular)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.MARQUEE
        isSelected = true
    }

    private val bottomRightLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(13f)
        lbl.setSingleLine()
        lbl.gravity = Gravity.RIGHT
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.RIGHT or Gravity.CENTER_VERTICAL)
        )
    }

    override fun setupViews() {
        super.setupViews()

        addView(
            iconView,
            LayoutParams(
                (ApplicationContextHolder.adaptiveIconSize + 2).dp,
                (ApplicationContextHolder.adaptiveIconSize + 2).dp
            )
        )
        addView(topLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(bottomLeftLabel)
        addView(topRightView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(bottomRightLabel)
        setConstraints {
            // Icon View
            toTop(iconView, ApplicationContextHolder.adaptiveIconTopMargin)
            toStart(iconView, 12f)

            // Top Left View
            setHorizontalBias(topLeftLabel.id, 0f)
            toStart(topLeftLabel, ApplicationContextHolder.adaptiveContentStart)
            toTop(topLeftLabel, 9f)

            // Top Right View
            setHorizontalBias(topRightView.id, 1f)
            constrainedWidth(topRightView.id, true)
            startToEnd(topRightView, topLeftLabel, 4f)
            toTop(topRightView, 9f)
            toEnd(topRightView, 16f)

            // Bottom Views
            toEnd(bottomRightLabel, 16f)
            toBottom(bottomRightLabel, 10f)
            setHorizontalBias(bottomLeftLabel.id, 0f)
            constrainedWidth(bottomLeftLabel.id, true)
            toStart(bottomLeftLabel, ApplicationContextHolder.adaptiveContentStart)
            toBottom(bottomLeftLabel, 10f)
            endToStart(bottomLeftLabel, bottomRightLabel, 4f)
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, 60.dp.exactly)
    }

    private var transaction: MApiTransaction? = null
    fun configure(transaction: MApiTransaction, accountId: String, isMultichain: Boolean) {
        this.transaction = transaction
        when (transaction) {
            is MApiTransaction.Transaction -> {
                configureTransaction(accountId, isMultichain)
            }

            is MApiTransaction.Swap -> {
                configureSwap()
            }
        }
        bottomLeftLabel.isGone = transaction.isEmulation
        if (transaction.isEmulation) {
            topLeftLabel.setPadding(0, 10.dp, 0, 0)
        }
    }

    fun updateTheme() {
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        topRightView.updateTheme()
        bottomRightLabel.contentView.setTextColor(WColor.PrimaryLightText.color)
        (transaction as? MApiTransaction.Transaction)?.let(iconView::config)
    }

    override fun updateProtectedView() {
        bottomRightLabel.updateProtectedView()
    }

    private fun configureTransaction(accountId: String, isMultichain: Boolean) {
        val transaction = transaction as MApiTransaction.Transaction
        iconView.config(transaction)
        topLeftLabel.text = buildTopLeftTitle(transaction.title)
        topRightView.configure(transaction)
        configureTransactionSubtitle(accountId, isMultichain)
        configureTransactionEquivalentAmount()
    }

    private fun configureSwap() {
        val swap = transaction as MApiTransaction.Swap
        iconView.config(swap)
        topLeftLabel.text = buildTopLeftTitle(swap.title)
        topRightView.configure(swap)
        configureSwapSubtitle()
        configureSwapRate()
    }

    private fun configureTransactionEquivalentAmount() {
        val transaction = transaction as MApiTransaction.Transaction
        if (transaction.isNft || transaction.noAmountTransaction) {
            bottomRightLabel.contentView.text = ""
            bottomRightLabel.setMaskCols(0)
            return
        }
        val token = transaction.token
        if (token == null) {
            bottomRightLabel.contentView.text = ""
            bottomRightLabel.setMaskCols(0)
            return
        }
        bottomRightLabel.contentView.text = token.price?.let { price ->
            val equivalentAmount =
                (price * transaction.amount.doubleAbsRepresentation(decimals = token.decimals))
            equivalentAmount.toString(
                token.decimals,
                WalletCore.baseCurrency.sign,
                WalletCore.baseCurrency.decimalsCount,
                smartDecimals = true,
                roundUp = false
            )
        }
        updateBottomRightLabelMaskCols()
    }

    private fun buildTopLeftTitle(title: String): CharSequence {
        if (transaction?.isScam != true) {
            return title
        }
        return buildSpannedString {
            append(title)
            append(" ")
            append(" ", scamLabelSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    private fun configureTransactionSubtitle(accountId: String, isMultichain: Boolean) {
        val transaction = transaction as MApiTransaction.Transaction
        val token = transaction.token
        val timeStr = transaction.dt.formatTime()
        val builder = SpannableStringBuilder()
        if (transaction.status == ApiTransactionStatus.FAILED) {
            builder.append(
                LocaleController.getString("Failed")
            ).append(" · ")
        }
        if (transaction.shouldShowTransactionAddress) {
            builder.append(
                LocaleController.getString(
                    if (transaction.isIncoming)
                        "from"
                    else
                        "to"
                ).lowercase()
            )
            builder.append(" ")
            if (isMultichain) {
                token?.mBlockchain?.symbolIcon?.let {
                    val drawable = ContextCompat.getDrawable(context, it)!!
                    drawable.mutate()
                    drawable.setTint(WColor.PrimaryLightText.color)
                    val width = 12.dp
                    val height = 12.dp
                    drawable.setBounds(0, 0, width, height)
                    val imageSpan = VerticalImageSpan(drawable)
                    builder.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                builder.append(" ")
            }
            val addressStart = builder.length
            val addressToShow = transaction.addressToShow()
            builder.append(addressToShow?.first)
            builder.append(if (LocaleController.isRTL) " \u200F· " else " · ")
            builder.setSpan(
                WTypefaceSpan(WFont.Medium.typeface),
                addressStart,
                builder.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            if (addressToShow?.second == false)
                builder.styleDots(startIndex = addressStart)
        } else if (transaction.type == ApiTransactionType.STAKE) {
            val stakingState =
                StakingStore.getStakingState(accountId)?.states?.firstOrNull {
                    it?.tokenSlug == transaction.slug
                }
            stakingState?.let { stakingState ->
                val annualYield = LocaleController.getString("at %annual_yield%")
                val addressStart = builder.length + annualYield.indexOf("%")
                val yieldString =
                    stakingState.yieldType.toString() + " " + stakingState.annualYield + "%"
                builder.append(
                    annualYield.replace(
                        "%annual_yield%",
                        yieldString
                    )
                )
                builder.setSpan(
                    WTypefaceSpan(WFont.Medium.typeface),
                    addressStart,
                    builder.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                builder.append(" · ")
                builder.setSpan(
                    WTypefaceSpan(WFont.Medium.typeface),
                    builder.length - 3,
                    builder.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        }
        builder.append(timeStr)
        builder.setSpan(
            ForegroundColorSpan(WColor.PrimaryLightText.color),
            0,
            builder.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        bottomLeftLabel.text = builder
    }

    private fun configureSwapSubtitle() {
        val swap = transaction as MApiTransaction.Swap
        val subtitle = swap.subtitle(ignoreInProgress = true) ?: ""
        val timeStr = swap.dt.formatTime()
        val builder = SpannableStringBuilder()
        if (subtitle.isNotEmpty()) {
            builder.append(subtitle)
            builder.append(" · ")
            builder.setSpan(
                WTypefaceSpan(WFont.Medium.typeface),
                0,
                builder.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        builder.append(timeStr)
        builder.setSpan(
            ForegroundColorSpan(WColor.PrimaryLightText.color),
            0,
            builder.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        bottomLeftLabel.text = builder
    }

    private fun configureSwapRate() {
        val swap = transaction as MApiTransaction.Swap
        val fromToken = swap.fromToken
        val toToken = swap.toToken
        if (fromToken == null || toToken == null) {
            bottomRightLabel.contentView.text = ""
            bottomRightLabel.setMaskCols(0)
            return
        }
        val builder = SpannableStringBuilder()
        val rateBigInt = (swap.fromAmount.absoluteValue / swap.toAmount).toBigInteger(fromToken.decimals)!!
        val rate = rateBigInt.toString(
            fromToken.decimals,
            fromToken.symbol,
            2 + rateBigInt.smartDecimalsCount(fromToken.decimals),
            showPositiveSign = false,
            forceCurrencyToRight = true
        )
        builder.append(toToken.symbol)
        builder.append(" ≈ ")
        val rateStart = builder.length
        builder.setSpan(
            ForegroundColorSpan(WColor.PrimaryLightText.color),
            0,
            rateStart,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        val rateFmtDotIndex = rate.indexOf(".")
        builder.append(rate)
        builder.setSpan(
            WTypefaceSpan(WFont.Medium.typeface, WColor.PrimaryLightText.color),
            rateStart,
            builder.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        builder.setSpan(
            RelativeSizeSpan(10 / 14f),
            rateStart + (if (rateFmtDotIndex > -1) rateFmtDotIndex else rate.length),
            builder.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        bottomRightLabel.contentView.text = builder
        updateBottomRightLabelMaskCols()
    }

    private fun updateBottomRightLabelMaskCols() {
        val amountCols =
            if (bottomRightLabel.contentView.text.isNullOrEmpty()) 0 else 4 + abs(bottomRightLabel.contentView.text.hashCode() % 4)
        bottomRightLabel.setMaskCols(amountCols)
    }
}
