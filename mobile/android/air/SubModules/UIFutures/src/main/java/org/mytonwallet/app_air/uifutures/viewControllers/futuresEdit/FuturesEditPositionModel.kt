package org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.FuturesAmountModel
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.FuturesFundsHint
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.getFuturesHyperliquidBalance
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.getFuturesWalletBalance
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeAmountInput
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsDraftRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsQuote
import org.mytonwallet.app_air.walletcore.moshi.PERPS_FUNDING_BALANCE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PAYMENT_TOKEN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_INCREASE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_REDUCE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_UNIT_CURRENCY

/** Edits the margin of a position; a margin difference is paid in or received */
class FuturesEditPositionModel(position: MApiPerpsNativePosition, private val accountId: String?) :
    FuturesAmountModel {
    /** Replaced by each snapshot, so the mark price and estimates stay current. */
    var position = position
        set(value) {
            field = value
            if (isCoinAmount && markPrice <= 0) {
                isCoinAmount = false
                resetToCurrent()
            }
        }
    override var isCoinAmount = false
        private set
    override var input = currentMarginInput()
        private set
    override var isFundedFromBalance = false
        private set
    override val leverage: Int
        get() = position.leverage
    var estimate: FuturesQuoteResult? = null
        private set
    private var estimateDraft: MApiPerpsDraftRequest? = null

    override val markPrice: Double
        get() = position.markPrice ?: 0.0

    override val symbol: String
        get() = position.symbol

    override val currentMarginText: String?
        get() = position.invested.toUsdString().takeIf { isChanged }

    override val isEditing = true

    override val canSelectLeverage = false

    override val quickChanges = listOf(-25, -5, 5, 25)
    override val areQuickChangesRelative = true
    override val areQuickChangesEnabled = true

    override fun applyQuickChange(percent: Int) {
        setTargetMargin(position.invested * (1 + percent / 100.0))
    }

    override val inputDecimals: Int
        get() = if (isCoinAmount) position.asset?.szDecimals ?: COIN_DECIMALS else USD_DECIMALS

    val targetMargin: Double
        get() {
            val value = BigDecimal(input.amount(inputDecimals), inputDecimals).toDouble()
            return if (isCoinAmount) value * markPrice else value
        }

    /** Unchanged while the field holds the current margin as it is first shown. */
    private val isAmountChanged: Boolean
        get() = input.amount(inputDecimals) != currentMarginInput().amount(inputDecimals)

    override val isChanged: Boolean
        get() = isAmountChanged

    val marginDelta: Double
        get() = if (isAmountChanged) {
            BigDecimal.valueOf(targetMargin - position.invested)
                .setScale(USD_DECIMALS, RoundingMode.HALF_UP)
                .toDouble()
        } else {
            0.0
        }

    val isIncrease: Boolean
        get() = marginDelta > 0

    /** Target total collateral sent to the SDK; the change is relative to the position's own. */
    val requestAmount: String
        get() = targetMargin.toPerpsAmount()

    val draft: MApiPerpsDraftRequest
        get() = MApiPerpsDraftRequest(
            assetId = position.asset?.id.orEmpty(),
            side = position.side,
            amount = requestAmount,
            unit = PERPS_UNIT_CURRENCY,
            leverage = leverage,
            editing = true,
            funding = PERPS_FUNDING_BALANCE.takeIf { isFundedFromBalance }
        )

    private val currentResult: FuturesQuoteResult?
        get() = estimate?.takeIf { estimateDraft == draft }

    /** The quote of the change now entered, if it arrived. */
    val currentEstimate: MApiPerpsQuote?
        get() = currentResult?.quote?.takeIf {
            it.kind == PERPS_QUOTE_INCREASE || it.kind == PERPS_QUOTE_REDUCE
        }

    /** Waiting for the quote of a change that can be quoted; an empty or zero field has none. */
    override val isEstimating: Boolean
        get() = isChanged && targetMargin > 0 && estimateDraft != draft

    override val conversionText: String
        get() = if (isCoinAmount) {
            targetMargin.toUsdString()
        } else {
            val coins = if (markPrice > 0) targetMargin / markPrice else 0.0
            "${coins.toString(
                COIN_DECIMALS,
                "",
                COIN_DECIMALS,
                smartDecimals = true
            )} ${position.symbol}"
        }

    override val liquidationPrice: Double?
        get() = if (isChanged) {
            currentEstimate?.estimatedLiquidationPrice?.toDoubleOrNull()
        } else {
            position.liquidationPrice
        }

    override val positionValue: Double?
        get() = if (isChanged) {
            currentEstimate?.notional?.toDoubleOrNull()
        } else {
            position.positionValue
        }

    override val paymentTitle: String
        get() = LocaleController.getString(
            when (currentEstimate?.kind) {
                PERPS_QUOTE_INCREASE -> "You Pay"
                PERPS_QUOTE_REDUCE -> "You Receive"
                else -> "You Pay or Receive"
            }
        )

    override val isPaymentTitleKnown: Boolean
        get() = currentEstimate != null

    /** Paid for an increase; a reduction's estimated proceeds */
    override val paymentAmount: Double?
        get() {
            val quote = currentEstimate ?: return null
            return if (isIncrease) {
                quote.paymentAmount.toDoubleOrNull()
            } else {
                quote.estimatedReceiveAmount?.toDoubleOrNull()
            }
        }

    override val isPaymentEstimated: Boolean
        get() = !isIncrease

    override val paymentSlug: String?
        get() = PERPS_PAYMENT_TOKEN_SLUG.takeIf { currentEstimate != null }

    override val paymentSymbol: String
        get() = futuresPaymentSymbol

    override val walletBalance: BigDecimal?
        get() = getFuturesWalletBalance(accountId)

    override val hyperliquidBalance: BigDecimal?
        get() = getFuturesHyperliquidBalance(
            accountId,
            position.asset?.dex ?: position.dex,
            isFundedFromBalance
        )

    override val canSelectFunding: Boolean
        get() = (isFundedFromBalance || hyperliquidBalance != null) && marginDelta >= 0

    override fun selectFunding(isFromBalance: Boolean) {
        if (isFromBalance == isFundedFromBalance || (isFromBalance && !canSelectFunding)) return
        isFundedFromBalance = isFromBalance
    }

    private val hasEnoughBalance: Boolean
        get() {
            currentEstimate ?: return true
            val amount = paymentAmount ?: return true
            val balance = if (isFundedFromBalance) {
                hyperliquidBalance ?: return true
            } else {
                walletBalance ?: BigDecimal.ZERO
            }
            return balance >= BigDecimal.valueOf(amount)
        }

    /** Why the change cannot be reviewed, or `null` once it can. */
    override val reviewBlocker: String?
        get() {
            if (input.text.isEmpty()) return LocaleController.getString("Enter Amount")
            if (targetMargin <= 0) return LocaleController.getString("Invalid amount")
            val result = currentResult ?: return null
            if (result.error != null) return null
            currentEstimate ?: return LocaleController.getString("Invalid amount")
            if (isIncrease && !hasEnoughBalance) {
                return LocaleController.getStringWithKeyValues(
                    "Insufficient %symbol% Balance",
                    listOf("%symbol%" to paymentSymbol)
                )
            }
            return null
        }

    override var isPreparingReview = false

    override val canReview: Boolean
        get() = isChanged && currentEstimate != null && reviewBlocker == null

    override val fundsHint: FuturesFundsHint?
        get() = currentResult?.funding?.toFundsHint(isEditing = true)

    override val quoteError: String?
        get() = currentResult?.error?.takeIf { fundsHint == null }?.let(::futuresErrorText)

    override fun userEditedInput(input: TokenTradeAmountInput) {
        this.input = input
    }

    override fun resetToCurrent() {
        input = currentMarginInput()
    }

    override fun toggleUnit() {
        if (markPrice <= 0) return
        val isMarginChanged = isAmountChanged
        val margin = targetMargin
        isCoinAmount = !isCoinAmount
        if (isMarginChanged) setTargetMargin(margin) else input = currentMarginInput()
    }

    fun setEstimate(draft: MApiPerpsDraftRequest, estimate: FuturesQuoteResult) {
        if (draft != this.draft) return
        estimateDraft = draft
        this.estimate = estimate
    }

    private fun setTargetMargin(margin: Double) {
        input = marginInput(margin, RoundingMode.DOWN)
    }

    private fun currentMarginInput() = marginInput(position.invested, RoundingMode.HALF_UP)

    private fun marginInput(margin: Double, rounding: RoundingMode): TokenTradeAmountInput {
        val value = if (isCoinAmount) margin / markPrice else margin
        return TokenTradeAmountInput.of(value.toUnits(inputDecimals, rounding), inputDecimals)
    }

    private fun Double.toUnits(
        decimals: Int,
        rounding: RoundingMode = RoundingMode.DOWN
    ): BigInteger = BigDecimal.valueOf(
        this
    ).setScale(decimals, rounding).movePointRight(decimals).toBigInteger()

    private companion object {
        const val USD_DECIMALS = 2
        const val COIN_DECIMALS = 8
    }
}
