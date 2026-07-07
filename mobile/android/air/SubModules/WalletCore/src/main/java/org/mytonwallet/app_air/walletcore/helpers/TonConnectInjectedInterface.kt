package org.mytonwallet.app_air.walletcore.helpers

import android.annotation.SuppressLint
import android.net.Uri
import android.view.MotionEvent
import android.view.View
import android.view.View.OnTouchListener
import android.webkit.JavascriptInterface
import android.webkit.WebView
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload
import org.mytonwallet.app_air.walletcore.moshi.TonConnectConnectRequest
import org.mytonwallet.app_air.walletcore.moshi.TonConnectTransactionPayload
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.inject.ApiDappConnectionRequest
import org.mytonwallet.app_air.walletcore.moshi.inject.ApiDappDisconnectRequest
import org.mytonwallet.app_air.walletcore.moshi.inject.ApiDappPermissions
import org.mytonwallet.app_air.walletcore.moshi.inject.ApiDappRequestedChain
import org.mytonwallet.app_air.walletcore.moshi.inject.ApiDappSignDataRequest
import org.mytonwallet.app_air.walletcore.moshi.inject.ApiDappTransactionRequest
import org.mytonwallet.app_air.walletcore.moshi.inject.DAppInject
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.net.URI
import java.security.SecureRandom

