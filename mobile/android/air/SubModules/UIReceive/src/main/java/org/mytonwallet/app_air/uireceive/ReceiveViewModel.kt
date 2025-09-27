package org.mytonwallet.app_air.uireceive

import android.os.Handler
import android.os.Looper
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.getMoonpayOnrampUrl

class ReceiveViewModel : ViewModel() {

    val buyWithCardUrls = mutableMapOf<String, String>()

    var redirectBuyWithCardSymbol: String? = null
    var failedToGetUrlOnce: Boolean = false

    fun getBuyWithCardUrl(tokenSymbol: String) {
        viewModelScope.launch {
            try {
                val activeTheme = if (ThemeManager.isDark) "dark" else "light"
                val result = WalletCore.getMoonpayOnrampUrl(
                    tokenSymbol,
                    activeTheme
                )
                val url = result["url"]
                if (!url.isNullOrBlank()) {
                    buyWithCardUrls[tokenSymbol] = url
                    if (!redirectBuyWithCardSymbol.isNullOrBlank())
                        _eventsFlow.tryEmit(VmToVcEvents.OpenBuyWithCard)
                }
                return@launch
            } catch (e: JSWebViewBridge.ApiError) {
                e.printStackTrace()
            } catch (e: Throwable) {
                e.printStackTrace()
            }
            failedToGetUrlOnce = true
            Handler(Looper.getMainLooper()).postDelayed({
                getBuyWithCardUrl(tokenSymbol)
            }, 1000)
        }
    }

    private val _eventsFlow: MutableSharedFlow<VmToVcEvents> =
        MutableSharedFlow(replay = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val eventsFlow = _eventsFlow.asSharedFlow()

    sealed class VmToVcEvents {
        object OpenBuyWithCard : VmToVcEvents()
    }

}
