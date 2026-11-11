package org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount

import java.math.BigDecimal
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeAmountInput
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PAYMENT_TOKEN_SLUG
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.PerpsStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

/** Funding the order misses on Arbitrum, with the token the action buys. */
data class FuturesFundsHint(
    val title: String,
    val message: String,
    val buttonTitle: String,
    val tokenSlug: String
) {
    /** Empty, which hides the action, until the token loads. */
    val actionTitle: String
        get() = TokenStore.getToken(tokenSlug)?.let {
            LocaleController.getStringWithKeyValues("Buy %token%", listOf("%token%" to it.symbol))
        } ?: ""
}

/** The margin entry screens' state: editing a position and opening one share the layout. */
interface FuturesAmountModel {
    val input: TokenTradeAmountInput
    val inputDecimals: Int
    val isCoinAmount: Boolean
    val markPrice: Double
    val symbol: String
    val conversionText: String

    /** The field holds a new amount, so Review replaces the quick buttons. */
    val isChanged: Boolean

    /** The margin the field started from, linked to reset it; `null` hides the link. */
    val currentMarginText: String?
    val isEstimating: Boolean
    val liquidationPrice: Double?

    /** Editing an existing position, which also shows its liquidation price. */
    val isEditing: Boolean

    /** Shown as a tappable pill. */
    val leverage: Int
    val canSelectLeverage: Boolean
    val positionValue: Double?

    val paymentSlug: String?
    val paymentTitle: String

    /** Shown dimmed until the quote tells paying from receiving. */
    val isPaymentTitleKnown: Boolean
        get() = true
    val paymentAmount: Double?

    /** Shown with "≈". */
    val isPaymentEstimated: Boolean
        get() = false
    val paymentSymbol: String

    val isFundedFromBalance: Boolean

    /** `null` until balances load. */
    val walletBalance: BigDecimal?

    /** `null` below the minimum offered. */
    val hyperliquidBalance: BigDecimal?

    val canSelectFunding: Boolean
    fun selectFunding(isFromBalance: Boolean)

    val canReview: Boolean
    val reviewBlocker: String?

    var isPreparingReview: Boolean

    /** Blocks Review while set. */
    val fundsHint: FuturesFundsHint?

    /** Shown only without a [fundsHint]. */
    val quoteError: String?

    /** Quick buttons, in percent: of the current margin when signed, of the balance otherwise. */
    val quickChanges: List<Int>
    val areQuickChangesRelative: Boolean
    val areQuickChangesEnabled: Boolean
    fun applyQuickChange(percent: Int)

    fun userEditedInput(input: TokenTradeAmountInput)
    fun toggleUnit()
    fun resetToCurrent()
}

internal fun getFuturesWalletBalance(accountId: String?): BigDecimal? {
    val units = BalanceStore.getBalances(accountId)?.get(PERPS_PAYMENT_TOKEN_SLUG) ?: return null
    val decimals = TokenStore.getToken(PERPS_PAYMENT_TOKEN_SLUG)?.decimals ?: USDC_DECIMALS
    return BigDecimal(units, decimals)
}

/** A selected balance stays offered below the minimum. */
internal fun getFuturesHyperliquidBalance(
    accountId: String?,
    dex: String,
    isSelected: Boolean
): BigDecimal? {
    val balance = PerpsStore.snapshotFor(accountId)?.spendableUsdcByDex?.get(dex)
        ?.toBigDecimalOrNull() ?: return null
    return balance.takeIf { isSelected || it > MIN_HYPERLIQUID_BALANCE }
}

private const val USDC_DECIMALS = 6
private val MIN_HYPERLIQUID_BALANCE = BigDecimal("0.25")