class TonConnectInjectedInterface(
    val webView: WebView,
    val accountId: String,
    val uri: Uri,
    val showError: (error: String) -> Unit
) {
    val origin = uri.scheme + "://" + uri.host

    private var liveAccountId = accountId

    private fun sendInvokeError(invocationId: String, error: String? = "An error occurred!") {
        sendInvokeResponse(
            DAppInject.FunctionInvokeInvokeResult(
                type = "functionResponse",
                invocationId = invocationId,
                status = "rejected",
                data = error
            )
        )
    }

    private fun sendInvokeResult(invocationId: String, result: Any) {
        sendInvokeResponse(
            DAppInject.FunctionInvokeInvokeResult(
                type = "functionResponse",
                invocationId = invocationId,
                status = "fulfilled",
                data = result
            )
        )
    }

    private fun sendInvokeResponse(res: DAppInject.FunctionInvokeInvokeResult) {
        val adapter = WalletCore.moshi.adapter(DAppInject.FunctionInvokeInvokeResult::class.java)
        val json = adapter.toJson(res)
        webView.post {
            webView.evaluateJavascript(
                """
                (function() {
                  window.dispatchEvent(new MessageEvent('message', {
                    data: ${JSONObject.quote(json)}
                  }));
                })();
            """, null
            )
        }
    }

    fun updateAccountId(accountId: String) {
        liveAccountId = accountId
    }

    private fun currentDApp(): ApiMethod.DApp.Inject.DAppArg {
        return ApiMethod.DApp.Inject.DAppArg(
            url = resolveDappOrigin(origin, webView.url),
            urlTrustStatus = "verified",
            accountId = liveAccountId
        )
    }

    @JavascriptInterface
    fun invokeFunc(json: String) {
        val adapter = WalletCore.moshi.adapter(DAppInject.FunctionInvoke::class.java)
        try {
            var parsed = adapter.fromJson(json) ?: return
            if (parsed.args == null) {
                JSONObject(json).optJSONObject("args")?.let { args ->
                    parsed = parsed.copy(args = JSONArray().put(args))
                }
            }
            webView.post { invokeFunc(parsed) }
        } catch (t: Throwable) {
        }
    }

    private fun invokeFunc(invoke: DAppInject.FunctionInvoke) {
        when (invoke.name) {
            "tonConnect:restoreConnection" -> {
                WalletCore.call(
                    ApiMethod.DApp.Inject.TonConnectReconnect(
                        currentDApp(),
                        getRequestId()
                    )
                ) { res, _ ->
                    val protocolData = res?.optJSONObject("session")?.optJSONObject("protocolData")
                    if (protocolData?.optString("event") == "connect") {
                        sendInvokeResult(invoke.invocationId, protocolData)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "tonConnect:connect" -> {
                val args = invoke.args ?: return
                val version = args.getInt(0)
                val protocolDataJson = args.getJSONObject(1)
                if (version > TonConnectHelper.deviceInfo.maxProtocolVersion) {
                    return
                }

                val protocolData = WalletCore.moshi
                    .adapter(TonConnectConnectRequest::class.java)
                    .fromJson(protocolDataJson.toString()) ?: return

                val request = ApiDappConnectionRequest(
                    protocolType = "tonConnect",
                    transport = "inAppBrowser",
                    protocolData = protocolData,
                    permissions = ApiDappPermissions(
                        isAddressRequired = true,
                        isPasswordRequired = false
                    ),
                    requestedChains = listOf(
                        ApiDappRequestedChain(
                            chain = "ton",
                            network = AccountStore.activeAccount?.network?.value
                                ?: MBlockchainNetwork.MAINNET.value
                        )
                    )
                )

                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.TonConnectConnect(
                        currentDApp(),
                        request,
                        getRequestId()
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res?.optBoolean("success") == true) {
                        sendInvokeResult(
                            invoke.invocationId,
                            res.getJSONObject("session").getJSONObject("protocolData")
                        )
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "tonConnect:disconnect" -> {
                val request = ApiDappDisconnectRequest(
                    requestId = getRequestId().toString()
                )
                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.TonConnectDisconnect(
                        currentDApp(),
                        request
                    )
                ) { _, _ ->
                    webView.unlockTouch()
                    sendInvokeResult(invoke.invocationId, JSONObject())
                }
            }

            "tonConnect:send" -> {
                val args = invoke.args ?: return
                val transaction = args.getJSONObject(0)
                val method = transaction.getString("method")
                val id = transaction.get("id").toString()
                webView.lockTouch()
                when (method) {
                    "disconnect" -> {
                        val disconnectRequest = ApiDappDisconnectRequest(
                            requestId = id
                        )
                        WalletCore.call(
                            ApiMethod.DApp.Inject.TonConnectDisconnect(
                                currentDApp(),
                                disconnectRequest
                            )
                        ) { _, _ ->
                            webView.unlockTouch()
                            sendInvokeResult(invoke.invocationId, JSONObject().apply {
                                put("result", JSONObject())
                                put("id", id)
                            })
                        }
                    }

                    "sendTransaction" -> {
                        val payloadJson = transaction.getJSONArray("params").getString(0)
                        val payload = WalletCore.moshi
                            .adapter(TonConnectTransactionPayload::class.java)
                            .fromJson(payloadJson) ?: run {
                            webView.unlockTouch()
                            sendInvokeError(invoke.invocationId)
                            return
                        }
                        val request = ApiDappTransactionRequest(
                            id = id,
                            chain = "ton",
                            payload = payload
                        )
                        WalletCore.call(
                            ApiMethod.DApp.Inject.TonConnectSendTransaction(
                                currentDApp(),
                                request
                            )
                        ) { res, _ ->
                            webView.unlockTouch()
                            if (res?.optBoolean("success") == true) {
                                sendInvokeResult(invoke.invocationId, res.get("result"))
                            } else {
                                sendInvokeError(
                                    invoke.invocationId,
                                    res?.optJSONObject("error")?.optString("message")
                                )
                            }
                        }
                    }

                    "signData" -> {
                        val payloadJson = transaction.getJSONArray("params").getString(0)
                        val payload = WalletCore.moshi
                            .adapter(MSignDataPayload::class.java)
                            .fromJson(payloadJson) ?: run {
                            webView.unlockTouch()
                            sendInvokeError(invoke.invocationId)
                            return
                        }
                        val request = ApiDappSignDataRequest(
                            id = id,
                            chain = "ton",
                            payload = payload
                        )
                        WalletCore.call(
                            ApiMethod.DApp.Inject.TonConnectSignData(
                                currentDApp(),
                                request
                            )
                        ) { res, _ ->
                            webView.unlockTouch()
                            if (res?.optBoolean("success") == true) {
                                sendInvokeResult(invoke.invocationId, res.get("result"))
                            } else {
                                sendInvokeError(
                                    invoke.invocationId,
                                    res?.optJSONObject("error")?.optString("message")
                                )
                            }
                        }
                    }

                    else -> {
                        webView.unlockTouch()
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "walletConnect:connect" -> {
                val args = invoke.args ?: return
                val request = args.optJSONObject(0) ?: return
                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectConnect(
                        currentDApp(),
                        request,
                        getRequestId()
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res != null) {
                        sendInvokeResult(invoke.invocationId, res)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "walletConnect:reconnect" -> {
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectReconnect(
                        currentDApp(),
                        getRequestId()
                    )
                ) { res, _ ->
                    if (res != null) {
                        sendInvokeResult(invoke.invocationId, res)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "walletConnect:disconnect" -> {
                val args = invoke.args ?: return
                val request = args.optJSONObject(0) ?: return
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectDisconnect(
                        currentDApp(),
                        request
                    )
                ) { res, _ ->
                    if (res != null) {
                        sendInvokeResult(invoke.invocationId, res)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "walletConnect:sendTransaction" -> {
                val args = invoke.args ?: return
                val request = args.optJSONObject(0) ?: return
                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectSendTransaction(
                        currentDApp(),
                        request
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res != null) {
                        sendInvokeResult(invoke.invocationId, res)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "walletConnect:signData" -> {
                val args = invoke.args ?: return
                val request = args.optJSONObject(0) ?: return
                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectSignData(
                        currentDApp(),
                        request
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res != null) {
                        sendInvokeResult(invoke.invocationId, res)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            // Silent readonly RPC proxy. No lockTouch — these are read-only forwards
            // (eth_blockNumber/eth_call/eth_estimateGas/...) to our backend RPC; the
            // user-facing UI remains responsive.
            "walletConnect:proxyEvmRpc" -> {
                val args = invoke.args ?: return
                val request = args.optJSONObject(0) ?: return
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectProxyEvmRpc(
                        currentDApp(),
                        request
                    )
                ) { res, _ ->
                    if (res != null) {
                        sendInvokeResult(invoke.invocationId, res)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "window:open" -> {
                val url = invoke.args?.optJSONObject(0)?.optString("url") ?: return
                val routingDecision = WindowOpenUrlRoutingDecision.resolve(url) { deeplink, source ->
                    WalletContextManager.delegate?.get()?.handleDeeplink(deeplink, source) == true
                }
                if (routingDecision == WindowOpenUrlRoutingDecision.LOAD_URL) {
                    webView.loadUrl(url)
                }
            }

            "window:close" -> {}
        }
    }

    private fun getRequestId() = SecureRandom().nextInt()
}

internal fun resolveDappOrigin(initialOrigin: String, liveUrl: String?): String {
    if (liveUrl.isNullOrBlank()) {
        return initialOrigin
    }

    val liveUri = try {
        URI(liveUrl)
    } catch (_: Throwable) {
        return initialOrigin
    }
    val liveScheme = liveUri.scheme ?: return initialOrigin
    val liveHost = liveUri.host ?: return initialOrigin

    return "$liveScheme://$liveHost"
}

fun WebView.lockTouch() {
    @SuppressLint("ClickableViewAccessibility")
    setOnTouchListener(OnTouchListener { v: View?, event: MotionEvent? -> true })
}

fun WebView.unlockTouch() {
    setOnTouchListener(null)
}
