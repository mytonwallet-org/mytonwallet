package org.mytonwallet.app_air.uireceive

import java.lang.ref.WeakReference
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uiinappbrowser.CustomTabsBrowser
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.OnRampCurrencyPolicy

object BuyWithCardLauncher {

    // Null when nothing is offered on this chain, which is the only correct answer: naming a currency
    // of its own here is what would let the app offer one the server withdrew
    fun preferredBaseCurrency(chain: String): MBaseCurrency? {
        val preferred = if (ConfigStore.countryCode == "RU") {
            MBaseCurrency.RUB
        } else {
            WalletCore.baseCurrency
        }
        return OnRampCurrencyPolicy.preferredCurrency(chain, listOf(preferred))
    }

    fun supportedBaseCurrencies(chain: String): List<MBaseCurrency> =
        OnRampCurrencyPolicy.supportedCurrencies(chain)

    fun buyWithCardUrl(
        chain: String,
        baseCurrency: MBaseCurrency,
        onReceive: (url: String?) -> Unit
    ) {
        when (baseCurrency) {
            MBaseCurrency.RUB -> {
                val address = AccountStore.activeAccount?.tonAddress ?: ""
                onReceive(
                    "https://dreamwalkers.io/ru/mytonwallet/?wallet=$address&give=CARDRUB&take=TON&type=buy"
                )
            }

            MBaseCurrency.USD, MBaseCurrency.EUR -> {
                val activeTheme = if (ThemeManager.isDark) "dark" else "light"
                WalletCore.call(
                    ApiMethod.Other.GetMoonpayOnrampUrl(
                        ApiMethod.Other.GetMoonpayOnrampUrl.Params(
                            chain = chain,
                            addressByChain =
                                AccountStore.activeAccount?.addressByChain ?: emptyMap(),
                            theme = activeTheme,
                            currency = baseCurrency.currencyCode
                        )
                    )
                ) { result, _ ->
                    onReceive(result?.url)
                }
            }

            else -> {}
        }
    }

    fun launch(caller: WeakReference<WViewController>, chain: String) {
        // Entry points that cannot observe config updates still route here, so refuse instead of
        // falling back to a currency the server no longer allows
        val baseCurrency = preferredBaseCurrency(chain)
        if (baseCurrency == null) {
            caller.get()?.showError(MBridgeError.Type.SERVER_ERROR)
            return
        }
        buyWithCardUrl(chain, baseCurrency) { url ->
            val context = caller.get()?.context
            if (context != null && url != null) {
                CustomTabsBrowser.open(context, url)
            } else {
                caller.get()?.showError(MBridgeError.Type.SERVER_ERROR)
            }
        }
    }
}
