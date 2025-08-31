package org.mytonwallet.app_air.uicreatewallet.viewControllers.wordCheck

import WNavigationController
import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.View.OnFocusChangeListener
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderAndActionsView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.WWordInput
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
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
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.uihome.tabs.TabsVC
import java.lang.ref.WeakReference
import kotlin.math.max

@SuppressLint("ViewConstructor")
class WordCheckVC(
    context: Context,
    val words: Array<String>,
    private val wordIndices: List<Int>,
    private val isFirstWallet: Boolean,
    // Used when adding new account (not first account!)
    private var passedPasscode: String?
) :
    WViewController(context), WordCheckVM.Delegate, WEditText.Delegate {

    private val wordCheckVM by lazy {
        WordCheckVM(this)
    }

    override val isSwipeBackAllowed: Boolean
        get() {
            return !isKeyboardOpen
        }

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = true
    override val ignoreSideGuttering = true

    private val headerView: HeaderAndActionsView by lazy {
        val v = HeaderAndActionsView(
            context,
            R.raw.animation_test,
            null,
            false,
            LocaleController.getString("Let's Check!"),
            (LocaleController.getString("\$check_words_description") +
                LocaleController.getFormattedString(
                    "\$mnemonic_check_words_list",
                    listOf(wordIndices.joinToString(", ") { it.toString() })
                )).toProcessedSpannableStringBuilder(),
            onStarted = {
                scrollView.fadeIn()
            }
        )
        v
    }

    private val continueButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.PRIMARY)
        btn.text =
            LocaleController.getString("Continue")
        btn.setOnClickListener {
            checkPressed()
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
        v.addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        for (wordNumber in wordIndices) {
            val wordInputView = WWordInput(context, wordNumber, this)
            v.addView(wordInputView)
            wordInputViews.add(wordInputView)
            wordInputView.textField.setOnEditorActionListener { _, _, _ ->
                scrollToBottom()
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
                scrollToBottom()
                if (actionId == EditorInfo.IME_ACTION_DONE) {
                    clearFocus()
                    checkPressed()
                    return@setOnEditorActionListener true
                }
                false
            }
        }
        v.addView(continueButton, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(suggestionView, ViewGroup.LayoutParams(0, 48.dp))
        v.setConstraints {
            toTopPx(
                headerView,
                WNavigationBar.DEFAULT_HEIGHT.dp + (navigationController?.getSystemBars()?.top
                    ?: 0)
            )
            toCenterX(headerView)
            var prevWordInput: WWordInput? = null
            for (wordInput in wordInputViews) {
                topToBottom(
                    wordInput,
                    prevWordInput ?: headerView,
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

        scrollView.alpha = 0f
        view.addView(scrollView, ViewGroup.LayoutParams(0, 0))
        view.setConstraints({
            allEdges(scrollView)
        })

        val scrollOffsetToShowNav = (WNavigationBar.DEFAULT_HEIGHT + 135).dp
        scrollView.onScrollChange = { y ->
            if (y > 0) {
                topReversedCornerView?.resumeBlurring()
            } else {
                topReversedCornerView?.pauseBlurring(false)
            }
            if (y > scrollOffsetToShowNav) {
                setNavTitle(LocaleController.getString("Let's Check!"))
                setTopBlur(visible = true, animated = true)
            } else {
                setNavTitle("")
                setTopBlur(visible = false, animated = true)
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.Background.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollingContentView.setConstraints {
            toBottomPx(
                continueButton,
                48.dp + max(
                    (navigationController?.getSystemBars()?.bottom
                        ?: 0), (window?.imeInsets?.bottom
                        ?: 0)
                )
            )
        }
        if (activeField != null && (window?.imeInsets?.bottom ?: 0) > 0)
            makeFieldVisible(activeField!!)
    }

    private var activeField: WWordInput? = null
    private fun makeFieldVisible(view: WWordInput) {
        if (activeField != view)
            activeField = view
        scrollView.makeViewVisible(activeField!!)
        suggestionView.attachToWordInput(activeField!!)
    }

    private fun checkPressed() {
        // check if words are correct
        wordInputViews.forEachIndexed { index, wordInput ->
            if ((wordInput.textField.text ?: "").toString().trim()
                    .lowercase() != words[wordIndices[index] - 1].trim().lowercase()
            ) {
                showAlert(
                    LocaleController.getString("Incorrect words"),
                    LocaleController.getString("\$mnemonic_check_error"),
                    LocaleController.getString("See Words"),
                    {
                        pop()
                    },
                    LocaleController.getString("Try Again"),
                    {
                    }, preferPrimary = true
                )
                return
            }
        }
        if (isFirstWallet) {
            push(SetPasscodeVC(context, true, null) { passcode, biometricsActivated ->
                wordCheckVM.finalizeAccount(window!!, words, passcode, biometricsActivated, 0)
            }, onCompletion = {
                navigationController?.removePrevViewControllers()
            })
        } else {
            continueButton.isLoading = true
            view.lockView()
            wordCheckVM.finalizeAccount(window!!, words, passedPasscode ?: "", null, 0)
        }
    }

    private fun scrollToBottom() {
        scrollView.scrollToBottom()
    }

    override fun finalizedCreation(createdAccount: MAccount) {
        WalletCore.activateAccount(createdAccount.accountId, notifySDK = false) { res, err ->
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

    override fun showError(error: MBridgeError?) {
        if (navigationController?.viewControllers?.last() != this) {
            navigationController?.viewControllers?.last()?.showError(error)
            return
        }
        super.showError(error)
        continueButton.isLoading = false
        view.unlockView()
    }

    override fun pastedMultipleLines() {
        wordInputViews.forEach {
            it.checkValue()
        }
        if (wordInputViews.none { it.textField.text.toString().trim().isEmpty() })
            checkPressed()
    }

}
