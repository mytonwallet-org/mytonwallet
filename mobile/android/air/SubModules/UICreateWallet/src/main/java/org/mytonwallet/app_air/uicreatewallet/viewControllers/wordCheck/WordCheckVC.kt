package org.mytonwallet.app_air.uicreatewallet.viewControllers.wordCheck

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderAndActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.WordCheckerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicreatewallet.WalletCreationVM
import org.mytonwallet.app_air.uicreatewallet.viewControllers.walletAdded.WalletAddedVC
import org.mytonwallet.app_air.uipasscode.viewControllers.setPasscode.SetPasscodeVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WordCheckMode
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import java.lang.ref.WeakReference
import kotlin.math.max

@SuppressLint("ViewConstructor")
class WordCheckVC(
    context: Context,
    val network: MBlockchainNetwork,
    val words: Array<String>,
    private val initialWordIndices: List<Int>,
    private val mode: WordCheckMode
) : WViewController(context), WalletCreationVM.Delegate {
    override val TAG = "WordCheck"

    private val walletCreationVM by lazy {
        WalletCreationVM(this)
    }

    override val isSwipeBackAllowed: Boolean
        get() {
            return !isKeyboardOpen && DEBUG_MODE
        }

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = true
    override val ignoreSideGuttering = true

    private val headerView: HeaderAndActionsView by lazy {
        val v = HeaderAndActionsView(
            context,
            HeaderAndActionsView.Media.Animation(
                animation = R.raw.animation_bill,
                repeat = true
            ),
            title = LocaleController.getString("Let's Check!"),
            subtitle = (LocaleController.getString("\$check_words_description") + "\n" +
                LocaleController.getStringWithKeyValues(
                    "\$mnemonic_check_words_list",
                    listOf(
                        Pair(
                            "%word_numbers%",
                            "**${currentWordIndices.joinToString(", ") { it.toString() }}**"
                        )
                    )
                )).toProcessedSpannableStringBuilder(),
            onStarted = {
                scrollView.fadeIn()
            }
        )
        v
    }

    private val wordsDoNotMatchLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        text = LocaleController.getString("Words don’t match, please try again.")
        gravity = Gravity.CENTER
        setTextColor(WColor.Red)
        alpha = 0f
    }

    private var wordCheckerViews = ArrayList<WordCheckerView>()
    private var currentWordIndices = initialWordIndices.toMutableList()

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.layoutDirection = View.LAYOUT_DIRECTION_LTR
        v.addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(wordsDoNotMatchLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        initialWordIndices.forEachIndexed { viewIndex, wordNumber ->
            val wordCheckerView = WordCheckerView(context, this::onWordSelected)
            wordCheckerView.config(
                index = wordNumber,
                word = words[wordNumber - 1],
                animated = false
            )
            v.addView(wordCheckerView)
            wordCheckerViews.add(wordCheckerView)
        }
        v.setConstraints {
            toTopPx(
                headerView,
                (WNavigationBar.DEFAULT_HEIGHT - 6).dp +
                    (navigationController?.getSystemBars()?.top ?: 0)
            )
            toCenterX(headerView)
            var prevWordCheckerView: WordCheckerView? = null
            for (wordCheckerView in wordCheckerViews) {
                topToBottom(
                    wordCheckerView,
                    prevWordCheckerView ?: headerView,
                    if (prevWordCheckerView == null) 40f else 24f
                )
                toCenterX(wordCheckerView, 32f)
                prevWordCheckerView = wordCheckerView
            }
            topToBottom(wordsDoNotMatchLabel, prevWordCheckerView!!, 40f)
            toCenterX(wordsDoNotMatchLabel, 32f)
            toBottomPx(
                wordsDoNotMatchLabel,
                32.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
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
        if ((mode as? WordCheckMode.CheckAndImport)?.isFirstWalletToAdd == false)
            navigationBar?.addCloseButton()

        scrollView.alpha = 0f
        view.addView(scrollView, ViewGroup.LayoutParams(0, 0))
        view.setConstraints {
            allEdges(scrollView)
        }

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
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollingContentView.setConstraints {
            toBottomPx(
                wordsDoNotMatchLabel,
                48.dp + max(
                    (navigationController?.getSystemBars()?.bottom
                        ?: 0), (window?.imeInsets?.bottom
                        ?: 0)
                )
            )
        }
    }

    private fun checkPressed() {
        var allValid = true
        val validIndices = mutableListOf<Int>()
        wordCheckerViews.forEachIndexed { index, wordChecker ->
            if (!wordChecker.validate()) {
                allValid = false
            } else {
                validIndices.add(index)
            }
        }
        view.lockView()
        if (!allValid) {
            Handler(Looper.getMainLooper()).postDelayed({
                view.unlockView()
                val usedIndices = currentWordIndices.toMutableSet()
                validIndices.forEach { validIndex ->
                    val availableIndices = (1..words.size).filter { it !in usedIndices }
                    val newWordIndex = availableIndices.random()
                    usedIndices.remove(currentWordIndices[validIndex])
                    usedIndices.add(newWordIndex)
                    currentWordIndices[validIndex] = newWordIndex
                }
                currentWordIndices.sort()
                wordCheckerViews.forEachIndexed { index, wordCheckerView ->
                    val wordNumber = currentWordIndices[index]
                    wordCheckerView.config(
                        index = wordNumber,
                        word = words[wordNumber - 1],
                        animated = true
                    )
                }
                Handler(Looper.getMainLooper()).postDelayed({
                    wordsDoNotMatchLabel.fadeIn()
                }, AnimationConstants.VERY_QUICK_ANIMATION)
                updateHeaderDescription()
            }, 1000)
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({
            when (mode) {
                WordCheckMode.Check -> {
                    pop()
                }

                is WordCheckMode.CheckAndImport -> {
                    view.unlockView()
                    if (mode.isFirstPasscodeProtectedWallet) {
                        push(SetPasscodeVC(context, true, null) { passcode, biometricsActivated ->
                            walletCreationVM.finalizeAccount(
                                window!!,
                                network,
                                words,
                                passcode,
                                biometricsActivated,
                                0
                            )
                        }, onCompletion = {
                            navigationController?.removePrevViewControllers()
                        })
                    } else {
                        view.lockView()
                        walletCreationVM.finalizeAccount(
                            window!!,
                            network,
                            words,
                            mode.passedPasscode ?: "",
                            null,
                            0
                        )
                    }
                }
            }
        }, 1000)
    }

    override fun finalizedCreation(createdAccount: MAccount) {
        if (WGlobalStorage.accountIds().size < 2) {
            push(WalletAddedVC(context, true), {
                navigationController?.removePrevViewControllers()
            })
        } else {
            WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
            window!!.dismissLastNav()
        }
    }

    override fun showError(error: MBridgeError?) {
        if (navigationController?.viewControllers?.last() != this) {
            navigationController?.viewControllers?.last()?.showError(error)
            return
        }
        super.showError(error)
        view.unlockView()
    }

    private fun onWordSelected() {
        val allSelected = wordCheckerViews.all {
            it.isWordSelected && !it.isValidatedAndWrong
        }
        wordsDoNotMatchLabel.fadeOut()
        if (allSelected)
            checkPressed()
    }

    private fun updateHeaderDescription() {
        val newDescription = (LocaleController.getString("\$check_words_description") + "\n" +
            LocaleController.getStringWithKeyValues(
                "\$mnemonic_check_words_list",
                listOf(
                    Pair(
                        "%word_numbers%",
                        "**${currentWordIndices.joinToString(", ") { it.toString() }}**"
                    )
                )
            )).toProcessedSpannableStringBuilder()
        headerView.setSubtitleText(newDescription)
    }

}
