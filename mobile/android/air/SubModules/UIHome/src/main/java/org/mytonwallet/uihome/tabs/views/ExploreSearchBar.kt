package org.mytonwallet.uihome.tabs.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.InputType
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.view.KeyEvent
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import androidx.core.net.toUri
import androidx.core.view.doOnPreDraw
import androidx.core.widget.doAfterTextChanged
import kotlin.math.roundToInt
import me.vkryl.android.animatorx.BoolAnimator
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore

@SuppressLint("ViewConstructor")
class ExploreSearchBar(context: Context, private val config: Config) : WFrameLayout(context) {

    class Config(
        /** Called whenever the search keyword changes; mirrors ExploreVC.search(query, focused). */
        val onSearch: (query: String?, focused: Boolean) -> Unit,
        /** Opens the promoted exact search result, if one exists for the current query. */
        val onOpenBestMatch: (onResolved: (Boolean) -> Unit) -> Boolean,
        /** Expanded (focused) width in px. Usually content width minus paddings. */
        val expandedWidthProvider: () -> Int,
        /** Present the in-app browser navigation built for a search submit. */
        val presentBrowser: (config: InAppBrowserConfig) -> Unit,
        /** Notified when bounds change so a host can re-sync external shadow/blur if needed. */
        val onLayoutChanged: () -> Unit = {}
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

    val editText by lazy {
        object : WSearchEditText(context) {
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
                if (isProcessingSearchKeyword || searchMatchedSite == null) return

                val keyword = searchKeyword
                val autoCompleteText = text?.toString()
                doOnPreDraw {
                    if (isProcessingSearchKeyword ||
                        searchMatchedSite == null ||
                        searchKeyword != keyword ||
                        text?.toString() != autoCompleteText
                    ) {
                        return@doOnPreDraw
                    }
                    isProcessingSearchKeyword = true
                    removeAutoCompleteSuffix()
                    searchMatchedSite = null
                    isProcessingSearchKeyword = false
                }
            }
        }.apply {
            hint = LocaleController.getString("Search app or enter address")
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            doAfterTextChanged { editable ->
                if (isProcessingSearchKeyword) return@doAfterTextChanged
                val suffixStart = autoCompleteSuffixStart()
                val keyword =
                    if (suffixStart >= 0) {
                        editable?.substring(0, suffixStart) ?: ""
                    } else {
                        editable?.toString() ?: ""
                    }
                if (keyword == searchKeyword) return@doAfterTextChanged
                if (suffixStart >= 0) {
                    isProcessingSearchKeyword = true
                    removeAutoCompleteSuffix()
                    isProcessingSearchKeyword = false
                }
                val shouldCheckForMatchingUrl = keyword.length > searchKeyword.length
                searchKeyword = keyword
                searchMatchedSite = null
                config.onSearch(searchKeyword, hasFocus())
                if (shouldCheckForMatchingUrl) {
                    post {
                        if (searchKeyword == keyword && this@apply.text?.toString() == keyword) {
                            checkForMatchingUrl(keyword)
                        }
                    }
                }
            }
            onFocusChangeListener = OnFocusChangeListener { _, hasFocus ->
                if (isProcessingSearchKeyword) return@OnFocusChangeListener
                if (!hasFocus &&
                    (context as? android.app.Activity)?.isChangingConfigurations == true
                ) {
                    return@OnFocusChangeListener
                }
                val query = if (hasFocus) text?.toString() else null
                config.onSearch(query, hasFocus)
                checkForMatchingUrl(query ?: "")
            }
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_DONE ||
                    (
                        event?.action == KeyEvent.ACTION_DOWN &&
                            event.keyCode == KeyEvent.KEYCODE_ENTER
                        )
                ) {
                    val submittedText = text.toString()
                    if (submittedText.isBlank()) {
                        clearFocus()
                        hideKeyboard()
                        return@setOnEditorActionListener true
                    }
                    if (WalletContextManager.delegate?.get()?.handleDeeplink(submittedText) ==
                        true
                    ) {
                        setText("")
                        clearFocus()
                        hideKeyboard()
                        return@setOnEditorActionListener true
                    }
                    val matchedSite = searchMatchedSite
                    val onBestMatchResolved: (Boolean) -> Unit = { opened ->
                        if (opened) {
                            setText("")
                        } else {
                            val browserConfig = matchedSite?.let { matched ->
                                InAppBrowserConfig(
                                    url = matched.url,
                                    injectDappConnect = true,
                                    saveInVisitedHistory = true
                                )
                            } ?: run {
                                val (isValidUrl, uri) = InAppBrowserVC.convertToUri(submittedText)
                                if (!isValidUrl) {
                                    ExploreHistoryStore.saveSearchHistory(submittedText)
                                }
                                InAppBrowserConfig(
                                    url = uri.toString(),
                                    injectDappConnect = true,
                                    saveInVisitedHistory = isValidUrl
                                )
                            }
                            config.presentBrowser(browserConfig)
                        }
                        clearFocus()
                        hideKeyboard()
                    }
                    if (config.onOpenBestMatch(onBestMatchResolved)) {
                        return@setOnEditorActionListener true
                    }
                    onBestMatchResolved(false)
                    return@setOnEditorActionListener true
                }
                false
            }
        }
    }

    private var glass: WGlassView? = null
    private var blurRoot: android.view.ViewGroup? = null

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
        setBackgroundColor(Color.TRANSPARENT, 24f.dp, clipToBounds = true)
        addView(editText, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    /** Adds the glass halo under this bar; call once it has a parent. */
    fun attachGlass() {
        if (glass != null) return
        glass = WGlassView.attachTo(
            this,
            24f.dp,
            GlassProviders.pill(WColor.SearchFieldBackground),
            blurRoot
        )
    }

    fun setupBlurWith(target: android.view.ViewGroup) {
        blurRoot = target
        glass?.setupWith(target)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (changed) {
            config.onLayoutChanged()
        }
    }

    fun updateWidth() {
        if (layoutParams != null) {
            val newWidth = lerp(
                collapsedWidth.toFloat(),
                config.expandedWidthProvider().toFloat(),
                searchFocused.floatValue
            ).roundToInt()
            if (layoutParams.width != newWidth) {
                layoutParams = layoutParams.apply {
                    width = newWidth
                }
            }
        }
        editText.setPaddingDpLocalized(
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

    fun currentText(): String =
        if (searchMatchedSite != null) searchKeyword else (editText.text?.toString() ?: "")

    fun restoreText(text: String) {
        editText.setText(text)
    }

    fun checkForMatchingUrl(keyword: String) {
        searchKeyword = keyword
        if (keyword.isEmpty()) return
        searchMatchedSite =
            if (!editText.hasFocus()) {
                null
            } else {
                ExploreHistoryStore.exploreHistory?.visitedSites?.firstOrNull {
                    it.url.toUri().host?.startsWith(keyword) == true ||
                        it.url.startsWith(keyword)
                }
            }
        val wasProcessingSearchKeyword = isProcessingSearchKeyword
        isProcessingSearchKeyword = true
        editText.removeAutoCompleteSuffix()
        isProcessingSearchKeyword = wasProcessingSearchKeyword
        searchMatchedSite?.let { matchedSite ->
            val urlPart = matchedSite.url.toUri().let { uri ->
                if (uri.host?.startsWith(keyword) == true) {
                    uri.host
                } else {
                    "${uri.scheme}://${uri.host}"
                }
            }
            val txt = "$urlPart — ${matchedSite.title}"
            if (txt.length <= keyword.length ||
                !txt.startsWith(keyword) ||
                editText.text?.toString() != keyword
            ) {
                return
            }
            val suffix = SpannableString(txt.substring(keyword.length))
            suffix.setSpan(
                ForegroundColorSpan(WColor.Tint.color),
                ((urlPart?.length ?: 0) - keyword.length).coerceIn(0, suffix.length),
                suffix.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            isProcessingSearchKeyword = true
            editText.appendAutoCompleteSuffix(suffix)
            isProcessingSearchKeyword = wasProcessingSearchKeyword
            post { scrollTo(0, 0) }
        }
    }

    fun clearSearchAutoComplete() {
        editText.removeAutoCompleteSuffix()
        checkForMatchingUrl(searchKeyword)
    }
}
