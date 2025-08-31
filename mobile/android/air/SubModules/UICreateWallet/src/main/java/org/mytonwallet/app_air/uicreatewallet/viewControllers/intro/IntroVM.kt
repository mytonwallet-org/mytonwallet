package org.mytonwallet.app_air.uicreatewallet.viewControllers.intro

import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import java.lang.ref.WeakReference

class IntroVM(delegate: Delegate) {
    interface Delegate {
        fun mnemonicGenerated(words: Array<String>)
        fun showError(error: MBridgeError?)
    }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    fun createWallet() {
        WalletCore.doOnBridgeReady {
            WalletCore.call(ApiMethod.Auth.GenerateMnemonic(), callback = { words, err ->
                if (words != null) {
                    delegate.get()?.mnemonicGenerated(words)
                } else {
                    delegate.get()?.showError(err?.parsed)
                }
            })
        }
    }
}
