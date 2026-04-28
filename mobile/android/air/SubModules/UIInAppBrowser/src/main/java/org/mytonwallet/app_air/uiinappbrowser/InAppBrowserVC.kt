package org.mytonwallet.app_air.uiinappbrowser

import android.Manifest
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Activity
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
import android.webkit.GeolocationPermissions
import android.webkit.PermissionRequest
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.JavascriptInterface
import android.webkit.WebViewClient
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.content.ContextCompat.checkSelfPermission
import androidx.core.graphics.toColorInt
import androidx.core.net.toUri
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WMinimizableBlurHost
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.asImage
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uiinappbrowser.helpers.IABDarkModeStyleHelpers
import org.mytonwallet.app_air.uiinappbrowser.views.InAppBrowserTopBarView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.isBrightColor
import org.mytonwallet.app_air.walletbasecontext.utils.toUriOrNull
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.EvmConnectHelper
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
import java.util.Locale
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

    const match = color.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/i);
    if (!match) return null;

    if (match[4] !== undefined && parseFloat(match[4]) === 0) return null;

    const r = parseInt(match[1]).toString(16).padStart(2, '0');
    const g = parseInt(match[2]).toString(16).padStart(2, '0');
    const b = parseInt(match[3]).toString(16).padStart(2, '0');

    return '#' + r + g + b;
  }

  var themeMetas = document.querySelectorAll('meta[name="theme-color"]');
  for (var i = 0; i < themeMetas.length; i++) {
    var meta = themeMetas[i];
    var media = meta.getAttribute('media');
    if (media && !window.matchMedia(media).matches) continue;
    var hex = rgbToHex(meta.content);
    if (hex) return hex;
  }

  var els = Array.from(document.querySelectorAll('html, body, header, nav, .navbar')).reverse();
  for (var i = 0; i < els.length; i++) {
    var hex = rgbToHex(getComputedStyle(els[i]).backgroundColor);
    if (hex) return hex;
  }

  return null;
})();
"""

private const val OBSERVE_THEME_COLOR_JS = """
(function() {
  if (window._mtwThemeObserver) return;
  window._mtwThemeObserver = true;

  var pending = null;
  function notify() {
    if (pending) return;
    pending = setTimeout(function() {
      pending = null;
      _mtwThemeBridge.onThemeColorChanged();
    }, 100);
  }

  var headObserver = new MutationObserver(notify);
  if (document.head) {
    headObserver.observe(document.head, { childList: true, subtree: true, attributes: true, attributeFilter: ['content'] });
  }

  var rootObserver = new MutationObserver(notify);
  rootObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'style', 'data-theme', 'data-color-mode'] });
  if (document.body) {
    rootObserver.observe(document.body, { attributes: true, attributeFilter: ['class', 'style', 'data-theme', 'data-color-mode'] });
  }

  if (window.matchMedia) {
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', notify);
  }
})();
"""

private const val ORIGIN_PERMISSION_CAMERA = "camera"
private const val ORIGIN_PERMISSION_MICROPHONE = "microphone"
private const val ORIGIN_PERMISSION_GEOLOCATION = "geolocation"

@SuppressLint("ViewConstructor")
class InAppBrowserVC(
    context: Context,
    private val tabBarController: WNavigationController.ITabBarController?,
    val config: InAppBrowserConfig
) : WViewController(context), IInAppBrowser, WalletCore.EventObserver, WMinimizableBlurHost {

    override fun pauseMinimizedBlur() {
        topBar.pauseBlurring()
    }

    override fun resumeMinimizedBlur() {
        topBar.resumeBlurring()
    }

    override val TAG = "InAppBrowser"

    private var lastTitle: String = config.title ?: URL(config.url).host

    override val isSwipeBackAllowed = false

    override val topBarConfiguration = super.topBarConfiguration.copy(blurRootView = null)
    override val topBlurViewGuideline: View
        get() = topBar

    private var savedInExploreVisitedHistory = false
    private var shouldClearHistoryOnLoad = false
    private var fileChooserCallback: ValueCallback<Array<Uri>>? = null
    private val grantedPermissionsByOrigin = mutableMapOf<String, MutableSet<String>>()

    private val themeColorBridge = object {
        @JavascriptInterface
        fun onThemeColorChanged() {
            webView.post { setBarColorBasedOnContent() }
        }
    }

    private val topBar: InAppBrowserTopBarView by lazy {
        InAppBrowserTopBarView(
            this, tabBarController,
            options = config.options,
            selectedOption = config.selectedOption,
            optionsOnTitle = config.optionsOnTitle,
            minimizeStarted = {
                barBackgroundAnimator?.cancel()
                barBackgroundAnimator = null
                updateSystemBarColors()
                webViewScreenShot.setImageBitmap(webViewContainer.asImage())
                webViewScreenShot.visibility = View.VISIBLE
                webView.visibility = View.GONE
            },
            minimizeFinished = {
                topReversedCornerView?.setBlurOverlayColor(null)
                bottomReversedCornerView?.setBlurOverlayColor(null)
            },
            maximizeStarted = {
                topReversedCornerView?.setBlurOverlayColor(topBackgroundColor)
                bottomReversedCornerView?.setBlurOverlayColor(topBackgroundColor)
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
    override val forceBlurBottomView = true

    private val webViewScreenShot: AppCompatImageView by lazy {
        AppCompatImageView(context).apply {
            id = View.generateViewId()
        }
    }

    val webView: WebView by lazy {
        val wv = WebView(context)
        wv.id = View.generateViewId()
        wv.settings.javaScriptEnabled = true
        wv.settings.domStorageEnabled = true
        wv.settings.setSupportMultipleWindows(true)
        wv.setDownloadListener { url, userAgent, contentDisposition, mimetype, _ ->
            try {
                val request = DownloadManager.Request(url.toUri()).apply {
                    setMimeType(mimetype)
                    addRequestHeader("User-Agent", userAgent)

                    val cookie = CookieManager.getInstance().getCookie(url)
                    if (!cookie.isNullOrEmpty()) addRequestHeader("Cookie", cookie)

                    setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)

                    val filename = URLUtil.guessFileName(url, contentDisposition, mimetype)
                    setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename)
                }

                val dm =
                    webView.context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                dm.enqueue(request)
            } catch (_: Throwable) {
            }
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
                    webView.evaluateJavascript(EvmConnectHelper.inject(), null)
                }
                super.onPageStarted(view, url, favicon)
            }

            @Deprecated("Deprecated in Java")
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
                    webView.evaluateJavascript(OBSERVE_THEME_COLOR_JS, null)
                    // Re-check after SPA hydration
                    webView.postDelayed({ setBarColorBasedOnContent() }, 1000)
                }
            }

            private fun shouldOverride(url: String): Boolean {
                val scheme = url.toUriOrNull()?.scheme?.lowercase() ?: return false

                when (scheme) {
                    "intent" -> return true

                    "tel" -> {
                        try {
                            val intent = Intent(Intent.ACTION_DIAL)
                            intent.data = url.toUri()
                            window?.startActivity(intent)
                            return true
                        } catch (_: android.content.ActivityNotFoundException) {
                        }
                    }

                    "geo", "mailto", "market", "tg" -> {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW)
                            intent.data = url.toUri()
                            window?.startActivity(intent)
                            return true
                        } catch (_: android.content.ActivityNotFoundException) {
                        }
                    }

                    "sms" -> {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW)
                            var address: String? = null
                            val parmIndex = url.indexOf('?')

                            address = if (parmIndex == -1) {
                                url.substring(4)
                            } else {
                                url.substring(4, parmIndex).also {
                                    val uri = url.toUriOrNull()
                                    val query = uri?.query
                                    if (query != null && query.startsWith("body=")) {
                                        intent.putExtra("sms_body", query.substring(5))
                                    }
                                }
                            }

                            intent.setDataAndType(
                                "sms:$address".toUriOrNull(),
                                "vnd.android-dir/mms-sms"
                            )
                            intent.putExtra("address", address)
                            window?.startActivity(intent)
                            return true
                        } catch (_: android.content.ActivityNotFoundException) {
                        }
                    }

                    "http" -> return true

                    "https" -> {}

                    else -> {
                        val isValidDeeplink = WalletContextManager.delegate?.handleDeeplink(url)
                        if (isValidDeeplink == true)
                            return true
                    }
                }

                return false
            }
        })
        if (config.allowDownloads)
            wv.setDownloadListener { url, _, _, _, _ ->
                val configUri = config.url.toUriOrNull() ?: return@setDownloadListener
                val downloadUri = url.toUriOrNull() ?: return@setDownloadListener
                if (downloadUri.scheme != configUri.scheme || downloadUri.host != configUri.host)
                    return@setDownloadListener
                window?.startActivityCatching(Intent(Intent.ACTION_VIEW, downloadUri))
            }
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

            override fun onGeolocationPermissionsShowPrompt(
                origin: String?,
                callback: GeolocationPermissions.Callback?
            ) {
                if (origin == null || callback == null) {
                    callback?.invoke(origin, false, false)
                    return
                }
                handleGeolocationPermissionRequest(origin, callback)
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
                    uri = config.url.toUri(),
                    showError = { error ->
                        showAlert(
                            LocaleController.getString("Error"),
                            error
                        )
                    }
                )
            } else null
        } catch (_: Throwable) {
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

        if (config.topBarColorMode == InAppBrowserConfig.TopBarColorMode.CONTENT_BASED) {
            webView.addJavascriptInterface(themeColorBridge, "_mtwThemeBridge")
        }

        webView.loadUrl(config.url)

        updateTheme()

        WalletCore.registerObserver(this)
    }

    override fun navigate(url: String) {
        shouldClearHistoryOnLoad = true
        topBar.setIconBitmap(null)
        config.thumbnail = null
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
        grantedPermissionsByOrigin.clear()
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
    private var barBackgroundAnimator: ValueAnimator? = null
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
            topReversedCornerView?.setBlurOverlayColor(null)
            bottomReversedCornerView?.setBlurOverlayColor(null)
            return
        }
        barBackgroundAnimator = ValueAnimator.ofArgb(
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
        val origin = normalizeOrigin(request.origin)
        val requestedOriginPermissions = getRequestedMediaOriginPermissions(request.resources)
        val missingOriginPermissions =
            getMissingOriginPermissions(origin, requestedOriginPermissions)

        if (missingOriginPermissions.isEmpty()) {
            requestMediaAndroidPermissions(request) { isGranted ->
                if (isGranted) {
                    safeGrantPermissionRequest(request, request.resources)
                } else {
                    safeDenyPermissionRequest(request)
                }
            }
            return
        }

        showOriginPermissionDialog(
            origin = origin,
            requestedPermissions = missingOriginPermissions,
            onAllow = {
                requestMediaAndroidPermissions(request) { isGranted ->
                    if (isGranted) {
                        grantOriginPermissions(origin, requestedOriginPermissions)
                        safeGrantPermissionRequest(request, request.resources)
                    } else {
                        safeDenyPermissionRequest(request)
                    }
                }
            },
            onDeny = {
                safeDenyPermissionRequest(request)
            }
        )
    }

    private fun handleGeolocationPermissionRequest(
        origin: String,
        callback: GeolocationPermissions.Callback
    ) {
        val normalizedOrigin = normalizeOrigin(origin)
        if (hasOriginPermission(normalizedOrigin, ORIGIN_PERMISSION_GEOLOCATION)) {
            requestGeolocationAndroidPermissions { isGranted ->
                callback.invoke(origin, isGranted, false)
            }
            return
        }

        val geolocationPermission = setOf(ORIGIN_PERMISSION_GEOLOCATION)
        showOriginPermissionDialog(
            origin = normalizedOrigin,
            requestedPermissions = geolocationPermission,
            onAllow = {
                requestGeolocationAndroidPermissions { isGranted ->
                    if (isGranted) {
                        grantOriginPermissions(normalizedOrigin, geolocationPermission)
                        callback.invoke(origin, true, false)
                    } else {
                        callback.invoke(origin, false, false)
                    }
                }
            },
            onDeny = {
                callback.invoke(origin, false, false)
            }
        )
    }

    private fun requestMediaAndroidPermissions(
        request: PermissionRequest,
        onResult: (Boolean) -> Unit
    ) {
        val permissionsToRequest = LinkedHashSet<String>()
        request.resources.forEach { resource ->
            if (
                resource == PermissionRequest.RESOURCE_VIDEO_CAPTURE
                && checkSelfPermission(
                    context,
                    Manifest.permission.CAMERA
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                permissionsToRequest.add(Manifest.permission.CAMERA)
            } else if (
                resource == PermissionRequest.RESOURCE_AUDIO_CAPTURE
                && checkSelfPermission(
                    context,
                    Manifest.permission.RECORD_AUDIO
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                permissionsToRequest.add(Manifest.permission.RECORD_AUDIO)
            }
        }

        if (permissionsToRequest.isEmpty()) {
            onResult(true)
            return
        }

        val activity = window ?: run {
            onResult(false)
            return
        }
        activity.requestPermissions(permissionsToRequest.toTypedArray()) { _, grantResults ->
            val allGranted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            onResult(allGranted)
        }
    }

    private fun requestGeolocationAndroidPermissions(onResult: (Boolean) -> Unit) {
        val permissionsToRequest = LinkedHashSet<String>()
        if (checkSelfPermission(
                context,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            permissionsToRequest.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        if (checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }

        if (permissionsToRequest.isEmpty()) {
            onResult(true)
            return
        }

        val activity = window ?: run {
            onResult(false)
            return
        }
        activity.requestPermissions(permissionsToRequest.toTypedArray()) { _, grantResults ->
            val hasAnyGrant = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            onResult(hasAnyGrant)
        }
    }

    private fun getRequestedMediaOriginPermissions(resources: Array<String>): Set<String> {
        val originPermissions = mutableSetOf<String>()
        resources.forEach { resource ->
            if (resource == PermissionRequest.RESOURCE_VIDEO_CAPTURE) {
                originPermissions.add(ORIGIN_PERMISSION_CAMERA)
            } else if (resource == PermissionRequest.RESOURCE_AUDIO_CAPTURE) {
                originPermissions.add(ORIGIN_PERMISSION_MICROPHONE)
            }
        }
        return originPermissions
    }

    private fun getMissingOriginPermissions(
        origin: String,
        requestedPermissions: Set<String>
    ): Set<String> {
        val missingPermissions = mutableSetOf<String>()
        requestedPermissions.forEach { requestedPermission ->
            if (!hasOriginPermission(origin, requestedPermission)) {
                missingPermissions.add(requestedPermission)
            }
        }
        return missingPermissions
    }

    private fun hasOriginPermission(origin: String, permissionKey: String): Boolean {
        val permissions = grantedPermissionsByOrigin[origin]
        return permissions?.contains(permissionKey) == true
    }

    private fun grantOriginPermissions(origin: String, permissionKeys: Set<String>) {
        if (permissionKeys.isEmpty()) {
            return
        }
        val permissions = grantedPermissionsByOrigin.getOrPut(origin) { mutableSetOf() }
        permissions.addAll(permissionKeys)
    }

    private fun showOriginPermissionDialog(
        origin: String,
        requestedPermissions: Set<String>,
        onAllow: () -> Unit,
        onDeny: () -> Unit
    ) {
        val activity = context as? Activity ?: run {
            onDeny()
            return
        }
        if (activity.isFinishing) {
            onDeny()
            return
        }

        val originName = getOriginDisplayName(origin)
        val permissionList = buildPermissionLabel(requestedPermissions)
        val permissionPrompt = LocaleController.getStringWithKeyValues(
            "\$web_permission_prompt",
            listOf(
                Pair("%origin%", originName),
                Pair("%permissions%", permissionList)
            )
        )
        activity.runOnUiThread {
            if (activity.isFinishing) {
                onDeny()
                return@runOnUiThread
            }
            androidx.appcompat.app.AlertDialog.Builder(activity)
                .setMessage(permissionPrompt)
                .setCancelable(false)
                .setPositiveButton(LocaleController.getString("\$web_permission_allow")) { _, _ ->
                    onAllow()
                }
                .setNegativeButton(LocaleController.getString("\$web_permission_deny")) { _, _ ->
                    onDeny()
                }
                .show()
        }
    }

    private fun buildPermissionLabel(requestedPermissions: Set<String>): String {
        val labels = mutableListOf<String>()
        if (requestedPermissions.contains(ORIGIN_PERMISSION_CAMERA)) {
            labels.add(LocaleController.getString("\$web_permission_camera"))
        }
        if (requestedPermissions.contains(ORIGIN_PERMISSION_MICROPHONE)) {
            labels.add(LocaleController.getString("\$web_permission_microphone"))
        }
        if (requestedPermissions.contains(ORIGIN_PERMISSION_GEOLOCATION)) {
            labels.add(LocaleController.getString("\$web_permission_location"))
        }

        if (labels.isEmpty()) {
            return LocaleController.getString("\$web_permission_device_features")
        }
        if (labels.size == 1) {
            return labels[0]
        }
        return LocaleController.getFormattedEnumeration(labels, "and")
    }

    private fun getOriginDisplayName(origin: String): String {
        if (origin.isBlank()) {
            return LocaleController.getString("\$web_permission_this_site")
        }
        return try {
            origin.toUri().host?.takeIf { it.isNotBlank() } ?: origin
        } catch (_: Exception) {
            origin
        }
    }

    private fun normalizeOrigin(uri: Uri?): String {
        if (uri == null) {
            return ""
        }

        val scheme = uri.scheme
        val host = uri.host
        if (scheme == null || host == null) {
            return uri.toString()
        }

        return buildString {
            append(scheme.lowercase(Locale.US))
            append("://")
            append(host.lowercase(Locale.US))
            if (uri.port != -1) {
                append(":")
                append(uri.port)
            }
        }
    }

    private fun normalizeOrigin(origin: String?): String {
        if (origin == null) {
            return ""
        }
        return try {
            normalizeOrigin(origin.toUri())
        } catch (_: Exception) {
            origin
        }
    }

    private fun safeGrantPermissionRequest(request: PermissionRequest, resources: Array<String>) {
        try {
            request.grant(resources)
        } catch (_: IllegalStateException) {
        }
    }

    private fun safeDenyPermissionRequest(request: PermissionRequest) {
        try {
            request.deny()
        } catch (_: IllegalStateException) {
        }
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
            } catch (_: Exception) {
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
