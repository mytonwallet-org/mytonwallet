package org.mytonwallet.app_air.walletcore

import android.content.Context
import android.webkit.WebView
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.logger.Logger

/**
 * Reads the Play Install Referrer once, sanitises it into a canonical bucket, and delivers it to
 * `window.airBridge.setInstallChannel(...)`. Fire-and-forget: a successful or permanently-failed
 * read delivers a bucket (`unknown` on permanent failure) so the install is attributed; a transient
 * failure delivers nothing and the next launch retries. Asynchronous, so it never blocks boot.
 */
object InstallReferrerChannel {

    fun deliver(context: Context, webView: WebView) {
        val client = InstallReferrerClient.newBuilder(context.applicationContext).build()
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    try {
                        handleResponse(responseCode, client, webView)
                    } catch (e: Exception) {
                        // Transient (binder/service hiccup): deliver nothing and let the next
                        // launch retry. Delivering `unknown` here would latch the JS claim and
                        // drop a later real referrer; a device with no Play services reports
                        // FEATURE_NOT_SUPPORTED as a response code above, not an exception.
                        Logger.e(
                            Logger.LogTag.JS_WEBVIEW_BRIDGE,
                            "InstallReferrerChannel: read failed error=${e.javaClass.simpleName}"
                        )
                    } finally {
                        try {
                            client.endConnection()
                        } catch (_: Exception) {
                        }
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    // No retry this launch; the claim is idempotent across launches.
                    try {
                        client.endConnection()
                    } catch (_: Exception) {
                    }
                }
            })
        } catch (e: Exception) {
            // Connection failure is transient; the next launch retries.
            Logger.e(
                Logger.LogTag.JS_WEBVIEW_BRIDGE,
                "InstallReferrerChannel: connection failed error=${e.javaClass.simpleName}"
            )
            try {
                client.endConnection()
            } catch (_: Exception) {
            }
        }
    }

    private fun handleResponse(responseCode: Int, client: InstallReferrerClient, webView: WebView) {
        when (responseCode) {
            InstallReferrerClient.InstallReferrerResponse.OK ->
                deliverChannel(
                    webView,
                    sanitizeInstallAttribution(client.installReferrer.installReferrer)
                )

            // SERVICE_UNAVAILABLE is transient; leave it for the next launch to retry.
            InstallReferrerClient.InstallReferrerResponse.SERVICE_UNAVAILABLE -> Unit

            // Any other code is permanent (no Play services, developer or permission error):
            // deliver the fallback bucket so the install is still attributed.
            else -> deliverChannel(webView, sanitizeInstallAttribution(null))
        }
    }

    // The referrer is untrusted input, so the channel is escaped with
    // JSONObject.quote and NEVER string-interpolated into the evaluated script.
    private fun deliverChannel(webView: WebView, attribution: InstallAttribution) {
        val script = if (attribution.isTechnical) {
            "window.airBridge?.setInstallChannel(" + JSONObject.quote(attribution.channel) +
                ",undefined," +
                (attribution.technicalKind?.let { JSONObject.quote(it) } ?: "undefined") + ")"
        } else {
            // Serialize into a quoted JS string; escaping separators also supports pre-ES2019 parsers.
            val json = JSONObject.quote(attribution.toJson().toString())
                .replace("\u2028", "\\u2028")
                .replace("\u2029", "\\u2029")
            "window.airBridge?.captureInstallAttribution(JSON.parse($json))"
        }
        webView.post {
            try {
                webView.evaluateJavascript(script, null)
            } catch (e: Exception) {
                // WebView may already be destroyed by the time this runs; a lost delivery
                // must not crash the app.
                Logger.e(
                    Logger.LogTag.JS_WEBVIEW_BRIDGE,
                    "InstallReferrerChannel: eval failed error=${e.javaClass.simpleName}"
                )
            }
        }
    }
}
