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
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.inject.DAppInject
import java.security.SecureRandom

class TonConnectInjectedInterface(
    val webView: WebView,
    val accountId: String,
    val uri: Uri,
    val showError: (error: String) -> Unit
) {
    val origin = uri.scheme + "://" + uri.host
    private val dApp =
        ApiMethod.DApp.Inject.DAppArg(url = origin, isUrlEnsured = true, accountId = accountId)

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
            "restoreConnection" -> {
                WalletCore.call(
                    ApiMethod.DApp.Inject.TonConnectReconnect(
                        dApp,
                        getRequestId()
                    )
                ) { res, _ ->
                    if (res?.getString("event") == "connect") {
                        sendInvokeResult(invoke.invocationId, res)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "connect" -> {
                val args = invoke.args ?: return
                val version = args.getInt(0)
                val request = args.getJSONObject(1)
                if (version > TonConnectHelper.deviceInfo.maxProtocolVersion) {
                    return
                }

                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.TonConnectConnect(
                        dApp,
                        request,
                        getRequestId()
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res?.getString("event") == "connect") {
                        sendInvokeResult(invoke.invocationId, res)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "disconnect" -> {
                val request = ApiMethod.DApp.Inject.TonConnectDisconnect.Request(
                    id = getRequestId().toString()
                )
                webView.lockTouch()
                WalletCore.call(
                    ApiMethod.DApp.Inject.TonConnectDisconnect(
                        dApp,
                        request
                    )
                ) { res, _ ->
                    webView.unlockTouch()
                    if (res?.has("result") == true) {
                        sendInvokeResult(invoke.invocationId, res)
                    } else {
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "send" -> {
                val args = invoke.args ?: return
                val transaction =
                    args.getJSONObject(0)         // only the first request is handled to match web version
                val param = transaction.getJSONArray("params").getString(0)
                val request = ApiMethod.DApp.Inject.TonConnectSendTransaction.Request(
                    id = transaction.getString("id"),
                    params = listOf(param),
                    method = transaction.getString("method")
                )
                webView.lockTouch()
                when (request.method) {
                    "sendTransaction" -> {
                        WalletCore.call(
                            ApiMethod.DApp.Inject.TonConnectSendTransaction(
                                dApp,
                                request
                            )
                        ) { res, _ ->
                            webView.unlockTouch()
                            if (res?.has("result") == true) {
                                sendInvokeResult(invoke.invocationId, res)
                            } else {
                                sendInvokeError(invoke.invocationId)
                            }
                        }
                    }

                    "signData" -> {
                        WalletCore.call(
                            ApiMethod.DApp.Inject.TonConnectSignData(
                                dApp,
                                request
                            )
                        ) { res, _ ->
                            webView.unlockTouch()
                            if (res?.has("result") == true) {
                                sendInvokeResult(invoke.invocationId, res)
                            } else {
                                sendInvokeError(invoke.invocationId)
                            }
                        }
                    }

                    else -> {
                        webView.unlockTouch()
                        sendInvokeError(invoke.invocationId)
                    }
                }
            }

            "window:open" -> {
                val url = invoke.args?.optJSONObject(0)?.optString("url") ?: return
                webView.loadUrl(url)
            }

            "window:close" -> {}
        }
    }

    private fun getRequestId() = SecureRandom().nextInt()
}

fun WebView.lockTouch() {
    @SuppressLint("ClickableViewAccessibility")
    setOnTouchListener(OnTouchListener { v: View?, event: MotionEvent? -> true })
}

fun WebView.unlockTouch() {
    setOnTouchListener(null)
}
