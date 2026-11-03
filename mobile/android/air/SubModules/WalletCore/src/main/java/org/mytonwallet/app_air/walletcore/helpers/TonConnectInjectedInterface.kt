package org.mytonwallet.app_air.walletcore.helpers

import android.annotation.SuppressLint
import android.view.MotionEvent
import android.view.View
import android.view.View.OnTouchListener
import android.webkit.WebView
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.security.SecureRandom
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiDappUrlTrustStatus
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

class TonConnectInjectedInterface(
    val webView: WebView,
    val accountId: String,
    val showError: (error: String) -> Unit,
    val openNonWebUrl: (url: String) -> Unit
) {
    companion object {
        val isSupported: Boolean
            get() = WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)
    }

    private var liveAccountId = accountId

    // Every frame gets the `_mytonwallet` object; only main-frame messages from http(s) origins
    // are handled.
    private val messageListener =
        WebViewCompat.WebMessageListener { _, message, sourceOrigin, isMainFrame, _ ->
            val context = resolveDappMessageContext(
                isMainFrame,
                sourceOrigin.scheme,
                sourceOrigin.host,
                sourceOrigin.port
            ) ?: return@WebMessageListener
            if (message.type != WebMessageCompat.TYPE_STRING) return@WebMessageListener
            handleMessage(message.data ?: return@WebMessageListener, context)
        }

    // Requires `isSupported`. Takes effect for documents loaded after the call.
    fun install() {
        WebViewCompat.addWebMessageListener(
            webView,
            TonConnectHelper.TON_CONNECT_WALLET_JS_BRIDGE_INTERFACE,
            setOf("*"),
            messageListener
        )
    }

    fun uninstall() {
        WebViewCompat.removeWebMessageListener(
            webView,
            TonConnectHelper.TON_CONNECT_WALLET_JS_BRIDGE_INTERFACE
        )
    }

    private fun sendInvokeError(
        context: DappMessageContext,
        invocationId: String,
        error: String? = "An error occurred!"
    ) {
        sendInvokeResponse(
            context,
            DAppInject.FunctionInvokeInvokeResult(
                type = "functionResponse",
                invocationId = invocationId,
                status = "rejected",
                data = error
            )
        )
    }

    private fun sendInvokeResult(context: DappMessageContext, invocationId: String, result: Any) {
        sendInvokeResponse(
            context,
            DAppInject.FunctionInvokeInvokeResult(
                type = "functionResponse",
                invocationId = invocationId,
                status = "fulfilled",
                data = result
            )
        )
    }

    // Delivered only while the main frame still shows the origin that sent the request.
    private fun sendInvokeResponse(
        context: DappMessageContext,
        res: DAppInject.FunctionInvokeInvokeResult
    ) {
        val adapter = WalletCore.moshi.adapter(DAppInject.FunctionInvokeInvokeResult::class.java)
        val json = adapter.toJson(res)
        webView.post {
            webView.evaluateJavascript(
                """
                (function() {
                  if (window.location.origin !== ${JSONObject.quote(context.origin)}) return;
                  window.dispatchEvent(new MessageEvent('message', {
                    data: ${JSONObject.quote(json)}
                  }));
                })();
            """,
                null
            )
        }
    }

    fun updateAccountId(accountId: String) {
        liveAccountId = accountId
    }

    private fun currentDApp(context: DappMessageContext): ApiMethod.DApp.Inject.DAppArg =
        ApiMethod.DApp.Inject.DAppArg(
            url = context.origin,
            urlTrustStatus = context.urlTrustStatus.rawValue,
            accountId = liveAccountId
        )

    private fun handleMessage(json: String, context: DappMessageContext) {
        val adapter = WalletCore.moshi.adapter(DAppInject.FunctionInvoke::class.java)
        val invoke = try {
            var parsed = adapter.fromJson(json) ?: return
            if (parsed.args == null) {
                JSONObject(json).optJSONObject("args")?.let { args ->
                    parsed = parsed.copy(args = JSONArray().put(args))
                }
            }
            parsed
        } catch (_: Throwable) {
            return
        }
        webView.post { invokeFunc(invoke, context) }
    }

    private fun invokeFunc(invoke: DAppInject.FunctionInvoke, context: DappMessageContext) {
        when (invoke.name) {
            "tonConnect:restoreConnection" -> {
                WalletCore.call(
                    ApiMethod.DApp.Inject.TonConnectReconnect(
                        currentDApp(context),
                        getRequestId()
                    )
                ) { res, _ ->
                    val protocolData = res?.optJSONObject("session")?.optJSONObject("protocolData")
                    if (protocolData?.optString("event") == "connect") {
                        sendInvokeResult(context, invoke.invocationId, protocolData)
                    } else {
                        sendInvokeError(context, invoke.invocationId)
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
                        currentDApp(context),
                        request,
                        getRequestId()
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res?.optBoolean("success") == true) {
                        sendInvokeResult(
                            context,
                            invoke.invocationId,
                            res.getJSONObject("session").getJSONObject("protocolData")
                        )
                    } else {
                        sendInvokeError(context, invoke.invocationId)
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
                        currentDApp(context),
                        request
                    )
                ) { _, _ ->
                    webView.unlockTouch()
                    sendInvokeResult(context, invoke.invocationId, JSONObject())
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
                                currentDApp(context),
                                disconnectRequest
                            )
                        ) { _, _ ->
                            webView.unlockTouch()
                            sendInvokeResult(
                                context,
                                invoke.invocationId,
                                JSONObject().apply {
                                    put("result", JSONObject())
                                    put("id", id)
                                }
                            )
                        }
                    }

                    "sendTransaction" -> {
                        val payloadJson = transaction.getJSONArray("params").getString(0)
                        val payload = WalletCore.moshi
                            .adapter(TonConnectTransactionPayload::class.java)
                            .fromJson(payloadJson) ?: run {
                            webView.unlockTouch()
                            sendInvokeError(context, invoke.invocationId)
                            return
                        }
                        val request = ApiDappTransactionRequest(
                            id = id,
                            chain = "ton",
                            payload = payload
                        )
                        WalletCore.call(
                            ApiMethod.DApp.Inject.TonConnectSendTransaction(
                                currentDApp(context),
                                request
                            )
                        ) { res, _ ->
                            webView.unlockTouch()
                            if (res?.optBoolean("success") == true) {
                                sendInvokeResult(context, invoke.invocationId, res.get("result"))
                            } else {
                                sendInvokeError(
                                    context,
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
                            sendInvokeError(context, invoke.invocationId)
                            return
                        }
                        val request = ApiDappSignDataRequest(
                            id = id,
                            chain = "ton",
                            payload = payload
                        )
                        WalletCore.call(
                            ApiMethod.DApp.Inject.TonConnectSignData(
                                currentDApp(context),
                                request
                            )
                        ) { res, _ ->
                            webView.unlockTouch()
                            if (res?.optBoolean("success") == true) {
                                sendInvokeResult(context, invoke.invocationId, res.get("result"))
                            } else {
                                sendInvokeError(
                                    context,
                                    invoke.invocationId,
                                    res?.optJSONObject("error")?.optString("message")
                                )
                            }
                        }
                    }

                    else -> {
                        webView.unlockTouch()
                        sendInvokeError(context, invoke.invocationId)
                    }
                }
            }

            "walletConnect:connect" -> {
                val args = invoke.args ?: return
                val request = args.optJSONObject(0) ?: return
                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectConnect(
                        currentDApp(context),
                        request,
                        getRequestId()
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res != null) {
                        sendInvokeResult(context, invoke.invocationId, res)
                    } else {
                        sendInvokeError(context, invoke.invocationId)
                    }
                }
            }

            "walletConnect:reconnect" -> {
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectReconnect(
                        currentDApp(context),
                        getRequestId()
                    )
                ) { res, _ ->
                    if (res != null) {
                        sendInvokeResult(context, invoke.invocationId, res)
                    } else {
                        sendInvokeError(context, invoke.invocationId)
                    }
                }
            }

            "walletConnect:disconnect" -> {
                val args = invoke.args ?: return
                val request = args.optJSONObject(0) ?: return
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectDisconnect(
                        currentDApp(context),
                        request
                    )
                ) { res, _ ->
                    if (res != null) {
                        sendInvokeResult(context, invoke.invocationId, res)
                    } else {
                        sendInvokeError(context, invoke.invocationId)
                    }
                }
            }

            "walletConnect:sendTransaction" -> {
                val args = invoke.args ?: return
                val request = args.optJSONObject(0) ?: return
                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectSendTransaction(
                        currentDApp(context),
                        request
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res != null) {
                        sendInvokeResult(context, invoke.invocationId, res)
                    } else {
                        sendInvokeError(context, invoke.invocationId)
                    }
                }
            }

            "walletConnect:signData" -> {
                val args = invoke.args ?: return
                val request = args.optJSONObject(0) ?: return
                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.WalletConnectSignData(
                        currentDApp(context),
                        request
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res != null) {
                        sendInvokeResult(context, invoke.invocationId, res)
                    } else {
                        sendInvokeError(context, invoke.invocationId)
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
                        currentDApp(context),
                        request
                    )
                ) { res, _ ->
                    if (res != null) {
                        sendInvokeResult(context, invoke.invocationId, res)
                    } else {
                        sendInvokeError(context, invoke.invocationId)
                    }
                }
            }

            "window:open" -> {
                val url = invoke.args?.optJSONObject(0)?.optString("url") ?: return
                val routingDecision = WindowOpenUrlRoutingDecision.resolve(url) {
                        deeplink,
                        source
                    ->
                    WalletContextManager.delegate?.get()?.handleDeeplink(deeplink, source) == true
                }
                when (routingDecision) {
                    WindowOpenUrlRoutingDecision.LOAD_URL -> webView.loadUrl(url)
                    WindowOpenUrlRoutingDecision.OPEN_NON_WEB_URL -> openNonWebUrl(url)
                    WindowOpenUrlRoutingDecision.CONSUME, WindowOpenUrlRoutingDecision.IGNORE -> {}
                }
            }

            "window:close" -> {}
        }
    }

    private fun getRequestId() = SecureRandom().nextInt()
}

