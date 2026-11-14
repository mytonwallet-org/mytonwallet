package org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit

import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableString
import android.text.style.StyleSpan
import java.math.BigDecimal
import java.math.RoundingMode
import kotlinx.coroutines.CancellationException
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.FuturesFundsHint
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsDraftRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFundingRequirements
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsQuote
import org.mytonwallet.app_air.walletcore.moshi.PERPS_FUNDING_BALANCE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PAYMENT_TOKEN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.TokenStore

/**
 * A reviewed order quote, or the SDK's validation code when the draft cannot be ordered; with
 * the Arbitrum funding it misses, when that is why.
 */
data class FuturesQuoteResult(
    val quote: MApiPerpsQuote?,
    val error: String?,
    val funding: MApiPerpsFundingRequirements? = null
)

/** Display only; Review needs [prepareFuturesQuote]. */
internal suspend fun previewFuturesQuote(
    accountId: String?,
    draft: MApiPerpsDraftRequest
): FuturesQuoteResult = loadFuturesQuote(accountId, draft) {
    ApiMethod.Perps.PreviewOrder(it, draft)
}

internal suspend fun prepareFuturesQuote(
    accountId: String?,
    draft: MApiPerpsDraftRequest,
    loadsFunding: Boolean = true
): FuturesQuoteResult = loadFuturesQuote(accountId, draft, loadsFunding) {
    ApiMethod.Perps.PrepareOrder(it, draft)
}

private suspend fun loadFuturesQuote(
    accountId: String?,
    draft: MApiPerpsDraftRequest,
    loadsFunding: Boolean = true,
    method: (String) -> ApiMethod<MApiPerpsQuote>
): FuturesQuoteResult {
    accountId ?: return FuturesQuoteResult(null, PERPS_QUOTE_FAILED)
    return try {
        val quote = WalletCore.call(method(accountId))
        FuturesQuoteResult(quote, null, quote.fundingRequirements)
    } catch (e: CancellationException) {
        throw e
    } catch (e: JSWebViewBridge.ApiError) {
        val error = e.thrownMessage ?: PERPS_QUOTE_FAILED
        val funding = if (loadsFunding && error.startsWith("PerpsInsufficient")) {
            loadFuturesFunding(accountId, draft)
        } else {
            null
        }
        FuturesQuoteResult(null, error, funding)
    } catch (_: Throwable) {
        FuturesQuoteResult(null, PERPS_QUOTE_FAILED)
    }
}

/** What the draft needs on Arbitrum; `null` when it cannot be checked. */
internal suspend fun loadFuturesFunding(
    accountId: String?,
    draft: MApiPerpsDraftRequest
): MApiPerpsFundingRequirements? {
    accountId ?: return null
    return try {
        WalletCore.call(ApiMethod.Perps.GetFundingRequirements(accountId, draft))
    } catch (e: CancellationException) {
        throw e
    } catch (_: Throwable) {
        null
    }
}

/** The funding banner for missing USDC, ETH for the fee, or both, as on iOS. */
internal fun MApiPerpsFundingRequirements.toFundsHint(isEditing: Boolean): FuturesFundsHint? {
    val usdc = fundingUsdc()
    val eth = requiredEth.toFundingAmount()
    return when {
        needsUsdc && needsEth -> FuturesFundsHint(
            title = LocaleController.getString("PerpsFundingMissingTitle"),
            message = LocaleController.getStringWithKeyValues(
                "\$perps_funding_missing",
                listOf("%minUSDC%" to usdc, "%feeETH%" to eth)
            ),
            buttonTitle = LocaleController.getString("Not Enough Funds"),
            tokenSlug = PERPS_PAYMENT_TOKEN_SLUG
        )

        needsUsdc -> FuturesFundsHint(
            title = LocaleController.getStringWithKeyValues(
                "\$not_enough_symbol_lowercase",
                listOf("%symbol%" to futuresPaymentSymbol)
            ),
            message = LocaleController.getStringWithKeyValues(
                if (isEditing) "\$perps_funding_usdc_increase" else "\$perps_funding_usdc",
                listOf("%minUSDC%" to usdc)
            ),
            buttonTitle = notEnoughText(futuresPaymentSymbol),
            tokenSlug = PERPS_PAYMENT_TOKEN_SLUG
        )

        needsEth -> FuturesFundsHint(
            title = LocaleController.getString("PerpsFundingGasTitle"),
            message = LocaleController.getStringWithKeyValues(
                "\$perps_funding_gas",
                listOf(
                    "%feeETH%" to eth,
                    "%feeFiat%" to (requiredEthUsd.toDoubleOrNull()?.toUsdString() ?: "")
                )
            ),
            buttonTitle = notEnoughText(feeTokenSymbol),
            tokenSlug = MBlockchain.arbitrum.nativeSlug
        )

        else -> null
    }
}

