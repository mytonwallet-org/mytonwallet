package org.mytonwallet.app_air.uisend.send

import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uiinappbrowser.CustomTabsBrowser
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigDecimal
import java.math.BigInteger

object SellWithCardLauncher {
    private const val OFF_RAMP_BASE_URL = "https://my.tt/offramp/"
    private val OFFRAMP_PREFILL_MAX_AMOUNT = BigDecimal("2000")

    /// https://support.moonpay.com/en/articles/362475-moonpay-s-supported-currencies
    /// Ordered by priority
    private val SUPPORTED_CURRENCIES = listOf(MBaseCurrency.USD, MBaseCurrency.EUR)

    fun launch(
        caller: WeakReference<WViewController>,
        account: MAccount,
        tokenSlug: String,
    ) {
        val token = TokenStore.getToken(tokenSlug)
        val chain = token?.mBlockchain ?: MBlockchain.ton
        val address = account.addressByChain[chain.name] ?: run {
            return
        }

        val balance =
            BalanceStore.getBalances(account.accountId)?.get(chain.nativeSlug)
                ?: BigInteger.ZERO
        val nativeTokenDecimals = TokenStore.getToken(chain.nativeSlug)?.decimals ?: 9
        val balanceDecimal = balance.toBigDecimal(nativeTokenDecimals)
        val amount =
            balanceDecimal.min(OFFRAMP_PREFILL_MAX_AMOUNT).stripTrailingZeros().toPlainString()
        val activeTheme = if (ThemeManager.isDark) "dark" else "light"
        val currency = SUPPORTED_CURRENCIES.firstOrNull { it == WalletCore.baseCurrency }
            ?: SUPPORTED_CURRENCIES.first()

        WalletCore.call(
            ApiMethod.Other.GetMoonpayOfframpUrl(
                ApiMethod.Other.GetMoonpayOfframpUrl.Params(
                    chain = chain.name,
                    address = address,
                    theme = activeTheme,
                    currency = currency.currencyCode,
                    amount = amount,
                    baseUrl = OFF_RAMP_BASE_URL,
                ),
            ),
            callback = { result, _ ->
                val context = caller.get()?.context
                val url = result?.url
                if (context != null && url != null) {
                    CustomTabsBrowser.open(context, url)
                } else if (!WalletCore.isConnected()) {
                    caller.get()?.showError(MBridgeError.SERVER_ERROR)
                }
            }
        )
    }
}
