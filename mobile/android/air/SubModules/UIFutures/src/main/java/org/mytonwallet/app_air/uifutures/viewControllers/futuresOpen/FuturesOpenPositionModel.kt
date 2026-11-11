package org.mytonwallet.app_air.uifutures.viewControllers.futuresOpen

import java.math.BigDecimal
import java.math.RoundingMode
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.FuturesAmountModel
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.FuturesFundsHint
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.getFuturesHyperliquidBalance
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.getFuturesWalletBalance
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesQuoteResult
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.futuresErrorText
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.futuresPaymentSymbol
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.toFundsHint
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.toPerpsAmount
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeAmountInput
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsDraftRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFundingRequirements
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsQuote
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsSide
import org.mytonwallet.app_air.walletcore.moshi.PERPS_FUNDING_BALANCE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PAYMENT_TOKEN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_OPEN
import org.mytonwallet.app_air.walletcore.moshi.PERPS_UNIT_CURRENCY

/** The margin and leverage of a new position. */
class FuturesOpenPositionModel(
    asset: MApiPerpsListedAsset,
    val side: MApiPerpsSide,
    private val accountId: String?
) : FuturesAmountModel {
    /** Replaced by each snapshot, so the mark price stays current. */
    var asset = asset
    override var isCoinAmount = false
        private set
    override var input = TokenTradeAmountInput()
        private set
    override var leverage: Int = DEFAULT_LEVERAGE.coerceAtMost(asset.maxLeverage)
        private set
    override var isFundedFromBalance = false
        private set
    override val isEditing = false
    override val canSelectLeverage = true
    var estimate: FuturesQuoteResult? = null
        private set
    private var estimateKey: EstimateKey? = null

    data class EstimateKey(val amount: String, val leverage: Int, val isFromBalance: Boolean)

    override val markPrice: Double
        get() = asset.context?.markPx?.toDoubleOrNull() ?: 0.0

    override val symbol: String
        get() = asset.symbol

    override val inputDecimals: Int
        get() = if (isCoinAmount) asset.szDecimals else USD_DECIMALS

    val margin: Double
        get() {
            val value = BigDecimal(input.amount(inputDecimals), inputDecimals).toDouble()
            val usd = if (isCoinAmount) value * markPrice else value
            return BigDecimal.valueOf(usd).setScale(USD_DECIMALS, RoundingMode.DOWN).toDouble()
        }

    val currentKey: EstimateKey
        get() = EstimateKey(margin.toPerpsAmount(), leverage, isFundedFromBalance)

    fun draft(key: EstimateKey = currentKey) = MApiPerpsDraftRequest(
        assetId = asset.id,
        side = side,
        amount = key.amount,
        unit = PERPS_UNIT_CURRENCY,
        leverage = key.leverage,
        funding = PERPS_FUNDING_BALANCE.takeIf { key.isFromBalance }
    )

    private val currentResult: FuturesQuoteResult?
        get() = estimate?.takeIf { estimateKey == currentKey }

    override val isChanged: Boolean
        get() = input.text.isNotEmpty()

    override val currentMarginText: String? = null

    val currentEstimate: MApiPerpsQuote?
        get() = currentResult?.quote?.takeIf { it.kind == PERPS_QUOTE_OPEN }

    override val isEstimating: Boolean
        get() = margin > 0 && estimateKey != currentKey

    override val conversionText: String
        get() = if (isCoinAmount) {
            margin.toUsdString()
        } else {
            val coins = if (markPrice > 0) margin / markPrice else 0.0
            "${coins.toString(COIN_DECIMALS, "", COIN_DECIMALS, smartDecimals = true)} $symbol"
        }

    override val liquidationPrice: Double?
        get() = currentEstimate?.estimatedLiquidationPrice?.toDoubleOrNull()

    override val positionValue: Double?
        get() = currentEstimate?.notional?.toDoubleOrNull()

    override val paymentSlug: String?
        get() = PERPS_PAYMENT_TOKEN_SLUG

    override val paymentTitle: String
        get() = LocaleController.getString("You Pay")

    override val paymentAmount: Double?
        get() = currentEstimate?.paymentAmount?.toDoubleOrNull()

    override val paymentSymbol: String
        get() = futuresPaymentSymbol

    override val walletBalance: BigDecimal?
        get() = getFuturesWalletBalance(accountId)

    override val hyperliquidBalance: BigDecimal?
        get() = getFuturesHyperliquidBalance(accountId, asset.dex, isFundedFromBalance)

    override val canSelectFunding: Boolean
        get() = isFundedFromBalance || hyperliquidBalance != null

    override fun selectFunding(isFromBalance: Boolean) {
        if (isFromBalance == isFundedFromBalance || (isFromBalance && !canSelectFunding)) return
        isFundedFromBalance = isFromBalance
        pendingFraction = null
        emptyFunding = null
        availableCollateral = null
    }

    override val reviewBlocker: String?
        get() {
            if (input.text.isEmpty()) return LocaleController.getString("Enter Amount")
            if (margin <= 0) return LocaleController.getString("Invalid amount")
            val result = currentResult ?: return null
            if (result.error != null) return null
            if (currentEstimate == null) return LocaleController.getString("Invalid amount")
            return null
        }

    override var isPreparingReview = false

    override val canReview: Boolean
        get() = currentEstimate != null && reviewBlocker == null

    /** Funding checked with an empty field, before there is anything to quote. */
    var emptyFunding: MApiPerpsFundingRequirements? = null

    /** The latest quote's funding stays shown while the next one loads. */
    override val fundsHint: FuturesFundsHint?
        get() {
            val funding = if (input.text.isEmpty()) {
                emptyFunding
            } else {
                (currentResult ?: estimate)?.funding
            }
            return funding?.toFundsHint(isEditing = false)
        }

    override val quoteError: String?
        get() = currentResult?.error?.takeIf { fundsHint == null }?.let(::futuresErrorText)

    override val quickChanges = listOf(25, 50, 100)
    override val areQuickChangesRelative = false

    /** The SDK's opening maximum for the selected source, after fees; kept between quotes that omit it. */
    private var availableCollateral: BigDecimal? = null

    val hasAvailableCollateral: Boolean
        get() = availableCollateral != null

    override val areQuickChangesEnabled: Boolean
        get() = availableCollateral?.signum() == 1

    /** A quick button's share of the balance, which the SDK turns into a margin. */
    var pendingFraction: Int? = null
        private set

    /** Fills the share of [availableCollateral] at once; the SDK's quote for the exact share follows. */
    override fun applyQuickChange(percent: Int) {
        val available = availableCollateral ?: return
        pendingFraction = percent
        setUsdInput(available.multiply(BigDecimal(percent)).movePointLeft(2))
    }

    fun updateAvailableCollateral(funding: MApiPerpsFundingRequirements?, isFromBalance: Boolean) {
        if (isFromBalance != isFundedFromBalance) return
        funding?.availableCollateral?.toBigDecimalOrNull()?.let { availableCollateral = it }
    }

    /** Fills the field with the margin the SDK quoted for [pendingFraction]. */
    fun applyFractionResult(result: FuturesQuoteResult) {
        pendingFraction = null
        result.quote?.inputAmount?.toBigDecimalOrNull()?.let(::setUsdInput)
        // A rejected share keeps the filled amount; its error or funding hint is shown
        estimateKey = currentKey
        estimate = result
    }

    private fun setUsdInput(amount: BigDecimal) {
        isCoinAmount = false
        input = TokenTradeAmountInput.of(
            amount.setScale(USD_DECIMALS, RoundingMode.DOWN).movePointRight(USD_DECIMALS)
                .toBigInteger(),
            USD_DECIMALS
        )
    }

    override fun userEditedInput(input: TokenTradeAmountInput) {
        pendingFraction = null
        this.input = input
    }

    override fun toggleUnit() {
        if (markPrice <= 0) return
        pendingFraction = null
        val margin = margin
        isCoinAmount = !isCoinAmount
        if (input.text.isEmpty()) return
        setMargin(margin)
    }

    override fun resetToCurrent() {
        pendingFraction = null
        input = TokenTradeAmountInput()
    }

    fun setLeverage(leverage: Int) {
        this.leverage = leverage.coerceIn(1, asset.maxLeverage)
    }

    fun setEstimate(key: EstimateKey, estimate: FuturesQuoteResult) {
        if (key != currentKey) return
        estimateKey = key
        this.estimate = estimate
    }

    private fun setMargin(margin: Double) {
        val value = if (isCoinAmount) margin / markPrice else margin
        input = TokenTradeAmountInput.of(
            BigDecimal.valueOf(value).setScale(inputDecimals, RoundingMode.DOWN)
                .movePointRight(inputDecimals).toBigInteger(),
            inputDecimals
        )
    }

    private companion object {
        const val DEFAULT_LEVERAGE = 2
        const val USD_DECIMALS = 2
        const val COIN_DECIMALS = 8
    }
}
