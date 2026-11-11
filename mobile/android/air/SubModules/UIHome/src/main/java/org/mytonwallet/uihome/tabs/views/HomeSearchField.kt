package org.mytonwallet.uihome.tabs.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.os.SystemClock
import android.text.InputType
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import androidx.core.view.doOnPreDraw
import androidx.core.widget.doAfterTextChanged
import me.vkryl.android.animatorx.BoolAnimator
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchBestMatchAction
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class HomeSearchField(
    context: Context,
    private val onSearch: (query: String?, focused: Boolean) -> Unit,
    private val onSubmit: (field: WSearchEditText) -> Unit,
    private val onFocusProgressChanged: () -> Unit = {}
) : WFrameLayout(context) {

    companion object {
        const val HEIGHT = 48
        private const val HINT_KEY = "Search or Ask"
        private const val SHORT_HINT_KEY = "Search"

        // The unfocused placeholder starts past the magnifier
        private const val PLACEHOLDER_START = 44
    }

    private var isProcessingSearchKeyword = false
    private var searchKeyword = ""
    private var autoCompleteKeyword: String? = null
    private var bestSearchMatchAction: Pair<String, SearchBestMatchAction?>? = null

    private val searchFocused =
        BoolAnimator(
            AnimationConstants.VERY_QUICK_ANIMATION,
            CubicBezierInterpolator.EASE_BOTH,
            false
        ) { _, _, _, _ ->
            updatePadding()
            onFocusProgressChanged()
        }

    val focusProgress: Float
        get() = searchFocused.floatValue

    /** How the field takes touches: as a field, letting them through, or swallowing them */
    enum class TouchMode { FIELD, PASS_THROUGH, SWALLOW }

    /**
     * Set while the field turns into the Agent bar's search circle. A gesture keeps the mode it began with; one that
     * began on the field ends there with a cancel and the rest of it is swallowed.
     */
    var touchMode = TouchMode.FIELD
        set(value) {
            if (field == value) return
            field = value
            if (gestureMode == TouchMode.FIELD && isGestureActive && value != TouchMode.FIELD) {
                val now = SystemClock.uptimeMillis()
                val cancel = MotionEvent.obtain(now, now, MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
                super.dispatchTouchEvent(cancel)
                cancel.recycle()
                gestureMode = TouchMode.SWALLOW
            }
        }
    private var gestureMode = TouchMode.FIELD
    private var isGestureActive = false

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                gestureMode = touchMode
                isGestureActive = true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> isGestureActive = false
        }
        return when (gestureMode) {
            TouchMode.FIELD -> super.dispatchTouchEvent(ev)
            TouchMode.PASS_THROUGH -> false
            TouchMode.SWALLOW -> true
        }
    }

    val editText: WSearchEditText = object : WSearchEditText(context) {
        override fun onFocusChanged(
            focused: Boolean,
            direction: Int,
            previouslyFocusedRect: Rect?
        ) {
            super.onFocusChanged(focused, direction, previouslyFocusedRect)
            searchFocused.animatedValue = focused
        }

        override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
            super.onLayout(changed, left, top, right, bottom)
            updateHint()
        }

        override fun onSelectionChanged(selStart: Int, selEnd: Int) {
            super.onSelectionChanged(selStart, selEnd)
            if (isProcessingSearchKeyword ||
                autoCompleteSuffixStart() < 0 ||
                !isSelectionChangeFromTouch()
            ) {
                return
            }

            val keyword = searchKeyword
            val autoCompleteText = text?.toString()
            doOnPreDraw {
                if (isProcessingSearchKeyword ||
                    autoCompleteSuffixStart() < 0 ||
                    searchKeyword != keyword ||
                    text?.toString() != autoCompleteText
                ) {
                    return@doOnPreDraw
                }
                isProcessingSearchKeyword = true
                removeAutoCompleteSuffix()
                isProcessingSearchKeyword = false
            }
        }
    }.apply {
        isHintSingleLine = true
        id = UIComponentsR.id.home_search_input
        isSaveEnabled = false
        hint = LocaleController.getString(HINT_KEY)
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        doAfterTextChanged {
            if (isProcessingSearchKeyword) return@doAfterTextChanged
            val suffixStart = autoCompleteSuffixStart()
            val keyword = typedText()
            if (keyword == searchKeyword) return@doAfterTextChanged
            if (suffixStart >= 0) {
                isProcessingSearchKeyword = true
                removeAutoCompleteSuffix()
                isProcessingSearchKeyword = false
            }
            val shouldCheckForMatchingUrl = keyword.length > searchKeyword.length
            searchKeyword = keyword
            autoCompleteKeyword = keyword.takeIf { shouldCheckForMatchingUrl }
            onSearch(searchKeyword, hasFocus())
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
            if (!hasFocus) {
                isProcessingSearchKeyword = true
                removeAutoCompleteSuffix()
                isProcessingSearchKeyword = false
            }
            val query = if (hasFocus) typedText() else null
            autoCompleteKeyword = query
            onSearch(query, hasFocus)
            checkForMatchingUrl(query ?: "")
        }
        setOnEditorActionListener { _, actionId, event ->
            if (event?.keyCode == KeyEvent.KEYCODE_ENTER) {
                // The release is consumed too, or `TextView` moves focus on it and the blur closes
                // the search before a submit waiting for results can open anything
                if (event.action == KeyEvent.ACTION_DOWN) onSubmit(this)
                return@setOnEditorActionListener true
            }
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                onSubmit(this)
                return@setOnEditorActionListener true
            }
            false
        }
    }

    init {
        setBackgroundColor(Color.TRANSPARENT, 24f.dp, clipToBounds = true)
        addView(editText, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        updatePadding()
    }

    fun setBestMatchAction(query: String, action: SearchBestMatchAction?) {
        bestSearchMatchAction = query to action
        if (query == searchKeyword) checkForMatchingUrl(query)
    }

    fun setSearchText(text: String) {
        editText.requestFocus()
        editText.setText(text)
    }

    fun currentText(): String = editText.typedText()

    fun restoreText(text: String) {
        editText.setText(text)
    }

    fun clearAutoComplete() {
        editText.removeAutoCompleteSuffix()
        checkForMatchingUrl(searchKeyword)
    }

    fun updateTheme() {
        editText.highlightColor = WColor.Tint.color.colorWithAlpha(51)
        isProcessingSearchKeyword = true
        editText.removeAutoCompleteSuffix()
        checkForMatchingUrl(searchKeyword)
        isProcessingSearchKeyword = false
    }

    private fun updatePadding() {
        editText.setPaddingDpLocalized(
            lerp(22f, 16f, searchFocused.floatValue).ceilToInt(),
            0,
            lerp(0f, 48f, searchFocused.floatValue).ceilToInt(),
            0
        )
    }

    private fun updateHint() {
        val fullHint = LocaleController.getString(HINT_KEY)
        val width = editText.width - PLACEHOLDER_START.dp - editText.compoundPaddingRight
        val hint = if (width <= 0 || editText.paint.measureText(fullHint) <= width) {
            fullHint
        } else {
            LocaleController.getString(SHORT_HINT_KEY)
        }
        if (hint == appliedHint) return
        appliedHint = hint
        editText.hint = hint
        editText.requestLayout()
    }

    private var appliedHint: String? = null

    private fun checkForMatchingUrl(keyword: String) {
        searchKeyword = keyword
        if (keyword.isEmpty()) return
        val action = bestSearchMatchAction
            ?.takeIf { it.first == keyword && autoCompleteKeyword == keyword }
            ?.second
            ?.takeIf { editText.typedText() == keyword }
        val completion = action?.suggestion?.drop(keyword.length)
        val suffixText = action?.let { "$completion — ${it.title}" }
        if (suffixText != null && editText.autoCompleteSuffixText() == suffixText) return
        val wasProcessingSearchKeyword = isProcessingSearchKeyword
        isProcessingSearchKeyword = true
        editText.removeAutoCompleteSuffix()
        if (action != null && completion != null && suffixText != null) {
            val suffix = SpannableString(suffixText)
            suffix.setSpan(
                ForegroundColorSpan(
                    (if (action.isAgent) WColor.PrimaryText else WColor.Tint).color
                ),
                completion.length,
                suffix.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            editText.appendAutoCompleteSuffix(suffix)
            post { scrollTo(0, 0) }
        }
        isProcessingSearchKeyword = wasProcessingSearchKeyword
    }
}
