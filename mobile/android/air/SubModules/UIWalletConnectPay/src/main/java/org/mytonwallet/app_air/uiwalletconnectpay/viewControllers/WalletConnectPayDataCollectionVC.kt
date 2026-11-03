package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.constraintlayout.widget.ConstraintLayout
import org.json.JSONObject
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor", "SetJavaScriptEnabled")
class WalletConnectPayDataCollectionVC(
    context: Context,
    private val url: String,
    private val onComplete: () -> Unit,
    private val onError: (String) -> Unit,
    private val onClosed: () -> Unit
) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "WalletConnectPayDataCollection"

    override val ignoreSideGuttering = true
    override val shouldDisplayBottomBar = true
    override val forceBlurBottomView = true

    private var finished = false

    private val expectedOrigin: String? = runCatching {
        java.net.URI(url).let { "${it.scheme}://${it.authority}" }
    }.getOrNull()

    private val webView: WebView by lazy {
        WebView(context).apply {
            id = WebView.generateViewId()
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccessFromFileURLs = false
            settings.allowUniversalAccessFromFileURLs = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setWebViewClient(object : android.webkit.WebViewClient() {
                override fun onPageFinished(view: WebView?, pageUrl: String?) {
                    super.onPageFinished(view, pageUrl)
                    evaluateJavascript(MESSAGE_LISTENER_JS, null)
                }

                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: WebResourceRequest
                ): Boolean {
                    val scheme = request.url.scheme?.lowercase()
                    if (scheme == "http" || scheme == "https") return false
                    return openExternally(request.url.toString())
                }
            })
            addJavascriptInterface(messageBridge, JS_INTERFACE)
        }
    }

    private val messageBridge = object {
        @JavascriptInterface
        fun onMessage(origin: String, data: String) {
            if (expectedOrigin != null && origin != expectedOrigin) return
            webView.post { handleMessage(data) }
        }

        @JavascriptInterface
        fun postMessage(data: String) {
            webView.post { handleMessage(data) }
        }
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)
        setNavTitle(LocaleController.getString("Payment"))
        navigationBar?.addCloseButton {
            navigationController?.window?.dismissLastNav()
        }

        view.addView(
            webView,
            ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        applyWebViewConstraints()

        webView.loadUrl(url)
        updateTheme()
    }

    private fun applyWebViewConstraints() {
        val systemBars = navigationController?.getSystemBars()
        view.setConstraints {
            toTopPx(
                webView,
                (systemBars?.top ?: 0) + WNavigationBar.DEFAULT_HEIGHT.dp
            )
            toCenterX(webView)
            toBottomPx(webView, systemBars?.bottom ?: 0)
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        applyWebViewConstraints()
    }

    override fun onBackPressed(): Boolean {
        if (webView.canGoBack()) {
            webView.goBack()
            return false
        }
        return super.onBackPressed()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.Background.color)
    }

    private fun handleMessage(data: String) {
        if (finished) return
        val json = runCatching { JSONObject(data) }.getOrNull() ?: return
        when (json.optString("type")) {
            "IC_COMPLETE" -> {
                if (json.has("success") && !json.optBoolean("success")) {
                    finish { onError(json.optString("error").ifEmpty { "Unknown error" }) }
                } else {
                    finish { onComplete() }
                }
            }

            "IC_ERROR" -> {
                finish { onError(json.optString("error").ifEmpty { "Unknown error" }) }
            }
        }
    }

    private fun openExternally(rawUrl: String): Boolean = try {
        val intent = if (rawUrl.startsWith("intent:")) {
            browsableIntent(rawUrl)
        } else {
            Intent(Intent.ACTION_VIEW, android.net.Uri.parse(rawUrl))
        }
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
        true
    } catch (_: ActivityNotFoundException) {
        val fallback = runCatching {
            Intent.parseUri(rawUrl, Intent.URI_INTENT_SCHEME)
                .getStringExtra("browser_fallback_url")
        }.getOrNull()
        if (fallback != null) {
            webView.loadUrl(fallback)
            true
        } else {
            false
        }
    } catch (_: Throwable) {
        true
    }

    /**
     * An `intent:` link names its target, extras and flags, and this app becomes its sender. It
     * opens only like a link from a browser: no explicit component or selector, no URI grants, and
     * never an activity of this app, whose launches from its own package are trusted.
     */
    private fun browsableIntent(rawUrl: String): Intent? {
        val intent = Intent.parseUri(rawUrl, Intent.URI_INTENT_SCHEME).apply {
            component = null
            selector = null
            addCategory(Intent.CATEGORY_BROWSABLE)
            flags = flags and URI_GRANT_FLAGS.inv()
        }
        val packageManager = context.packageManager
        val targets = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }
        return intent.takeIf { targets.none { it.activityInfo.packageName == context.packageName } }
    }

    private inline fun finish(action: () -> Unit) {
        finished = true
        action()
        navigationController?.window?.dismissLastNav()
    }

    override fun onDestroy() {
        super.onDestroy()
        webView.removeJavascriptInterface(JS_INTERFACE)
        webView.destroy()
        if (!finished) onClosed()
    }

    companion object {
        private const val JS_INTERFACE = "WcPayCollect"
        private const val URI_GRANT_FLAGS = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION

        private val MESSAGE_LISTENER_JS = """
            (function() {
              if (window.__wcPayCollectListener) return;
              window.__wcPayCollectListener = true;

              function toPayload(data) {
                return typeof data === 'string' ? data : JSON.stringify(data);
              }

              window.ReactNativeWebView = {
                postMessage: function(data) {
                  try { $JS_INTERFACE.postMessage(toPayload(data)); } catch (e) {}
                }
              };

              window.addEventListener('message', function(event) {
                try { $JS_INTERFACE.onMessage(event.origin || '', toPayload(event.data)); } catch (e) {}
              });
            })();
        """.trimIndent()
    }
}
