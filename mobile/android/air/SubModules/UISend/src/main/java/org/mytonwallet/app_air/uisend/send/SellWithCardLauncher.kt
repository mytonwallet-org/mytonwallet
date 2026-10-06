package org.mytonwallet.app_air.uisend.send

import java.lang.ref.WeakReference
import java.math.BigDecimal
import java.math.BigInteger
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uiinappbrowser.CustomTabsBrowser
import org.mytonwallet.app_air.uisend.send.helpers.TransferHelpers
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiAnyDisplayError
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

object SellWithCardLauncher {
    private val offRampBaseUrl: String
        get() = "https://${ApplicationContextHolder.universalShortUrlHost}/offramp/"
    private val OFFRAMP_PREFILL_MAX_AMOUNT = BigDecimal("2000")

    // / https://support.moonpay.com/en/articles/362475-moonpay-s-supported-currencies
    // / Ordered by priority
    private val SUPPORTED_CURRENCIES = listOf(MBaseCurrency.USD, MBaseCurrency.EUR)

    private val LIMITS_BY_SLUG = mapOf(TONCOIN_SLUG to OFFRAMP_PREFILL_MAX_AMOUNT)

    fun supportedCurrencies(): List<MBaseCurrency> {
        val allowed = ConfigStore.allowedOnOffRampCurrencies
        return SUPPORTED_CURRENCIES.filter { allowed == null || allowed.contains(it) }
    }

    /** The largest native amount that can be sold, leaving the network fee of the transfer. */
    suspend fun maximumAmount(
        accountId: String,
        token: IApiToken,
        balance: BigInteger
    ): BigInteger {
        val chain = token.mBlockchain ?: throw IllegalStateException("Unknown chain")
        var amount = if (chain.canTransferFullNativeBalance) {
            balance
        } else {
            val feeCheckAddress = chain.feeCheckAddress
                ?: throw IllegalStateException("No fee check address")
            val draft = try {
                WalletCore.call(
                    ApiMethod.Transfer.CheckTransactionDraft(
                        chain,
                        MApiCheckTransactionDraftOptions(
                            accountId = accountId,
                            toAddress = feeCheckAddress,
                            amount = balance,
                            tokenAddress = null,
                            stateInit = null,
                            allowGasless = null,
                            payload = null
                        )
                    )
                )
            } catch (error: JSWebViewBridge.ApiError) {
                if (error.parsed.type != MBridgeError.Type.INSUFFICIENT_BALANCE) throw error
                error.parsedResult as? MApiCheckTransactionDraftResult ?: throw error
            }
            val explainedFee = draft.explainedFee
            val fullFee = explainedFee?.fullFee
            // A full-balance probe can still provide the fee needed to reduce the amount.
            if (draft.error != null &&
                (draft.error != MApiAnyDisplayError.INSUFFICIENT_BALANCE || fullFee == null)
            ) {
                throw IllegalStateException("Fee estimation failed: ${draft.error}")
            }
            fullFee ?: throw IllegalStateException("Fee estimation failed")
            TransferHelpers.getMaxTransferAmount(
                tokenBalance = balance,
                isNativeToken = true,
                fullFee = fullFee.terms,
                canTransferFullBalance = explainedFee.canTransferFullBalance
            ) ?: balance
        }
        LIMITS_BY_SLUG[token.slug]?.let { limit ->
            CoinUtils.fromDecimal(limit, token.decimals)?.let { amount = amount.min(it) }
        }
        return amount.max(BigInteger.ZERO)
    }

    fun launch(
        caller: WeakReference<WViewController>,
        account: MAccount,
        tokenSlug: String,
        requestedAmount: BigInteger? = null,
        requestedCurrency: MBaseCurrency? = null
    ) {
        val token = TokenStore.getToken(tokenSlug)
        val chain = token?.mBlockchain ?: MBlockchain.ton
        val address = account.addressByChain[chain.name] ?: run {
            return
        }

        val nativeTokenDecimals = TokenStore.getToken(chain.nativeSlug)?.decimals ?: 9
        val amount = if (requestedAmount != null) {
            CoinUtils.toDecimalString(requestedAmount, nativeTokenDecimals)
        } else {
            val balance =
                BalanceStore.getBalances(account.accountId)?.get(chain.nativeSlug)
                    ?: BigInteger.ZERO
            val balanceDecimal = balance.toBigDecimal(nativeTokenDecimals)
            balanceDecimal.min(OFFRAMP_PREFILL_MAX_AMOUNT).stripTrailingZeros().toPlainString()
        }
        val activeTheme = if (ThemeManager.isDark) "dark" else "light"
        val preferredCurrency = requestedCurrency ?: WalletCore.baseCurrency
        val currency = SUPPORTED_CURRENCIES.firstOrNull { it == preferredCurrency }
            ?: SUPPORTED_CURRENCIES.first()

        WalletCore.call(
            ApiMethod.Other.GetMoonpayOfframpUrl(
                ApiMethod.Other.GetMoonpayOfframpUrl.Params(
                    chain = chain.name,
                    address = address,
                    theme = activeTheme,
                    currency = currency.currencyCode,
                    amount = amount,
                    baseUrl = offRampBaseUrl
                )
            ),
            callback = { result, error ->
                val context = caller.get()?.context
                val url = result?.url
                if (context != null && url != null) {
                    CustomTabsBrowser.open(context, url)
                } else {
                    caller.get()?.showError(error?.parsed ?: MBridgeError.Type.SERVER_ERROR)
                }
            }
        )
    }
}