internal fun futuresFeeText(fee: Double): String = if (fee > 0 && fee < MIN_DISPLAYED_FEE) {
    "<${MIN_DISPLAYED_FEE.toUsdString()}"
} else {
    "~${fee.toUsdString()}"
}

internal fun MApiPerpsQuote.formatBridgeFee(): String? =
    bridgeFee.takeIf { funding != PERPS_FUNDING_BALANCE }?.toDoubleOrNull()?.toUsdString()

/** `null` when the quote deposits nothing. */
internal fun MApiPerpsQuote.networkFeeText(): String? {
    estimatedNetworkFeeUsd?.toDoubleOrNull()?.let { return futuresFeeText(it) }
    estimatedNetworkFeeEth?.toDoubleOrNull()?.let {
        return "~${it.toString(
            ETH_DECIMALS,
            feeTokenSymbol,
            ETH_DECIMALS,
            smartDecimals = true,
            forceCurrencyToRight = true
        )}"
    }
    val isDeposit = funding != PERPS_FUNDING_BALANCE && receiveStatus != PERPS_RECEIVE_PENDING &&
        (paymentAmount.toDoubleOrNull() ?: 0.0) > 0
    return if (isDeposit) "—" else null
}

private val feeTokenSymbol: String
    get() = TokenStore.getToken(MBlockchain.arbitrum.nativeSlug)?.symbol ?: "ETH"

private fun notEnoughText(symbol: String) =
    LocaleController.getStringWithKeyValues("Not Enough %symbol%", listOf("%symbol%" to symbol))

private fun String.toFundingAmount(): String = toBigDecimalOrNull()?.toPerpsAmount() ?: this

/** Deposit plus the gasless paymaster reserve. Buying only the deposit leaves the reserve unpaid. */
private fun MApiPerpsFundingRequirements.fundingUsdc(): String {
    val deposit = requiredUsdc.toBigDecimalOrNull() ?: return requiredUsdc
    val gas = requiredGasUsdc.toBigDecimalOrNull() ?: BigDecimal.ZERO
    return deposit.add(gas).toPerpsAmount()
}

/** The text for an SDK error code, as iOS shows it. */
internal fun futuresErrorText(error: String): String {
    val key = PERPS_ERROR_KEYS.firstOrNull { error.contains(it) }
    if (key != null) return LocaleController.getString(key)
    return MBridgeError.fromErrorName(error)?.toLocalized
        ?: LocaleController.getString("PerpsUnavailable")
}

private val PERPS_ERROR_KEYS = listOf(
    "PerpsReviewChanged", "PerpsWithdrawalPending", "PerpsQuoteExpired", "PerpsInsufficientUsdc",
    "PerpsInsufficientBalance", "PerpsMarketNeedsUnifiedAccount", "PerpsInsufficientGas",
    "PerpsAmountTooSmall", "PerpsUnchanged", "PerpsOrderTooSmall", "PerpsOrderNotFilled",
    "PerpsInsufficientMargin", "PerpsOrderRejected", "PerpsPositionChanged", "PerpsPositionExists",
    "PerpsOperationPending", "PerpsUnsupportedAccount", "PerpsInvalidLeverage",
    "PerpsInvalidAmount", "PerpsChangeLeverageSeparately", "PerpsTradingUnavailable",
    "PerpsNothingToWithdraw", "PerpsWithdrawalRejected", "PerpsOrderNotPlaced"
)

internal val futuresPaymentSymbol: String
    get() = TokenStore.getToken(PERPS_PAYMENT_TOKEN_SLUG)?.symbol ?: "USDC"

/** USD collateral as the SDK's decimal string. */
internal fun Double.toPerpsAmount(): String = BigDecimal.valueOf(this).toPerpsAmount()

private fun BigDecimal.toPerpsAmount(): String =
    setScale(USDC_DECIMALS, RoundingMode.DOWN).stripTrailingZeros().toPlainString()

internal const val PERPS_QUOTE_FAILED = "quoteFailed"
internal const val PERPS_QUOTE_EXPIRED_ERROR = "PerpsQuoteExpired"
private const val USDC_DECIMALS = 6
private const val ETH_DECIMALS = 18
private const val MIN_DISPLAYED_FEE = 0.01
private const val PERPS_RECEIVE_PENDING = "pending"

/** A "Title – explanation" string with its title in bold. */
internal fun futuresExplanation(key: String): CharSequence {
    val text = LocaleController.getString(key)
    val titleEnd = text.indexOf(" – ").takeIf { it > 0 } ?: return text
    return SpannableString(text).apply {
        setSpan(StyleSpan(Typeface.BOLD), 0, titleEnd, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
    }
}
