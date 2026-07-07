package org.mytonwallet.uihome.tabs.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import androidx.core.net.toUri
import androidx.core.widget.doOnTextChanged
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.widgets.PillShadowView
import org.mytonwallet.app_air.uicomponents.widgets.SwapSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import me.vkryl.android.animatorx.BoolAnimator
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class ExploreSearchBar(
    context: Context,
    private val config: Config,
) : WFrameLayout(context) {

    class Config(
        /** Called whenever the search keyword changes; mirrors ExploreVC.search(query, focused). */
        val onSearch: (query: String?, focused: Boolean) -> Unit,
        /** Expanded (focused) width in px. Usually content width minus paddings. */
        val expandedWidthProvider: () -> Int,
        /** Present the in-app browser navigation built for a search submit. */
        val presentBrowser: (config: InAppBrowserConfig) -> Unit,
        /** Notified when bounds change so a host can re-sync external shadow/blur if needed. */
        val onLayoutChanged: () -> Unit = {},
    )

    companion object {
        const val SEARCH_HEIGHT = 48
        const val COLLAPSED_MAX_WIDTH = 320
    }

    private var isProcessingSearchKeyword = false
    var searchMatchedSite: MExploreHistory.VisitedSite? = null
        private set
    var searchKeyword = ""
        private set

    private val blurryBackgroundView = WBlurryBackgroundView(context, fadeSide = null).apply {
        setOverlayColor(WColor.SearchFieldBackground, 204)
    }

    val editText by lazy {
        object : SwapSearchEditText(context) {
            override fun onFocusChanged(
                focused: Boolean,
                direction: Int,
                previouslyFocusedRect: android.graphics.Rect?
            ) {
                super.onFocusChanged(focused, direction, previouslyFocusedRect)
                searchFocused.animatedValue = focused
            }

            override fun onSelectionChanged(selStart: Int, selEnd: Int) {
                super.onSelectionChanged(selStart, selEnd)
                if (isProcessingSearchKeyword || searchMatchedSite == null)
                    return
                isProcessingSearchKeyword = true
                setTextKeepCursor(searchKeyword)
                searchMatchedSite = null
                isProcessingSearchKeyword = false
            }
        }.apply {
            hint = LocaleController.getString("Search app or enter address")
            doOnTextChanged { text, start, _, count ->
                if (text != null && text == searchKeyword)
                    return@doOnTextChanged
                if (isProcessingSearchKeyword)
                    return@doOnTextChanged
                isProcessingSearchKeyword = true
                if ((text?.length ?: 0) > searchKeyword.length)
                    checkForMatchingUrl(text?.toString() ?: "")
                else {
                    searchKeyword = text?.toString() ?: ""
                    searchMatchedSite = null
                }
                if (searchMatchedSite == null) {
                    val cursorPosition = start + count
                    setText(searchKeyword)
                    setSelection(cursorPosition.coerceAtMost(searchKeyword.length))
                }
                config.onSearch(searchKeyword, hasFocus())
                post { isProcessingSearchKeyword = false }
            }
            onFocusChangeListener = OnFocusChangeListener { _, hasFocus ->
                if (isProcessingSearchKeyword)
                    return@OnFocusChangeListener
                if (!hasFocus && (context as? android.app.Activity)?.isChangingConfigurations == true)
                    return@OnFocusChangeListener
                isProcessingSearchKeyword = true
                val query = if (hasFocus) text?.toString() else null
                config.onSearch(query, hasFocus)
                checkForMatchingUrl(query ?: "")
                post { isProcessingSearchKeyword = false }
            }
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_DONE ||
                    event?.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_ENTER
                ) {
                    if (WalletContextManager.delegate?.get()?.handleDeeplink(text.toString()) == true) {
                        setText("")
                        clearFocus()
                        hideKeyboard()
                        return@setOnEditorActionListener true
                    }
                    val browserConfig = searchMatchedSite?.let { matched ->
                        InAppBrowserConfig(
                            url = matched.url,
                            injectDappConnect = true,
                            saveInVisitedHistory = true
                        )
                    } ?: run {
                        val (isValidUrl, uri) = InAppBrowserVC.convertToUri(text.toString())
                        if (!isValidUrl)
                            ExploreHistoryStore.saveSearchHistory(text.toString())
                        InAppBrowserConfig(
                            url = uri.toString(),
                            injectDappConnect = true,
                            saveInVisitedHistory = isValidUrl
                        )
                    }
                    config.presentBrowser(browserConfig)
                    clearFocus()
                    hideKeyboard()
                }
                false
            }
        }
    }

    private var shadow: PillShadowView? = null

    private val searchFocused = BoolAnimator(
        AnimationConstants.VERY_QUICK_ANIMATION,
        CubicBezierInterpolator.EASE_BOTH,
        false
    ) { _, _, _, _ ->
        updateWidth()
    }

    val collapsedWidth: Int by lazy {
        val hintWidth = editText.paint.measureText(
            LocaleController.getString("Search app or enter address")
        ).ceilToInt()
        (62.dp + hintWidth).coerceAtMost(COLLAPSED_MAX_WIDTH.dp)
    }

    init {
        addView(blurryBackgroundView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setBackgroundColor(Color.TRANSPARENT, 24f.dp, clipToBounds = true)
        addView(editText, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    fun attachShadow() {
        if (shadow == null)
            shadow = PillShadowView.attachTo(this, 24f.dp)
    }

    fun setupBlurWith(target: android.view.ViewGroup) {
        blurryBackgroundView.setupWith(target)
    }

    fun syncShadow() {
        shadow?.sync()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (changed) {
            shadow?.sync()
            config.onLayoutChanged()
        }
    }

    fun updateWidth() {
        if (layoutParams != null)
            layoutParams = layoutParams.apply {
                width = lerp(
                    collapsedWidth.toFloat(),
                    config.expandedWidthProvider().toFloat(),
                    searchFocused.floatValue
                ).roundToInt()
            }
        editText.setPaddingDp(
            lerp(21f, 16f, searchFocused.floatValue).ceilToInt(),
            0,
            lerp(0f, 48f, searchFocused.floatValue).ceilToInt(),
            0
        )
    }

    fun updateTheme() {
        editText.highlightColor = WColor.Tint.color.colorWithAlpha(51)
        isProcessingSearchKeyword = true
        checkForMatchingUrl(searchKeyword)
        isProcessingSearchKeyword = false
    }

    fun setSearchText(text: String) {
        editText.requestFocus()
        editText.setText(text)
    }

    fun currentText(): String {
        return if (searchMatchedSite != null) searchKeyword else (editText.text?.toString() ?: "")
    }

    fun restoreText(text: String) {
        editText.setText(text)
    }

    fun checkForMatchingUrl(keyword: String) {
        searchKeyword = keyword
        if (keyword.isEmpty())
            return
        searchMatchedSite =
            if (keyword.isEmpty() || !editText.hasFocus())
                null
            else
                ExploreHistoryStore.exploreHistory?.visitedSites?.firstOrNull {
                    it.url.toUri().host?.startsWith(keyword) == true ||
                        it.url.startsWith(keyword)
                }
        searchMatchedSite?.let { matchedSite ->
            val urlPart = matchedSite.url.toUri().let { uri ->
                if (uri.host?.startsWith(keyword) == true) {
                    uri.host
                } else {
                    "${uri.scheme}://${uri.host}"
                }
            }
            val txt = "$urlPart — ${matchedSite.title}"
            val spannable = SpannableString(txt)
            spannable.setSpan(
                ForegroundColorSpan(WColor.Tint.color),
                (urlPart?.length ?: 0),
                txt.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            editText.setText(spannable)
            val length = editText.length()
            editText.setSelection(
                keyword.length.coerceAtMost(length),
                txt.length.coerceAtMost(length)
            )
            post { scrollTo(0, 0) }
        }
    }

    fun clearSearchAutoComplete() {
        editText.setText(searchKeyword)
        checkForMatchingUrl(searchKeyword)
    }
}
