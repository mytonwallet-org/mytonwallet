package org.mytonwallet.app_air.uicreatewallet.viewControllers.importWallet

import android.annotation.SuppressLint
import android.content.Context
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.View.OnFocusChangeListener
import android.view.View.TEXT_ALIGNMENT_CENTER
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getTextFromClipboard
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.WWordInput
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.suggestion.WSuggestionView
import org.mytonwallet.app_air.uicreatewallet.viewControllers.intro.IntroVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.walletAdded.WalletAddedVC
import org.mytonwallet.app_air.uipasscode.viewControllers.setPasscode.SetPasscodeVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.constants.PossibleWords
import org.mytonwallet.app_air.walletcore.helpers.PrivateKeyHelper
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import java.lang.ref.WeakReference
import kotlin.math.max

@SuppressLint("ViewConstructor")
class ImportWalletVC(
    context: Context,
    private val network: MBlockchainNetwork,
    // Used when adding new accounts. (not first mnemonic wallet)
    private val passedPasscode: String?
) :
    WViewController(context), WThemedView, ImportWalletVM.Delegate, WEditText.Delegate {
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

    private val animationView: WAnimationView by lazy {
        WAnimationView(context).apply {
            play(
                org.mytonwallet.app_air.uicomponents.R.raw.animation_snitch, true,
                onStart = {
                    fadeIn()
                })
        }
    }
    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            text = LocaleController.getString("Enter Secret Words")
            setStyle(28f, WFont.SemiBold)
            gravity = Gravity.CENTER
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = LocaleController.getStringWithKeyValues(
                "\$auth_import_mnemonic_description",
                listOf(
                    Pair(
                        "%counts%", LocaleController.getFormattedEnumeration(
                            listOf("12", "24"),
                            "or"
                        )
                    )
                )
            )
                .toProcessedSpannableStringBuilder()
            textAlignment = TEXT_ALIGNMENT_CENTER
        }
    }

    private val pasteButton: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.SemiBold)
            text = LocaleController.getString("Paste from Clipboard")
            setTextColor(WColor.Tint.color)
            setPaddingDp(16, 8, 16, 8)
            setOnClickListener {
                pasteFromClipboard()
            }
        }
    }

    private val continueButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.PRIMARY)
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
            if (nextFocusView != null) {
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
        v.addView(animationView, ViewGroup.LayoutParams(104.dp, 104.dp))
        v.addView(titleLabel, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(subtitleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        v.addView(pasteButton, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        for (wordNumber in 1..24) {
            val wordInputView = WWordInput(context, wordNumber, this)
            wordInputViews.lastOrNull()?.textField?.nextFocusView =
                WeakReference(wordInputView.textField)
            v.addView(wordInputView, ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            wordInputViews.add(wordInputView)
            wordInputView.textField.setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_NEXT) {
                    wordInputViews.getOrNull(wordNumber)?.textField?.requestFocus()
                    return@setOnEditorActionListener true
                }
                false
            }
            wordInputView.textField.onFocusChangeListener = OnFocusChangeListener { _, hasFocus ->
                if (hasFocus) {
                    makeFieldVisible(wordInputView)
                } else {
                    wordInputView.checkValue()
                }
            }
        }
        wordInputViews.last().textField.apply {
            setImeOptions(EditorInfo.IME_ACTION_DONE)
            setOnEditorActionListener { _, actionId, _ ->
                clearFocus()
                if (actionId == EditorInfo.IME_ACTION_DONE) {
                    importPressed()
                    return@setOnEditorActionListener true
                }
                false
            }
        }
        v.addView(continueButton, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(suggestionView, ViewGroup.LayoutParams(0, 48.dp))
        v.clipChildren = false
        v.clipToPadding = false
        v.setConstraints {
            toTopPx(
                animationView,
                WNavigationBar.DEFAULT_HEIGHT.dp + (navigationController?.getSystemBars()?.top
                    ?: 0)
            )
            toCenterX(animationView)
            topToBottom(titleLabel, animationView, 24f)
            toCenterX(titleLabel, 20f)
            topToBottom(subtitleLabel, titleLabel, 20f)
            toCenterX(subtitleLabel, 48f)
            topToBottom(pasteButton, subtitleLabel, 1f)
            toCenterX(pasteButton)

            val containerWidth = (navigationController?.width?.takeIf { it > 0 }
                ?: ApplicationContextHolder.screenWidth)
            val wordInputWidth = (containerWidth - 64.dp - 16.dp) / 2

            var prevLeftWordInput: WWordInput? = null
            for (i in 0..11) {
                val wordInput = wordInputViews[i]
                topToBottom(
                    wordInput,
                    prevLeftWordInput ?: pasteButton,
                    if (prevLeftWordInput == null) 29f else 10f
                )
                toStart(wordInput, 32f)
                constrainWidth(wordInput.id, wordInputWidth)
                prevLeftWordInput = wordInput
            }

            var prevRightWordInput: WWordInput? = null
            for (i in 12..23) {
                val wordInput = wordInputViews[i]
                topToBottom(
                    wordInput,
                    prevRightWordInput ?: pasteButton,
                    if (prevRightWordInput == null) 29f else 10f
                )
                toEnd(wordInput, 32f)
                constrainWidth(wordInput.id, wordInputWidth)
                prevRightWordInput = wordInput
            }

            topToBottom(continueButton, prevLeftWordInput!!, 16f)
            toCenterX(continueButton, 32f)
            toBottomPx(
                continueButton,
                48.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
        v
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
        if (navigationController?.viewControllers?.firstOrNull() !is IntroVC)
            navigationBar?.addCloseButton()

        view.addView(scrollView, ViewGroup.LayoutParams(0, 0))
        view.setConstraints {
            allEdges(scrollView)
        }

        val scrollOffsetToShowNav =
            96.dp + WNavigationBar.DEFAULT_HEIGHT.dp + (navigationController?.getSystemBars()?.top
                ?: 0)
        scrollView.onScrollChange = { y ->
            if (y > 0) {
                topReversedCornerView?.resumeBlurring()
            } else {
                topReversedCornerView?.pauseBlurring(false)
            }
            if (y > scrollOffsetToShowNav) {
                setNavTitle(LocaleController.getString("Enter Secret Words") + network.localizedIdentifier)
                setTopBlur(true, animated = true)
            } else {
                setNavTitle("")
                setTopBlur(false, animated = true)
            }
        }

        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollingContentView.setConstraints {
            toBottomPx(
                continueButton,
                48.dp +
                    max(
                        (navigationController?.getSystemBars()?.bottom ?: 0),
                        (window?.imeInsets?.bottom ?: 0)
                    )
            )
        }
        if (activeField != null && (window?.imeInsets?.bottom ?: 0) > 0)
            makeFieldVisible(activeField!!)
    }

    override val isTinted = true
    override fun updateTheme() {
        scrollingContentView.setBackgroundColor(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.PrimaryText.color)
        pasteButton.addRippleEffect(WColor.TintRipple.color, 10f.dp)
    }

    private fun importPressed() {
        val words =
            wordInputViews
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
        if (words.size != 12 && words.size != 24) {
            showMnemonicAlert()
            return
        }

        view.lockView()
        continueButton.isLoading = true
        importWalletVM.importWallet(words = words)
    }

    private var activeField: WWordInput? = null
    private fun makeFieldVisible(view: WWordInput) {
        if (activeField != view)
            activeField = view
        scrollView.makeViewVisible(activeField!!)
        suggestionView.attachToWordInput(activeField!!)
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
        if (passedPasscode == null) {
            continueButton.isLoading = false
            view.unlockView()
            push(SetPasscodeVC(context, true, null) { passcode, biometricsActivated ->
                importWalletVM.finalizeAccount(window!!, network, words, passcode, biometricsActivated, 0)
            }, onCompletion = {
                navigationController?.removePrevViewControllers()
            })
        } else {
            importWalletVM.finalizeAccount(window!!, network, words, passedPasscode, null, 0)
        }
    }

    override fun finalizedImport(accountId: String) {
        WalletCore.activateAccount(
            accountId,
            notifySDK = false
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
                showError(MBridgeError.UNKNOWN)
                return@activateAccount
            } else {
                if (WGlobalStorage.accountIds().size < 2) {
                    push(WalletAddedVC(context, false), {
                        navigationController?.removePrevViewControllers()
                    })
                } else {
                    WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
                    window!!.dismissLastNav()
                }
            }
        }
    }

    override fun viewWillDisappear() {
        // Override to prevent keyboard from being dismissed!
    }

    override fun showError(error: MBridgeError?) {
        if (navigationController?.viewControllers?.last() != this) {
            navigationController?.viewControllers?.last()?.showError(error)
            return
        }
        showAlert(
            LocaleController.getString(
                if (error == MBridgeError.INVALID_MNEMONIC)
                    "Wrong Phrase"
                else
                    "Error"
            ),
            (error ?: MBridgeError.UNKNOWN).toLocalized
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
        if (words.size == 12 || words.size == 24 || PrivateKeyHelper.isMnemonicPrivateKey(words))
            importPressed()
    }

    private fun pasteFromClipboard() {
        val clipText = context.getTextFromClipboard()
        if (clipText.isNullOrEmpty()) {
            return
        }

        wordInputViews.firstOrNull()?.textField?.handlePaste(clipText)
    }

}