internal data class DappMessageContext(
    val origin: String,
    val urlTrustStatus: ApiDappUrlTrustStatus
)

// Accepts main-frame messages from http(s) origins only. Takes the `android.net.Uri` scheme,
// host and port of the message's source origin and returns the origin as `window.location.origin`
// serializes it: `scheme://host[:port]`, lowercase, without a default port. Only https counts as
// verified.
internal fun resolveDappMessageContext(
    isMainFrame: Boolean,
    scheme: String?,
    host: String?,
    port: Int
): DappMessageContext? {
    if (!isMainFrame) return null
    val originScheme = scheme?.lowercase(Locale.US) ?: return null
    if (originScheme != "http" && originScheme != "https") return null
    val originHost = host?.lowercase(Locale.US)?.takeIf { it.isNotEmpty() } ?: return null
    val isDefaultPort = port == -1 ||
        (originScheme == "http" && port == 80) ||
        (originScheme == "https" && port == 443)
    return DappMessageContext(
        origin = if (isDefaultPort) {
            "$originScheme://$originHost"
        } else {
            "$originScheme://$originHost:$port"
        },
        urlTrustStatus = if (originScheme == "https") {
            ApiDappUrlTrustStatus.VERIFIED
        } else {
            ApiDappUrlTrustStatus.UNKNOWN
        }
    )
}

fun WebView.lockTouch() {
    @SuppressLint("ClickableViewAccessibility")
    setOnTouchListener(OnTouchListener { v: View?, event: MotionEvent? -> true })
}

fun WebView.unlockTouch() {
    setOnTouchListener(null)
}
