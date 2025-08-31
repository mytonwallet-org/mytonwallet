package org.mytonwallet.app_air.uicreatewallet.viewControllers.importWallet

import WNavigationController
import android.annotation.SuppressLint
import android.content.Context
import android.text.Spannable
import android.text.SpannableString
import android.view.View
import android.view.View.OnFocusChangeListener
import android.view.View.TEXT_ALIGNMENT_CENTER
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.WWordInput
import org.mytonwallet.app_air.uicomponents.widgets.suggestion.WSuggestionView
import org.mytonwallet.app_air.uipasscode.viewControllers.setPasscode.SetPasscodeVC
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.constants.PossibleWords
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.uihome.tabs.TabsVC
import java.lang.ref.WeakReference
import kotlin.math.max

@SuppressLint("ViewConstructor")
class ImportWalletVC(
    context: Context,
    // Used when adding new accounts. (not first mnemonic wallet)
    private val passedPasscode: String?
) :
    WViewController(context), WThemedView, ImportWalletVM.Delegate, WEditText.Delegate {

    override val shouldDisplayTopBar = false
    override val ignoreSideGuttering = true

    private val importWalletVM by lazy {
        ImportWalletVM(this)
    }

    override val isSwipeBackAllowed: Boolean
        get() {
            return !isKeyboardOpen
        }

    override val shouldDisplayBottomBar = true

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.text = LocaleController.getString("24 Secret Words")
        lbl.setStyle(28f, WFont.Medium)
        lbl
    }

    private val subtitleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.setLineHeight(24f)
        val str = LocaleController.getString("\$auth_import_mnemonic_description")
            .toProcessedSpannableStringBuilder()
        val mediumWord = LocaleController.getString("24 Secret Words")
        val spannable: Spannable = SpannableString(str)
        spannable.setSpan(
            WTypefaceSpan(WFont.Regular.typeface),
            0,
            str.length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        val mediumWordIndex = str.indexOf(mediumWord)
        if (mediumWordIndex > -1)
            spannable.setSpan(
                WTypefaceSpan(WFont.Medium.typeface),
                mediumWordIndex,
                str.indexOf(mediumWord) + mediumWord.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        lbl.text = spannable
        lbl.textAlignment = TEXT_ALIGNMENT_CENTER
        lbl
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
            val nextFocusView = activeField?.focusSearch(View.FOCUS_DOWN)
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
        v.addView(titleLabel, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(subtitleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        for (wordNumber in 1..24) {
            val wordInputView = WWordInput(context, wordNumber, this)
            v.addView(wordInputView)
            wordInputViews.add(wordInputView)
            wordInputView.textField.setOnEditorActionListener { _, _, _ ->
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
        v.setConstraints {
            toTopPx(
                titleLabel,
                WNavigationBar.DEFAULT_HEIGHT.dp + (navigationController?.getSystemBars()?.top
                    ?: 0)
            )
            toCenterX(titleLabel)
            topToBottom(subtitleLabel, titleLabel, 8f)
            toCenterX(subtitleLabel, 48F)
            var prevWordInput: WWordInput? = null
            for (wordInput in wordInputViews) {
                topToBottom(
                    wordInput,
                    prevWordInput ?: subtitleLabel,
                    if (prevWordInput == null) 40F else 10F
                )
                toCenterX(wordInput, 48F)
                prevWordInput = wordInput
            }
            topToBottom(continueButton, prevWordInput!!, 16F)
            toCenterX(continueButton, 48F)
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

        view.addView(scrollView, ViewGroup.LayoutParams(0, 0))
        view.setConstraints {
            allEdges(scrollView)
        }

        val scrollOffsetToShowNav = WNavigationBar.DEFAULT_HEIGHT.dp
        scrollView.onScrollChange = { y ->
            if (y > 0) {
                topReversedCornerView?.resumeBlurring()
            } else {
                topReversedCornerView?.pauseBlurring(false)
            }
            if (y > scrollOffsetToShowNav) {
                setNavTitle(LocaleController.getString("24 Secret Words"))
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

    override fun updateTheme() {
        scrollingContentView.setBackgroundColor(WColor.Background.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.PrimaryText.color)
    }

    private fun importPressed() {
        // check if words are correct
        wordInputViews.forEachIndexed { _, wordInput ->
            wordInput.textField.text.toString().trim().lowercase().let {
                if (it.isNotEmpty() && !PossibleWords.All.contains(it)) {
                    showMnemonicAlert()
                    return
                }
            }
        }
        val words =
            wordInputViews
                .map { it.textField.text.toString().trim().lowercase() }
                .filter { it.isNotEmpty() }
                .toTypedArray()
        if (words.size != 12 && words.size != 24) {
            showMnemonicAlert()
            return
        }

        view.lockView()
        continueButton.isLoading = true
        importWalletVM.importWallet(
            words = words
        )
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
                importWalletVM.finalizeAccount(window!!, words, passcode, biometricsActivated, 0)
            }, onCompletion = {
                navigationController?.removePrevViewControllers()
            })
        } else {
            importWalletVM.finalizeAccount(window!!, words, passedPasscode, null, 0)
        }
    }

    override fun finalizedImport(accountId: String) {
        WalletCore.activateAccount(
            accountId,
            notifySDK = false
        ) { res, err ->
            if (res == null || err != null) {
                // Should not happen!
            } else {
                if (WGlobalStorage.accountIds().size < 2) {
                    val navigationController = WNavigationController(window!!)
                    navigationController.setRoot(TabsVC(context))
                    window!!.replace(navigationController, true)
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
        val wordsCount =
            wordInputViews.filter { it.textField.text.toString().trim().isNotEmpty() }.size
        if (wordsCount == 12 || wordsCount == 24)
            importPressed()
    }

}
