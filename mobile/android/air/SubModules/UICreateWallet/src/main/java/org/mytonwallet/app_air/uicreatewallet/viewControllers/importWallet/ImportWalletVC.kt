package org.mytonwallet.app_air.uicreatewallet.viewControllers.importWallet

import android.annotation.SuppressLint
import android.content.Context
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.View.TEXT_ALIGNMENT_CENTER
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.view.doOnLayout
import androidx.core.view.isVisible
import java.lang.ref.WeakReference
import kotlin.math.max
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.LinedCenteredTitleView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getTextFromClipboard
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.ToastHelper
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.WWordInput
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.segmentedControlGroup.WSegmentedControlGroup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.suggestion.WSuggestionView
import org.mytonwallet.app_air.uicreatewallet.viewControllers.intro.IntroVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.walletAdded.WalletAddedVC
import org.mytonwallet.app_air.uipasscode.viewControllers.setPasscode.SetPasscodeVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletbasecontext.utils.withLocalizedNumbers
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.constants.PossibleWords
import org.mytonwallet.app_air.walletcore.helpers.PrivateKeyHelper
import org.mytonwallet.app_air.walletcore.models.MBridgeError

@SuppressLint("ViewConstructor")
class ImportWalletVC(
    context: Context,
    private val network: MBlockchainNetwork,
    // Used when adding new accounts. (not first mnemonic wallet)
    private val passedEnclaveToken: String?
) : WViewController(context),
    WThemedView,
    ImportWalletVM.Delegate,
    WEditText.Delegate {
    @Suppress("PropertyName")
    override val TAG = "ImportWallet"

    override val shouldDisplayTopBar = false
    override val ignoreSideGuttering = true

    override val isBackAllowed: Boolean
        get() = navigationController?.viewControllers?.firstOrNull() is IntroVC

    private val importWalletVM by lazy {
        ImportWalletVM(this)
    }

    override val isSwipeBackAllowed: Boolean
        get() {
            return !isKeyboardOpen
        }

    override val shouldDisplayBottomBar = true
    override val shouldHideKeyboardOnDisappear = false

    private val animationView: WAnimationView by lazy {
        WAnimationView(context).apply {
            play(
                org.mytonwallet.app_air.uicomponents.R.raw.animation_snitch,
                true,
                onStart = {
                    fadeIn()
                }
            )
        }
    }
    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            text = LocaleController.getString("Enter Secret Words")
            setStyle(28f, WFont.Medium)
            gravity = Gravity.CENTER
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(adaptiveFontSize())
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 26f)
            text = LocaleController.getStringWithKeyValues(
                $$"$auth_import_mnemonic_description",
                listOf(
                    Pair(
                        "%counts%",
                        LocaleController.getFormattedEnumeration(
                            listOf("12", "24").map { it.withLocalizedNumbers },
                            "or"
                        )
                    )
                )
            )
                .toProcessedSpannableStringBuilder()
            textAlignment = TEXT_ALIGNMENT_CENTER
        }
    }

    private val pasteButtonRipple = WRippleDrawable.create(25f.dp)
    private val pasteButtonIcon =
        context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_clipboard_24)
            ?.mutate()
            ?.apply { setBounds(0, 0, 20.dp, 20.dp) }

    private val pasteButton: WLabel by lazy {
        WLabel(context).apply {
            id = UIComponentsR.id.import_paste
            setStyle(16f, WFont.Medium)
            text = LocaleController.getString("Paste from Clipboard")
            gravity = Gravity.CENTER
            minHeight = 50.dp
            setPaddingDp(32, 0, 32, 0)
            setCompoundDrawablesRelative(pasteButtonIcon, null, null, null)
            compoundDrawablePadding = 5.dp
            background = pasteButtonRipple
            setOnClickListener {
                pasteFromClipboard()
            }
        }
    }

    private val orEnterManuallyView: LinedCenteredTitleView by lazy {
        LinedCenteredTitleView(context).apply {
            configure(LocaleController.getString("or enter manually"), 0, 0)
            configureText(WFont.Regular, WColor.SecondaryText)
            lineColor = WColor.SecondaryText
        }
    }

    private val navPasteButton: WImageButton by lazy {
        WImageButton(context).apply {
            setImageDrawable(
                context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_clipboard_24)
            )
            setPadding(8.dp, 8.dp, 8.dp, 8.dp)
            contentDescription = LocaleController.getString("Paste from Clipboard")
            updateColors(WColor.Tint, WColor.TintRipple)
            setOnClickListener {
                pasteFromClipboard()
            }
        }
    }

    private var activeWordCount = 12

    // Stable resource ids of the word fields, for UI automation
    private val wordInputTestIds = intArrayOf(
        UIComponentsR.id.import_word_1, UIComponentsR.id.import_word_2,
        UIComponentsR.id.import_word_3, UIComponentsR.id.import_word_4,
        UIComponentsR.id.import_word_5, UIComponentsR.id.import_word_6,
        UIComponentsR.id.import_word_7, UIComponentsR.id.import_word_8,
        UIComponentsR.id.import_word_9, UIComponentsR.id.import_word_10,
        UIComponentsR.id.import_word_11, UIComponentsR.id.import_word_12,
        UIComponentsR.id.import_word_13, UIComponentsR.id.import_word_14,
        UIComponentsR.id.import_word_15, UIComponentsR.id.import_word_16,
        UIComponentsR.id.import_word_17, UIComponentsR.id.import_word_18,
        UIComponentsR.id.import_word_19, UIComponentsR.id.import_word_20,
        UIComponentsR.id.import_word_21, UIComponentsR.id.import_word_22,
        UIComponentsR.id.import_word_23, UIComponentsR.id.import_word_24
    )

    private val wordCountSwitcher: WSegmentedControlGroup by lazy {
        WSegmentedControlGroup(context).apply {
            minimumHeight = 38.dp
            listOf(
                "12 Words" to UIComponentsR.id.import_mode_12,
                "24 Words" to UIComponentsR.id.import_mode_24
            ).forEach { (title, viewId) ->
                addView(
                    WLabel(context).apply {
                        id = viewId
                        layoutParams = ViewGroup.LayoutParams(WRAP_CONTENT, MATCH_PARENT)
                        setStyle(16f, WFont.Medium)
                        text = LocaleController.getString(title)
                        gravity = Gravity.CENTER
                        setPaddingDp(16, 0, 16, 0)
                    }
                )
            }
            setSelectedIndex(0)
            setOnSelectedOptionChangeCallback { index ->
                val count = if (index == 0) 12 else 24
                if (activeWordCount != count) {
                    activeWordCount = count
                    applyWordInputConstraints(scrollingContentView)
                    scrollToActiveFieldAfterLayout()
                }
            }
        }
    }

    private val continueButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.PRIMARY)
        btn.id = UIComponentsR.id.import_continue
        btn.text = LocaleController.getString("Continue")
        btn.setOnClickListener {
            importPressed()
        }
        btn
    }

    private val suggestionView: WSuggestionView by lazy {
        val v = WSuggestionView(context) {
            activeField?.textField?.setText(it)
            val nextFocusView = activeField?.textField?.nextFocusView?.get()
                ?: activeField?.focusSearch(View.FOCUS_DOWN)
            if (activeField == wordInputViews.getOrNull(activeWordCount - 1)) {
                activeField?.textField?.onEditorAction(EditorInfo.IME_ACTION_DONE)
            } else if (nextFocusView != null) {
                nextFocusView.requestFocus()
            } else {
                activeField?.clearFocus()
                suggestionView.attachToWordInput(null)
            }
        }
        v
    }

    private var wordInputViews = ArrayList<WWordInput>()

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.layoutDirection = View.LAYOUT_DIRECTION_LTR
        v.addView(animationView, ViewGroup.LayoutParams(96.dp, 96.dp))
        v.addView(titleLabel, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(subtitleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        v.addView(pasteButton, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(orEnterManuallyView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        for (wordNumber in 1..24) {
            val wordInputView = WWordInput(context, wordNumber, this)
            // Debug builds only: a named id would let accessibility services
            // locate the recovery phrase fields in release builds
            if (DEBUG_MODE) {
                wordInputView.textField.id = wordInputTestIds[wordNumber - 1]
            }
            wordInputViews.lastOrNull()?.textField?.nextFocusView =
                WeakReference(wordInputView.textField)
            v.addView(wordInputView, ConstraintLayout.LayoutParams(WRAP_CONTENT, 48.dp))
            wordInputViews.add(wordInputView)
            wordInputView.textField.setOnEditorActionListener { _, actionId, _ ->
                when (actionId) {
                    EditorInfo.IME_ACTION_NEXT -> {
                        wordInputViews.getOrNull(wordNumber)?.textField?.requestFocus()
                        true
                    }

                    EditorInfo.IME_ACTION_DONE -> {
                        wordInputView.textField.clearFocus()
                        importPressed()
                        true
                    }

                    else -> false
                }
            }
            wordInputView.onFocusChanged = { hasFocus ->
                if (hasFocus) {
                    activeField = wordInputView
                    suggestionView.attachToWordInput(wordInputView)
                    scrollToWordInput(wordInputView)
                } else {
                    wordInputView.checkValue()
                    // Focus moving to another word field re-attaches the suggestions right after
                    if (activeField == wordInputView) {
                        activeField = null
                        suggestionView.attachToWordInput(null)
                    }
                }
            }
        }
        v.addView(continueButton, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.clipChildren = false
        v.clipToPadding = false
        v.setConstraints {
            toTopPx(
                animationView,
                WNavigationBar.DEFAULT_HEIGHT.dp + (
                    navigationController?.getSystemBars()?.top
                        ?: 0
                    )
            )
            toCenterX(animationView)
            topToBottom(titleLabel, animationView, 24f)
            toCenterX(titleLabel, 20f)
            topToBottom(subtitleLabel, titleLabel, 20f)
            toCenterX(subtitleLabel, 48f)
            topToBottom(pasteButton, subtitleLabel, 18f)
            toCenterX(pasteButton)

            topToBottom(orEnterManuallyView, pasteButton, 42f)
            toCenterX(orEnterManuallyView, 32f)
        }
        applyWordInputConstraints(v)
        v
    }

    private fun applyWordInputConstraints(container: WView) {
        val isTwoColumns = window?.isWideLayout == true
        val columnCount = if (isTwoColumns) activeWordCount / 2 else activeWordCount
        val containerWidth = (
            navigationController?.width?.takeIf { it > 0 }
                ?: ApplicationContextHolder.screenWidth
            )
            .coerceAtMost(WWindow.WIDE_LAYOUT_INNER_WIDTH_DP.dp) -
            systemBarStartInset - systemBarEndInset
        val wordInputWidth = if (isTwoColumns) {
            (containerWidth - 64.dp - 16.dp) / 2
        } else {
            containerWidth - 64.dp
        }
        val rowSpacing = if (isTwoColumns) 10f else 16f

        wordInputViews.forEachIndexed { i, wordInput ->
            wordInput.visibility = if (i < activeWordCount) View.VISIBLE else View.GONE
            wordInput.textField.setImeOptions(
                if (i == activeWordCount - 1) {
                    EditorInfo.IME_ACTION_DONE
                } else {
                    EditorInfo.IME_ACTION_NEXT
                }
            )
        }

        container.setConstraints {
            wordInputViews.forEach {
                clear(it.id, ConstraintSet.TOP)
                clear(it.id, ConstraintSet.START)
                clear(it.id, ConstraintSet.END)
            }

            var prevLeftWordInput: WWordInput? = null
            for (i in 0 until columnCount) {
                val wordInput = wordInputViews[i]
                topToBottom(
                    wordInput,
                    prevLeftWordInput ?: orEnterManuallyView,
                    if (prevLeftWordInput == null) 24f else rowSpacing
                )
                toStart(wordInput, 32f)
                constrainWidth(wordInput.id, wordInputWidth)
                prevLeftWordInput = wordInput
            }

            var prevRightWordInput: WWordInput? = null
            for (i in columnCount until activeWordCount) {
                val wordInput = wordInputViews[i]
                topToBottom(
                    wordInput,
                    prevRightWordInput ?: orEnterManuallyView,
                    if (prevRightWordInput == null) 24f else rowSpacing
                )
                toEnd(wordInput, 32f)
                constrainWidth(wordInput.id, wordInputWidth)
                prevRightWordInput = wordInput
            }

            prevLeftWordInput?.let { topToBottom(continueButton, it, 16f) }
            toCenterX(continueButton, 32f)
            // Keeps Continue above the suggestions footprint even while they are empty
            toBottomPx(continueButton, bottomInset + suggestionFootprint + 16.dp)
        }
    }

    private val bottomInset: Int
        get() = max(
            navigationController?.getSystemBars()?.bottom ?: 0,
            navigationController?.imeInsetBottom ?: 0
        )

    // Suggestions height plus their bottom margin, see applySuggestionViewConstraints
    private val suggestionFootprint: Int
        get() = 64.dp + 8.dp

    private fun setActiveWordCount(count: Int) {
        if (activeWordCount == count) return
        activeWordCount = count
        wordCountSwitcher.setSelectedIndex(if (count == 12) 0 else 1)
        applyWordInputConstraints(scrollingContentView)
        scrollToActiveFieldAfterLayout()
    }

    private val scrollView: WScrollView by lazy {
        val sv = WScrollView(WeakReference(this))
        sv.addView(scrollingContentView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        sv
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle("")
        setupNavBar(true)
        navigationBar?.setCenteredTitleView(wordCountSwitcher, animated = false)
        val navPasteButtonLayoutParams = ConstraintLayout.LayoutParams(40.dp, 40.dp)
        if (navigationController?.viewControllers?.firstOrNull() !is IntroVC) {
            navigationBar?.addCloseButton()
            navigationBar?.addLeadingView(navPasteButton, navPasteButtonLayoutParams)
        } else {
            navigationBar?.addTrailingView(navPasteButton, navPasteButtonLayoutParams)
        }
        listOf(wordCountSwitcher, navPasteButton).forEach {
            it.alpha = 0f
            it.visibility = View.INVISIBLE
        }

        view.addView(
            scrollView,
            ConstraintLayout.LayoutParams(0, 0).apply {
                matchConstraintMaxWidth = WWindow.WIDE_LAYOUT_INNER_WIDTH_DP.dp
            }
        )
        view.addView(
            suggestionView,
            ConstraintLayout.LayoutParams(0, 64.dp).apply {
                matchConstraintMaxWidth = WWindow.WIDE_LAYOUT_INNER_WIDTH_DP.dp - 16.dp
            }
        )
        view.setConstraints {
            allEdges(scrollView)
        }
        applySuggestionViewConstraints()

        scrollView.onScrollChange = {
            updateTopBar()
        }

        updateTheme()
    }

    override fun insetsUpdated() {
        val wasKeyboardOpen = isKeyboardOpen
        super.insetsUpdated()
        scrollView.setPaddingRelative(systemBarStartInset, 0, systemBarEndInset, 0)
        scrollView.bottomObscuredInset = bottomInset + suggestionFootprint
        applyWordInputConstraints(scrollingContentView)
        applySuggestionViewConstraints()
        if (isKeyboardOpen != wasKeyboardOpen) {
            scrollToActiveFieldAfterLayout()
        }
        updateTopBar()
        scrollingContentView.setConstraints {
            toTopPx(
                animationView,
                WNavigationBar.DEFAULT_HEIGHT.dp + (
                    navigationController?.getSystemBars()?.top
                        ?: 0
                    )
            )
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.PrimaryText.color)
        pasteButton.setTextColor(WColor.TextOnTint.color)
        pasteButtonIcon?.setTint(WColor.TextOnTint.color)
        pasteButtonRipple.backgroundColor = WColor.Tint.color
        pasteButtonRipple.rippleColor = WColor.BackgroundRipple.color
        wordCountSwitcher.updateTheme()
        wordCountSwitcher.setBackgroundColor(WColor.ThumbBackground.color, 19f.dp)
    }

    private fun importPressed() {
        val words =
            wordInputViews
                .take(activeWordCount)
                .map { it.textField.text.toString().trim().lowercase() }
                .filter { it.isNotEmpty() }
                .toTypedArray()

        if (PrivateKeyHelper.isMnemonicPrivateKey(words)) {
            view.lockView()
            continueButton.isLoading = true
            importWalletVM.importWallet(words = words)
            return
        }

        // check if mnemonic words are correct
        for (word in words) {
            if (!PossibleWords.All.contains(word)) {
                showMnemonicAlert()
                return
            }
        }
        if (words.size != activeWordCount) {
            showMnemonicAlert()
            return
        }

        view.lockView()
        continueButton.isLoading = true
        importWalletVM.importWallet(words = words)
    }

    private var activeField: WWordInput? = null
    private var hasAlignedFirstRow = false

    private fun applySuggestionViewConstraints() {
        view.setConstraints {
            toStartPx(suggestionView, systemBarStartInset + 8.dp)
            toEndPx(suggestionView, systemBarEndInset + 8.dp)
            toBottomPx(suggestionView, bottomInset + 8.dp)
        }
    }

    private fun scrollToActiveFieldAfterLayout() {
        val field = activeField?.takeIf { it.isVisible } ?: return
        scrollingContentView.doOnLayout { scrollToWordInput(field) }
    }

    private fun scrollToWordInput(input: WWordInput) {
        val visibleTop = (navigationController?.getSystemBars()?.top ?: 0) +
            WNavigationBar.DEFAULT_HEIGHT.dp + 16.dp
        val visibleBottom = scrollView.height - bottomInset - 48.dp - 32.dp
        var target = if (hasAlignedFirstRow) {
            scrollView.scrollY
        } else {
            wordInputViews.first().top - visibleTop
        }
        hasAlignedFirstRow = true
        if (input.bottom - target > visibleBottom) {
            target = input.bottom - visibleBottom
        } else if (input.top - target < visibleTop) {
            target = input.top - visibleTop
        }
        val maxScroll = max(0, scrollingContentView.height - scrollView.height)
        scrollView.smoothScrollTo(0, target.coerceIn(0, maxScroll))
    }

    private var isTopBarExpanded = false
    private fun updateTopBar() {
        val isHeaderScrolledAway = titleLabel.isLaidOut &&
            scrollView.scrollY > titleLabel.bottom -
            (navigationController?.getSystemBars()?.top ?: 0) - WNavigationBar.DEFAULT_HEIGHT.dp
        val expanded = isKeyboardOpen || isHeaderScrolledAway
        if (isTopBarExpanded == expanded) return
        isTopBarExpanded = expanded
        setTopBlur(expanded, animated = true)
        listOf(wordCountSwitcher, navPasteButton).forEach { control ->
            if (expanded) {
                control.visibility = View.VISIBLE
                control.fadeIn()
            } else {
                control.fadeOut {
                    if (!isTopBarExpanded) control.visibility = View.INVISIBLE
                }
            }
        }
    }

    private fun showMnemonicAlert() {
        // a word is incorrect.
        showAlert(
            LocaleController.getString("Wrong Phrase"),
            LocaleController.getString("InvalidMnemonic"),
            LocaleController.getString("OK")
        )
    }

    override fun walletCanBeImported(words: Array<String>) {
        val window = window ?: return
        if (passedEnclaveToken == null) {
            continueButton.isLoading = false
            view.unlockView()
            push(
                SetPasscodeVC(context, true, null) { enclaveToken, biometricsActivated ->
                    importWalletVM.finalizeAccount(
                        window,
                        network,
                        words,
                        biometricsActivated,
                        0,
                        enclaveToken
                    )
                },
                onCompletion = {
                    navigationController?.removePrevViewControllers()
                }
            )
        } else {
            importWalletVM.finalizeAccount(window, network, words, null, 0, passedEnclaveToken)
        }
    }

    override fun finalizedImport(accountId: String, importedAccountsCount: Int) {
        WalletCore.activateAccount(
            accountId,
            notifySDK = true
        ) { res, err ->
            if (res == null || err != null) {
                // Should not happen!
                Logger.e(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(
                            "activateAccount: Failed on import finalization err=$err",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        ).build()
                )
                continueButton.isLoading = false
                view.unlockView()
                showError(MBridgeError.Type.UNKNOWN)
                return@activateAccount
            } else {
                if (WGlobalStorage.accountIds().size <= importedAccountsCount) {
                    push(WalletAddedVC(context, false, importedAccountsCount), {
                        navigationController?.removePrevViewControllers()
                    })
                } else {
                    WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
                    ToastHelper.notifyWalletImported(
                        viewController = this,
                        accountId = accountId
                    )
                    window?.dismissLastNav()
                }
            }
        }
    }

    override fun showError(error: MBridgeError?) {
        if (navigationController?.viewControllers?.lastOrNull() != this) {
            navigationController?.viewControllers?.lastOrNull()?.showError(error)
            return
        }
        showAlert(
            LocaleController.getString(
                if (error == MBridgeError.Type.INVALID_MNEMONIC) "Wrong Phrase" else "Error"
            ),
            (error ?: MBridgeError.Type.UNKNOWN).toLocalized
        )
        continueButton.isLoading = false
        view.unlockView()
    }

    override fun pastedMultipleLines() {
        wordInputViews.forEach {
            it.checkValue()
        }
        val words =
            wordInputViews
                .map { it.textField.text.toString().trim().lowercase() }
                .filter { it.isNotEmpty() }
                .toTypedArray()
        if (words.size == 12 || words.size == 24) {
            setActiveWordCount(words.size)
            importPressed()
        } else if (PrivateKeyHelper.isMnemonicPrivateKey(words)) {
            importPressed()
        }
    }

    private fun pasteFromClipboard() {
        val clipText = context.getTextFromClipboard()
        if (clipText.isNullOrEmpty()) {
            return
        }

        wordInputViews.firstOrNull()?.textField?.handlePaste(clipText)
    }
}
