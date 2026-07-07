package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.text.buildSpannedString
import androidx.core.view.isGone
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.spans.ScamLabelSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.formatTime
import org.mytonwallet.app_air.walletbasecontext.utils.negative
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import java.math.BigInteger
import kotlin.math.abs

class ActivityMainContentView(context: Context) : WView(context), WProtectedView, WThemedView {

    init {
        id = generateViewId()
        clipChildren = false
    }

    private val iconView = IconView(context, ApplicationContextHolder.adaptiveIconSize.dp).apply {
        id = generateViewId()
        clipChildren = false
    }

    private val topLeftLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize(), WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        setTextColor(WColor.PrimaryText)
        minHeight = 24.dp
        gravity = Gravity.CENTER_VERTICAL
    }

    private val scamLabelSpan by lazy {
        ScamLabelSpan(LocaleController.getString("Scam").uppercase())
    }

    private val topRightIconView by lazy {
        WCustomImageView(context)
    }

    private val topRightLabel by lazy {
        WSensitiveDataContainer(
            WLabel(context).apply {
                setStyle(adaptiveFontSize())
                setSingleLine()
                ellipsize = TextUtils.TruncateAt.MARQUEE
                isSelected = true
                isHorizontalFadingEdgeEnabled = true
                applyFontOffsetFix = true
                minHeight = 24.dp
                gravity = Gravity.CENTER_VERTICAL
            },
            WSensitiveDataContainer.MaskConfig(
                0,
                2,
                Gravity.END or Gravity.CENTER_VERTICAL
            )
        )
    }

    private val bottomLeftLabel = WLabel(context).apply {
        setStyle(13f, WFont.Regular)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.MARQUEE
        isSelected = true
        useCustomEmoji = true
    }

    private val bottomRightLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context).apply {
            setStyle(13f)
            setSingleLine()
            gravity = Gravity.RIGHT
            setTextColor(WColor.PrimaryLightText)
        }
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.RIGHT or Gravity.CENTER_VERTICAL)
        )
    }

    private val activitySwapIconsView: ActivitySwapIconsView by lazy {
        ActivitySwapIconsView(context).apply {
            setPaddingDpLocalized(4, 0, 0, 0)
            isGone = true
        }
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
        addView(topRightIconView, LayoutParams(18.dp, 18.dp))
        addView(topRightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(bottomRightLabel)
        addView(activitySwapIconsView)
        setConstraints {
            // Swap Icons View
            toCenterY(activitySwapIconsView)
            toEndPx(activitySwapIconsView, END_MARGIN_PX)

            // Icon View
            toTop(iconView, ApplicationContextHolder.adaptiveIconTopMargin)
            toStart(iconView, 12f)

            // Top Left View
            setHorizontalBias(topLeftLabel.id, 0f)
            toStart(topLeftLabel, ApplicationContextHolder.adaptiveContentStart)
            toTop(topLeftLabel, 8f)

            // Top Right View
            setHorizontalBias(topRightLabel.id, 1f)
            constrainedWidth(topRightLabel.id, true)
            startToEnd(topRightLabel, topLeftLabel, 4f)
            toTop(topRightLabel, 8f)
            endToStart(topRightIconView, activitySwapIconsView)
            endToStart(topRightLabel, topRightIconView, 4f)
            topToTop(topRightIconView, topRightLabel)
            bottomToBottom(topRightIconView, topRightLabel)
            setGoneMargin(topRightLabel.id, ConstraintSet.END, 0)
            setGoneMargin(topRightIconView.id, ConstraintSet.END, END_MARGIN_PX)

            // Bottom Views
            endToStart(bottomRightLabel, activitySwapIconsView)
            toBottom(bottomRightLabel, 10f)
            setHorizontalBias(bottomLeftLabel.id, 0f)
            constrainedWidth(bottomLeftLabel.id, true)
            toStart(bottomLeftLabel, ApplicationContextHolder.adaptiveContentStart)
            toBottom(bottomLeftLabel, 10f)
            endToStart(bottomLeftLabel, bottomRightLabel, 4f)
            setGoneMargin(bottomRightLabel.id, ConstraintSet.END, END_MARGIN_PX)
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

    override fun updateTheme() {
        topLeftLabel.updateTheme()
        bottomLeftLabel.updateTheme()
        topRightLabel.contentView.updateTheme()
        bottomRightLabel.contentView.updateTheme()
        activitySwapIconsView.updateTheme()
        iconView.updateTheme()
        (transaction as? MApiTransaction.Transaction)?.let(iconView::config)
    }

    override fun updateProtectedView() {
        bottomRightLabel.updateProtectedView()
    }

    private fun configureTransaction(accountId: String, isMultichain: Boolean) {
        val transaction = transaction as MApiTransaction.Transaction
        iconView.config(transaction)
        topLeftLabel.text = buildTopLeftTitle(transaction.title)
        activitySwapIconsView.isGone = true
        with(bottomRightLabel) {
            contentView.setStyle(13f)
            contentView.setTextColor(WColor.PrimaryLightText)
            maskView.skin = null
        }
        configureTransactionSubtitle(accountId, isMultichain)
        configureTransactionEquivalentAmount()
        configureTransactionTopRight(transaction)
    }

    fun configureTransactionTopRight(transaction: MApiTransaction.Transaction) {
        topRightLabel.contentView.setStyle(adaptiveFontSize())

        val amountCols = if (transaction.isNft || transaction.noAmountTransaction) 0 else 4 + abs(
            transaction.id.hashCode() % 8
        )
        topRightLabel.setMaskCols(amountCols)

        val token = transaction.token
        if (token == null || transaction.isNft || transaction.noAmountTransaction) {
            topRightLabel.contentView.text = ""
            topRightIconView.isGone = true
            topRightIconView.clear()
            return
        }

        val isStake = transaction.type == ApiTransactionType.STAKE
        topRightLabel.contentView.setAmount(
            if (isStake) transaction.amount.abs() else transaction.amount,
            token.decimals,
            token.symbol,
            token.decimals,
            true,
            !isStake,
            forceCurrencyToRight = true,
        )
        topRightLabel.maskView.skin = if (transaction.type == null && transaction.isIncoming) {
            SensitiveDataMaskView.Skin.GREEN
        } else {
            null
        }
        topRightLabel.contentView.setTextColor(
            when {
                transaction.status == ApiTransactionStatus.FAILED -> WColor.Red.color
                transaction.type == ApiTransactionType.STAKE -> WColor.Purple.color
                transaction.type == ApiTransactionType.BURN -> WColor.Red.color
                transaction.amount > BigInteger.ZERO -> WColor.Green.color
                else -> WColor.PrimaryText.color
            }
        )

        topRightIconView.isVisible = true
        topRightIconView.set(Content.of(token, showChain = false))
    }

    private fun configureSwap() {
        val swap = transaction as MApiTransaction.Swap
        iconView.config(swap)
        topLeftLabel.text = buildTopLeftTitle(swap.title)
        activitySwapIconsView.isVisible = true
        activitySwapIconsView.configure(swap)
        configureSwapSubtitle()
        configureSwapTo(swap)
        configureSwapTopRight(swap)
    }

    fun configureSwapTopRight(swap: MApiTransaction.Swap) {
        topRightLabel.contentView.setStyle(adaptiveFontSize(14f))
        topRightLabel.setMaskCols(4 + abs(swap.id.hashCode() % 8))

        val fromToken = swap.fromToken
        if (fromToken == null) {
            topRightLabel.contentView.text = ""
            topRightIconView.isGone = true
            topRightIconView.clear()
            return
        }

        val status = swap.cex?.status?.uiStatus ?: swap.status.uiStatus
        val isFailed =
            status == MApiTransaction.UIStatus.EXPIRED || status == MApiTransaction.UIStatus.FAILED

        topRightLabel.contentView.setAmount(
            amount = swap.fromAmount.negative().toBigInteger(fromToken.decimals) ?: BigInteger.ZERO,
            decimals = fromToken.decimals,
            currency = fromToken.symbol,
            currencyDecimals = fromToken.decimals,
            smartDecimals = true,
            showPositiveSign = true,
            forceCurrencyToRight = true
        )
        topRightLabel.maskView.skin = if (isFailed) {
            SensitiveDataMaskView.Skin.RED
        } else {
            null
        }
        topRightLabel.contentView.setTextColor(
            if (isFailed) {
                WColor.Red
            } else {
                WColor.PrimaryLightText
            }
        )

        topRightIconView.visibility = GONE
        topRightIconView.clear()
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
                    val drawable = context.requireDrawableCompat(it)
                    drawable.mutate()
                    drawable.setTint(WColor.PrimaryLightText.color)
                    val width = 12.dp
                    val height = 12.dp
                    drawable.setBounds(0, 0, width, height)
                    val imageSpan = VerticalImageSpan(drawable)
                    builder.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.append(" ")
                }
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

    private fun configureSwapTo(swap: MApiTransaction.Swap) {
        val toToken = swap.toToken
        bottomRightLabel.contentView.setStyle(16f)
        if (toToken == null) {
            bottomRightLabel.contentView.text = ""
            bottomRightLabel.setMaskCols(0)
            return
        }
        bottomRightLabel.contentView.setAmount(
            amount = swap.toAmount.toBigInteger(toToken.decimals) ?: BigInteger.ZERO,
            decimals = toToken.decimals,
            currency = toToken.symbol,
            currencyDecimals = toToken.decimals,
            smartDecimals = true,
            showPositiveSign = true,
            forceCurrencyToRight = true
        )
        val status = swap.cex?.status?.uiStatus ?: swap.status.uiStatus
        when (status) {
            MApiTransaction.UIStatus.PENDING,
            MApiTransaction.UIStatus.COMPLETED -> {
                bottomRightLabel.maskView.skin = SensitiveDataMaskView.Skin.GREEN
                bottomRightLabel.contentView.setTextColor(WColor.Green)
            }

            MApiTransaction.UIStatus.EXPIRED,
            MApiTransaction.UIStatus.FAILED -> {
                bottomRightLabel.maskView.skin = SensitiveDataMaskView.Skin.RED
                bottomRightLabel.contentView.setTextColor(WColor.Red)
            }

            MApiTransaction.UIStatus.HOLD -> {
                bottomRightLabel.maskView.skin = null
                bottomRightLabel.contentView.setTextColor(WColor.PrimaryLightText)
            }
        }
        updateBottomRightLabelMaskCols()
    }

    private fun updateBottomRightLabelMaskCols() {
        val amountCols =
            if (bottomRightLabel.contentView.text.isNullOrEmpty()) 0 else 4 + abs(bottomRightLabel.contentView.text.hashCode() % 4)
        bottomRightLabel.setMaskCols(amountCols)
    }

    companion object {
        val END_MARGIN_PX = 16.dp
    }
}
