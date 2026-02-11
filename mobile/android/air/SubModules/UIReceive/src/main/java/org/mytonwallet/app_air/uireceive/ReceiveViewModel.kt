package org.mytonwallet.app_air.uireceive

import androidx.lifecycle.ViewModel
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class ReceiveViewModel : ViewModel() {

    fun buyWithCardUrl(
        chain: String,
        baseCurrency: MBaseCurrency,
        onReceive: (url: String?) -> Unit
    ) {
        when (baseCurrency) {
            MBaseCurrency.RUB -> {
                val address = AccountStore.activeAccount?.tonAddress ?: ""
                onReceive("https://dreamwalkers.io/ru/mytonwallet/?wallet=$address&give=CARDRUB&take=TON&type=buy")
            }

            MBaseCurrency.USD, MBaseCurrency.EUR -> {
                val activeTheme = if (ThemeManager.isDark) "dark" else "light"
                WalletCore.call(
                    ApiMethod.Other.GetMoonpayOnrampUrl(
                        ApiMethod.Other.GetMoonpayOnrampUrl.Params(
                            chain = chain,
                            address = AccountStore.activeAccount?.addressByChain[chain] ?: "",
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

}
