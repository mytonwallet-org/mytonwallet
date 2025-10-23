package org.mytonwallet.app_air.uiinappbrowser

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat.checkSelfPermission
import androidx.core.net.toUri
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.asImage
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uiinappbrowser.helpers.IABDarkModeStyleHelpers
import org.mytonwallet.app_air.uiinappbrowser.views.InAppBrowserTopBarView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.TonConnectHelper
import org.mytonwallet.app_air.walletcore.helpers.TonConnectInjectedInterface
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import java.net.URL
import java.net.URLEncoder
import java.util.regex.Pattern


@SuppressLint("ViewConstructor")
class InAppBrowserVC(
    context: Context,
    private val tabBarController: WNavigationController.ITabBarController?,
    val config: InAppBrowserConfig
) : WViewController(context), WalletCore.EventObserver {

    private var lastTitle: String = config.title ?: URL(config.url).host

    override val isSwipeBackAllowed = false

    override val topBarConfiguration = super.topBarConfiguration.copy(blurRootView = null)
    override val topBlurViewGuideline: View
        get() = topBar

    private var savedInExploreVisitedHistory = false

    private val topBar: InAppBrowserTopBarView by lazy {
        InAppBrowserTopBarView(
            this, tabBarController, minimizeStarted = {
                webViewScreenShot.setImageBitmap(webViewContainer.asImage())
                webViewScreenShot.visibility = View.VISIBLE
                webView.visibility = View.GONE
            },
            options = config.options,
            selectedOption = config.selectedOption,
            maximizeFinished = {
                view.post {
                    webView.visibility = View.VISIBLE
                    webView.post {
                        // prevents web-view flickers from being visible
                        webViewScreenShot.visibility = View.GONE
                    }
                }
            }).apply {
            updateTitle(lastTitle, animated = false)
            config.thumbnail?.let {
                setIconUrl(it)
            }
        }
    }

    override val shouldDisplayBottomBar = true

    private val webViewScreenShot: AppCompatImageView by lazy {
        AppCompatImageView(context).apply {
            id = View.generateViewId()
        }
    }

    private fun canHandleExternalUrl(url: String): Boolean {
        return url.startsWith("geo:") ||
            url.startsWith(WebView.SCHEME_MAILTO) ||
            url.startsWith("market:") ||
            url.startsWith("intent:") ||
            url.startsWith("tg:")
    }

    val webView: WebView by lazy {
        val wv = WebView(context)
        wv.id = View.generateViewId()
        wv.settings.javaScriptEnabled = true
        wv.settings.domStorageEnabled = true
        wv.setWebViewClient(object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest
            ): Boolean {
                return shouldOverride(request.url.toString())
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                if (config.injectDarkModeStyles)
                    IABDarkModeStyleHelpers.applyOn(webView)
                injectedInterface?.let {
                    webView.evaluateJavascript(TonConnectHelper.inject(), null)
                }
                super.onPageStarted(view, url, favicon)
            }

            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
                return shouldOverride(url)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                topBar.updateBackButton(true)
                // Prev method call may not work sometimes, so let's reset dark mode styles.
                if (config.injectDarkModeStyles)
                    IABDarkModeStyleHelpers.applyOn(webView)

                if (config.saveInVisitedHistory && !savedInExploreVisitedHistory) {
                    savedInExploreVisitedHistory = true
                    saveInExploreVisitedHistory()
                }
            }

            private fun shouldOverride(url: String): Boolean {
                if (url.startsWith(WebView.SCHEME_TEL)) {
                    try {
                        val intent = Intent(Intent.ACTION_DIAL)
                        intent.data = Uri.parse(url)
                        window?.startActivity(intent)
                        return true
                    } catch (_: android.content.ActivityNotFoundException) {
                    }
                } else if (url.startsWith("geo:") || url.startsWith(WebView.SCHEME_MAILTO) ||
                    url.startsWith("market:") || url.startsWith("intent:") || url.startsWith("tg:")
                ) {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW)
                        intent.data = Uri.parse(url)
                        window?.startActivity(intent)
                        return true
                    } catch (_: android.content.ActivityNotFoundException) {
                    }
                } else if (url.startsWith("sms:")) {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW)
                        var address: String? = null
                        val parmIndex = url.indexOf('?')

                        address = if (parmIndex == -1) {
                            url.substring(4)
                        } else {
                            url.substring(4, parmIndex).also {
                                val uri = Uri.parse(url)
                                val query = uri.query
                                if (query != null && query.startsWith("body=")) {
                                    intent.putExtra("sms_body", query.substring(5))
                                }
                            }
                        }

                        intent.data = Uri.parse("sms:$address")
                        intent.putExtra("address", address)
                        intent.type = "vnd.android-dir/mms-sms"
                        window?.startActivity(intent)
                        return true
                    } catch (_: android.content.ActivityNotFoundException) {
                    }
                }

                if (!url.startsWith("http://") &&
                    !url.startsWith("https://") &&
                    canHandleExternalUrl(url)
                ) {
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.setData(Uri.parse(url))
                    window?.startActivity(intent)
                    return false
                }

                return false
            }
        })
        wv.setBackgroundColor(0)
        wv.setWebChromeClient(object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest?) {
                request?.let {
                    handlePermissionRequest(it)
                }
            }

            override fun onReceivedTitle(view: WebView?, title: String?) {
                super.onReceivedTitle(view, title)
                if (config.title != null || title == lastTitle)
                    return
                lastTitle = title ?: URL(config.url).host
                topBar.updateTitle(lastTitle, animated = true)
            }

            override fun onReceivedIcon(view: WebView?, icon: Bitmap?) {
                super.onReceivedIcon(view, icon)
                if (config.thumbnail == null)
                    topBar.setIconBitmap(icon)
            }
        })
        wv.alpha = 0f
        wv.visibility = View.GONE
        wv
    }

    val injectedInterface: TonConnectInjectedInterface? by lazy {
        try {
            if (config.injectTonConnectBridge) {
                TonConnectInjectedInterface(
                    webView = webView,
                    accountId = AccountStore.activeAccountId!!,
                    uri = Uri.parse(config.url)!!,
                    showError = { error ->
                        showAlert(
                            LocaleController.getString("Error"),
                            error
                        )
                    }
                )
            } else null
        } catch (t: Throwable) {
            null
        }
    }

    private val webViewContainer = FrameLayout(context).apply {
        id = View.generateViewId()
        addView(webView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    override fun setupViews() {
        super.setupViews()

        addWebView()
        view.addView(topBar, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.setConstraints {
            toTop(topBar)
            toCenterX(topBar)
        }

        injectedInterface?.let {
            webView.addJavascriptInterface(
                it,
                TonConnectHelper.TON_CONNECT_WALLET_JS_BRIDGE_INTERFACE
            )
        }

        webView.loadUrl(config.url)

        updateTheme()

        WalletCore.registerObserver(this)
    }

    fun navigate(url: String) {
        webView.loadUrl(url)
        webView.clearHistory()
    }

    private var isFirstAppearance = true
    override fun viewDidAppear() {
        super.viewDidAppear()

        if (isFirstAppearance) {
            isFirstAppearance = false
            webView.visibility = View.VISIBLE
            webView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        }

        webView.visibility = View.VISIBLE
        webView.post {
            webViewScreenShot.visibility = View.GONE
        }
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        webViewScreenShot.setImageBitmap(webViewContainer.asImage())
        webViewScreenShot.visibility = View.VISIBLE
        webView.visibility = View.GONE
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.Background.color)
        webView.setBackgroundColor(WColor.Background.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        topReversedCornerView?.setHorizontalPadding(0f)
        bottomReversedCornerView?.setHorizontalPadding(0f)
    }

    private fun addWebView() {
        val refNav = navigationController?.window?.navigationControllers?.first()
        val browserWidth = refNav?.width ?: 0
        val topSpace = (window?.systemBars?.top ?: 0) +
            WNavigationBar.DEFAULT_HEIGHT_TINY.dp
        val browserHeight =
            (refNav?.height ?: 0) -
                topSpace -
                (window?.systemBars?.bottom ?: 0)
        view.addView(
            webViewContainer, ConstraintLayout.LayoutParams(
                browserWidth,
                browserHeight,
            )
        )
        view.addView(
            webViewScreenShot, ConstraintLayout.LayoutParams(
                browserWidth,
                browserHeight,
            )
        )
        webViewContainer.y = topSpace.toFloat()
        webViewScreenShot.y = topSpace.toFloat()
    }

    override fun onBackPressed(): Boolean {
        if (config.forceCloseOnBack)
            return super.onBackPressed()
        topBar.backPressed()
        return false
    }

    private fun saveInExploreVisitedHistory() {
        val fetchFavIconUrl = """
    (function() {
        function absoluteUrl(url) {
            try { return new URL(url, document.baseURI).href; }
            catch (e) { return url; }
        }

        var links = Array.from(document.querySelectorAll(
            'link[rel*="icon"], link[rel="mask-icon"], link[rel="apple-touch-icon"]'
        ));
        if (links.length === 0) {
            return absoluteUrl('/favicon.ico');
        }

        var best = links.map(link => {
            let sizes = link.getAttribute('sizes');
            let size = 0;
            if (sizes && /\d+x\d+/.test(sizes)) {
                size = parseInt(sizes.split('x')[0]);
            } else if (link.rel.includes('apple-touch-icon')) {
                size = 180;
            } else {
                size = 16;
            }
            return { href: absoluteUrl(link.href), size };
        }).sort((a, b) => b.size - a.size)[0];
        return best ? best.href : null;
    })();
    """

        webView.evaluateJavascript(fetchFavIconUrl) { result ->
            val faviconUrl = result?.trim('"')?.takeIf { it.isNotEmpty() && it != "null" }
            if (!isDisappeared && faviconUrl != null) {
                ExploreHistoryStore.saveSiteVisit(
                    MExploreHistory.VisitedSite(
                        favicon = faviconUrl,
                        lastTitle,
                        config.url,
                        System.currentTimeMillis()
                    )
                )
            }
        }
    }

    private fun handlePermissionRequest(request: PermissionRequest) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            var requiresCamera = false
            for (resource in request.resources) {
                if (resource == PermissionRequest.RESOURCE_VIDEO_CAPTURE) {
                    requiresCamera = true
                    break
                }
            }

            if (requiresCamera) {
                if (checkSelfPermission(context, Manifest.permission.CAMERA) ==
                    PackageManager.PERMISSION_GRANTED
                ) {
                    request.grant(request.resources)
                } else {
                    val activity = context as? WWindow ?: return
                    activity.requestPermissions(arrayOf(Manifest.permission.CAMERA)) { _, grantResults ->
                        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                            request.grant(request.resources)
                        }
                    }
                }
                return
            }
        }
        request.grant(request.resources)
    }

    companion object {
        const val GOOGLE_SEARCH_URL = "https://www.google.com/search?q="

        fun convertToUri(input: String): Pair<Boolean, Uri?> {
            try {
                val url = if (input.startsWith("https://") || input.startsWith("http://")) {
                    input
                } else {
                    "https://$input"
                }

                val uri = url.toUri()
                if (!isValidDomain(uri.host ?: "")) {
                    return Pair(
                        false,
                        (GOOGLE_SEARCH_URL + URLEncoder.encode(input, "UTF-8")).toUri()
                    )
                }
                return Pair(true, uri)
            } catch (e: Exception) {
                return Pair(false, null)
            }
        }

        private fun isValidDomain(domain: String): Boolean {
            val domainRegex = Pattern.compile(
                "^[a-zA-Z0-9][a-zA-Z0-9-_]{0,61}[a-zA-Z0-9]{0,1}\\.([a-zA-Z]{1,6}|[a-zA-Z0-9-]{1,30}\\.[a-zA-Z]{2,3})\$"
            )
            return domainRegex.matcher(domain).matches()
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.DappRemoved -> {
                if (config.url.removeSuffix("/") == walletEvent.dapp.url) {
                    webView.loadUrl(config.url)
                }
            }

            WalletEvent.DappsCountUpdated ->
                if (DappsStore.dApps[AccountStore.activeAccountId].isNullOrEmpty())
                    webView.loadUrl(config.url)

            else -> {}
        }
    }
}
