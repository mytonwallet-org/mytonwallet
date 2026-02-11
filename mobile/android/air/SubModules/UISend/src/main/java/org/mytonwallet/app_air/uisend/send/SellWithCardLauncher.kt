package org.mytonwallet.app_air.uisend.send

import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger

object SellWithCardLauncher {
    private const val OFF_RAMP_BASE_URL = "https://my.tt/offramp/"

    fun launch(
        caller: WeakReference<WViewController>,
        account: MAccount,
        tokenSlug: String,
    ) {
        val callerVC = caller.get() ?: return
        val window = callerVC.window ?: return

        val nav = WNavigationController(window)
        val browserVC = InAppBrowserVC(
            callerVC.view.context,
            null,
            InAppBrowserConfig(
                url = "about:blank",
                title = LocaleController.getString("Sell on Card"),
                injectTonConnectBridge = false,
                forceCloseOnBack = true,
            )
        )
        nav.setRoot(browserVC)
        window.present(nav)

        val token = TokenStore.getToken(tokenSlug)
        val chain = token?.mBlockchain ?: MBlockchain.ton
        val address = account.addressByChain[chain.name] ?: run {
            window.dismissNav(nav)
            return
        }

        val balance =
            BalanceStore.getBalances(account.accountId)?.get(chain.nativeSlug)
                ?: BigInteger.ZERO
        val activeTheme = if (ThemeManager.isDark) "dark" else "light"

        WalletCore.call(
            ApiMethod.Other.GetMoonpayOfframpUrl(
                ApiMethod.Other.GetMoonpayOfframpUrl.Params(
                    chain = chain.name,
                    address = address,
                    theme = activeTheme,
                    currency = WalletCore.baseCurrency.currencyCode,
                    amount = balance.toString(),
                    baseUrl = OFF_RAMP_BASE_URL
                )
            )
        ) { result, _ ->
            result?.url?.let { url ->
                if (nav.isDismissed) return@call
                browserVC.navigate(url)
            } ?: run {
                window.dismissNav(nav)
                if (!WalletCore.isConnected()) {
                    caller.get()?.showError(MBridgeError.SERVER_ERROR)
                }
            }
        }
    }
}
