package org.mytonwallet.app_air.uiinappbrowser

import android.Manifest
import android.app.Activity
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Message
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.ValueCallback
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.content.ContextCompat.checkSelfPermission
import androidx.core.graphics.toColorInt
import androidx.core.net.toUri
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.asImage
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uiinappbrowser.helpers.IABDarkModeStyleHelpers
import org.mytonwallet.app_air.uiinappbrowser.views.InAppBrowserTopBarView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.isBrightColor
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.TonConnectHelper
import org.mytonwallet.app_air.walletcore.helpers.TonConnectInjectedInterface
import org.mytonwallet.app_air.walletcore.helpers.WalletConnectHelper
import org.mytonwallet.app_air.walletcore.models.IInAppBrowser
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import java.net.URL
import java.net.URLEncoder
import java.util.regex.Pattern

const val FETCH_FAV_ICON_URL_JS = """
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

private const val FETCH_HEADER_COLOR_JS = """
(function () {
  function rgbToHex(color) {
    if (!color) return null;

    if (color.startsWith('#')) {
      return color.toLowerCase();
    }

    const match = color.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/i);
    if (!match) return null;

    const r = parseInt(match[1]).toString(16).padStart(2, '0');
    const g = parseInt(match[2]).toString(16).padStart(2, '0');
    const b = parseInt(match[3]).toString(16).padStart(2, '0');

    return '#' + r + g + b;
  }

  const theme = document.querySelector('meta[name="theme-color"]')?.content;
  if (theme) return rgbToHex(theme);

  const nav = document.querySelector('header, nav, .navbar, body, html');
  if (nav) {
    const bg = getComputedStyle(nav).backgroundColor;
    return rgbToHex(bg);
  }

  return null;
})();
"""

@SuppressLint("ViewConstructor")
class InAppBrowserVC(
    context: Context,
    private val tabBarController: WNavigationController.ITabBarController?,
    val config: InAppBrowserConfig
) : WViewController(context), IInAppBrowser, WalletCore.EventObserver {
    override val TAG = "InAppBrowser"

    private var lastTitle: String = config.title ?: URL(config.url).host

    override val isSwipeBackAllowed = false

    override val topBarConfiguration = super.topBarConfiguration.copy(blurRootView = null)
    override val topBlurViewGuideline: View
        get() = topBar

    private var savedInExploreVisitedHistory = false
    private var shouldClearHistoryOnLoad = false
    private var fileChooserCallback: ValueCallback<Array<Uri>>? = null

    private val topBar: InAppBrowserTopBarView by lazy {
        InAppBrowserTopBarView(
            this, tabBarController,
            options = config.options,
            selectedOption = config.selectedOption,
            optionsOnTitle = config.optionsOnTitle,
            minimizeStarted = {
                updateSystemBarColors()
                webViewScreenShot.setImageBitmap(webViewContainer.asImage())
                webViewScreenShot.visibility = View.VISIBLE
                webView.visibility = View.GONE
            },
            maximizeFinished = {
                updateSystemBarColors()
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
        wv.settings.setSupportMultipleWindows(true)
        wv.setDownloadListener { url, userAgent, contentDisposition, mimetype, _ ->
            val request = DownloadManager.Request(url.toUri()).apply {
                setMimeType(mimetype)
                addRequestHeader("User-Agent", userAgent)

                val cookie = CookieManager.getInstance().getCookie(url)
                if (!cookie.isNullOrEmpty()) addRequestHeader("Cookie", cookie)

                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)

                val filename = URLUtil.guessFileName(url, contentDisposition, mimetype)
                setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename)
            }

            val dm = webView.context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            dm.enqueue(request)
        }
        wv.setWebViewClient(object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest
            ): Boolean {
                return shouldOverride(request.url.toString())
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                applyTopBarColorInitial()
                if (config.injectDarkModeStyles)
                    IABDarkModeStyleHelpers.applyOn(webView)
                injectedInterface?.let {
                    webView.evaluateJavascript(TonConnectHelper.injectBridge(), null)
                    webView.evaluateJavascript(TonConnectHelper.inject(), null)
                    webView.evaluateJavascript(WalletConnectHelper.inject(), null)
                }
                super.onPageStarted(view, url, favicon)
            }

            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
                return shouldOverride(url)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                if (shouldClearHistoryOnLoad) {
                    shouldClearHistoryOnLoad = false
                    webView.clearHistory()
                }
                topBar.updateBackButton(true)
                // Prev method call may not work sometimes, so let's reset dark mode styles.
                if (config.injectDarkModeStyles)
                    IABDarkModeStyleHelpers.applyOn(webView)

                if (config.saveInVisitedHistory && !savedInExploreVisitedHistory) {
                    savedInExploreVisitedHistory = true
                    saveInExploreVisitedHistory()
                }
                if (config.topBarColorMode == InAppBrowserConfig.TopBarColorMode.CONTENT_BASED) {
                    setBarColorBasedOnContent()
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
                } else {
                    val isValidDeeplink = WalletContextManager.delegate?.handleDeeplink(url)
                    if (isValidDeeplink == true)
                        return true
                }

                if (!url.startsWith("http://") &&
                    !url.startsWith("https://") &&
                    return canHandleExternalUrl(url)
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
            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message?
            ): Boolean {
                val href = view?.handler?.obtainMessage()
                view?.requestFocusNodeHref(href)
                href?.data?.getString("url")?.let { url ->
                    webView.loadUrl(url)
                }
                return true
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                request?.let {
                    handlePermissionRequest(it)
                }
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                if (filePathCallback == null) {
                    return false
                }
                return openFileChooser(filePathCallback, fileChooserParams)
            }

            override fun onReceivedTitle(view: WebView?, title: String?) {
                super.onReceivedTitle(view, title)
                if (config.title != null || title == lastTitle || config.options != null)
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
            if (config.injectDappConnect) {
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

    private val webViewContainer = WFrameLayout(context).apply {
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

        applyTopBarColorInitial()

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

    override fun navigate(url: String) {
        shouldClearHistoryOnLoad = true
        webView.loadUrl(url)
    }

    private var isFirstAppearance = true
    override fun viewDidAppear() {
        super.viewDidAppear()

        if (isFirstAppearance) {
            isFirstAppearance = false
            webView.visibility = View.VISIBLE
            webView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        }
    }

    override fun viewDidEnterForeground() {
        super.viewDidEnterForeground()

        webView.visibility = View.VISIBLE
        webView.post {
            webViewScreenShot.visibility = View.GONE
        }
        updateSystemBarColors()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        updateSystemBarColors()
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

    override fun onDestroy() {
        super.onDestroy()
        fileChooserCallback?.onReceiveValue(null)
        fileChooserCallback = null
        webView.apply {
            stopLoading()
            webChromeClient = null
            setDownloadListener(null)
            removeAllViews()
            destroy()
        }
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
        webView.evaluateJavascript(FETCH_FAV_ICON_URL_JS) { result ->
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

    private fun updateSystemBarColors() {
        if (isDisappeared || topBar.isMinimizing || topBar.isMinimized) {
            window?.forceStatusBarLight = null
            window?.forceBottomBarLight = null
            return
        }
        topBar.overrideThemeIsDark?.let { overrideThemeIsDark ->
            window?.forceStatusBarLight = overrideThemeIsDark
            window?.forceBottomBarLight = overrideThemeIsDark
        }
    }

    private fun applyTopBarColorInitial() {
        when (config.topBarColorMode) {
            InAppBrowserConfig.TopBarColorMode.SYSTEM ->
                animateBarBackground(null)
            InAppBrowserConfig.TopBarColorMode.CONTENT_BASED ->
                animateBarBackground(null)
            InAppBrowserConfig.TopBarColorMode.FIXED ->
                animateBarBackground(config.topBarColor)
        }
    }

    private fun setBarColorBasedOnContent() {
        webView.evaluateJavascript(FETCH_HEADER_COLOR_JS) { result ->
            val cssColor = result?.trim('"')
            val parsedColor = cssColor
                ?.takeIf { it.isNotEmpty() && it != "null" }
                ?.let {
                    try {
                        it.toColorInt()
                    } catch (_: IllegalArgumentException) {
                        null
                    }
                }
            animateBarBackground(parsedColor)
        }
    }

    private var topBackgroundColor: Int? = null
    private fun animateBarBackground(newColor: Int?) {
        val isMinimized = topBar.isMinimizing || topBar.isMinimized
        newColor?.let { newColor ->
            val isDark = !newColor.isBrightColor()
            topBar.overrideThemeIsDark = isDark
        } ?: run {
            topBar.overrideThemeIsDark = null
        }
        updateSystemBarColors()
        if (isMinimized) {
            topBackgroundColor = newColor
            topReversedCornerView?.setBlurOverlayColor(topBackgroundColor)
            bottomReversedCornerView?.setBlurOverlayColor(topBackgroundColor)
            return
        }
        ValueAnimator.ofArgb(
            topBackgroundColor ?: WColor.SecondaryBackground.color,
            newColor ?: WColor.SecondaryBackground.color
        ).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animator ->
                topBackgroundColor = animator.animatedValue as Int
                topReversedCornerView?.setBlurOverlayColor(topBackgroundColor!!)
                bottomReversedCornerView?.setBlurOverlayColor(topBackgroundColor!!)
            }
            doOnEnd {
                topReversedCornerView?.setBlurOverlayColor(newColor)
                bottomReversedCornerView?.setBlurOverlayColor(newColor)
            }
            start()
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

    private fun openFileChooser(
        filePathCallback: ValueCallback<Array<Uri>>,
        fileChooserParams: WebChromeClient.FileChooserParams?
    ): Boolean {
        this.fileChooserCallback?.onReceiveValue(null)
        this.fileChooserCallback = filePathCallback

        val chooserIntent = try {
            fileChooserParams?.createIntent()
        } catch (_: Exception) {
            null
        } ?: Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }

        val window = window ?: run {
            this.fileChooserCallback?.onReceiveValue(null)
            this.fileChooserCallback = null
            return false
        }

        return try {
            window.startActivityForResult(chooserIntent) { resultCode, data ->
                val result = if (resultCode == Activity.RESULT_OK) {
                    WebChromeClient.FileChooserParams.parseResult(resultCode, data)
                } else {
                    null
                }
                this.fileChooserCallback?.onReceiveValue(result)
                this.fileChooserCallback = null
            }
            true
        } catch (_: Exception) {
            this.fileChooserCallback?.onReceiveValue(null)
            this.fileChooserCallback = null
            false
        }
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
            is WalletEvent.AccountChanged -> {
                val accountId = AccountStore.activeAccountId ?: return
                injectedInterface?.updateAccountId(accountId)
            }

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
