package org.mytonwallet.app_air.uireceive

import androidx.lifecycle.ViewModel
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.getMoonpayOnrampUrl
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
                WalletCore.getMoonpayOnrampUrl(
                    chain,
                    AccountStore.activeAccount?.addressByChain[chain] ?: "",
                    activeTheme,
                    currency = baseCurrency.currencyCode,
                    callback = { result ->
                        onReceive(result?.get("url"))
                    }
                )
            }

            else -> {}
        }
    }

}
