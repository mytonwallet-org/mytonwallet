package org.mytonwallet.app_air.ledger

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.ledger.connectionManagers.ILedgerConnectionManager
import org.mytonwallet.app_air.ledger.connectionManagers.LedgerBleManager
import org.mytonwallet.app_air.ledger.connectionManagers.LedgerUsbManager
import org.mytonwallet.app_air.walletcore.MAIN_NETWORK
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.LedgerAppInfo
import org.mytonwallet.app_air.walletcore.moshi.MApiTonWallet
import org.mytonwallet.app_air.walletcore.moshi.MApiTonWalletVersion
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

object LedgerManager : WalletCore.EventObserver {
    enum class ConnectionMode {
        BLE,
        USB
    }

    sealed class ConnectionState {
        data object None : ConnectionState()
        data object Connecting : ConnectionState()
        data class ConnectingToTonApp(val device: LedgerDevice) : ConnectionState()
        data class Done(val device: LedgerDevice, val tonAppVersion: String) : ConnectionState()
        data class Error(
            val step: Step,
            val message: String?,
        ) :
            ConnectionState() {
            enum class Step {
                CONNECT,
                TON_APP,
                SIGN;
            }
        }
    }

    private var connectionState: ConnectionState = ConnectionState.None
    private var onUpdate: ((ConnectionState) -> Unit)? = null
    private var activeManager: ILedgerConnectionManager? = null
    var activeMode: ConnectionMode? = null
        set(value) {
            field = value
            activeManager?.stopConnection()
            activeManager = null
        }

    fun init(applicationContext: Context, context: Context) {
        LedgerBleManager.init(context)
        LedgerUsbManager.init(applicationContext)
        WalletCore.registerObserver(this)
    }

    fun startConnection(
        mode: ConnectionMode,
        onUpdate: (ConnectionState) -> Unit
    ) {
        this.onUpdate = onUpdate
        this.activeMode = mode
        when (mode) {
            ConnectionMode.BLE -> {
                activeManager = LedgerBleManager
                LedgerBleManager.startConnection(onUpdate = {
                    Handler(Looper.getMainLooper()).post {
                        connectionState = it
                        this.onUpdate?.invoke(it)
                    }
                })
            }

            ConnectionMode.USB -> {
                activeManager = LedgerUsbManager
                LedgerUsbManager.startConnection(onUpdate = {
                    Handler(Looper.getMainLooper()).post {
                        connectionState = it
                        this.onUpdate?.invoke(it)
                    }
                })
            }
        }
    }

    suspend fun getWalletInfo(walletIndex: Int): MApiTonWallet? {
        return suspendCoroutine { continuation ->
            activeManager?.getPublicKey(walletIndex) { publicKey ->
                if (publicKey == null) {
                    continuation.resume(null)
                    return@getPublicKey
                }

                Handler(Looper.getMainLooper()).post {
                    WalletCore.call(
                        ApiMethod.Auth.AddressFromPublicKey(
                            publicKey,
                            MAIN_NETWORK,
                            MApiTonWalletVersion.V4_R2
                        ), callback = { wallet, error ->
                            if (error != null) {
                                continuation.resume(null)
                            } else {
                                continuation.resume(wallet)
                            }
                        })
                }
            }
        }
    }

    private fun appInfo(): LedgerAppInfo? {
        return activeManager?.appInfo()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.LedgerWriteRequest -> {
                try {
                    activeManager?.write(walletEvent.apdu, onSuccess = {
                        walletEvent.onResponse(it)
                    }, onError = {
                        walletEvent.onResponse("")
                    })
                } catch (_: Throwable) {
                    walletEvent.onResponse("")
                }
            }

            is WalletEvent.LedgerIsJettonIdSupported -> {
                walletEvent.onResponse(activeManager?.appInfo()?.isJettonIdSupported ?: false)
            }

            is WalletEvent.LedgerIsUnsafeSupported -> {
                walletEvent.onResponse(activeManager?.appInfo()?.isUnsafeSupported ?: false)
            }

            else -> {}
        }
    }
}
