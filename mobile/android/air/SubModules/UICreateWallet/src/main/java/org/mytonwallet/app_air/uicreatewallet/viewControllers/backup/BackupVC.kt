package org.mytonwallet.app_air.uicreatewallet.viewControllers.backup

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.CheckboxItemView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicreatewallet.viewControllers.intro.IntroVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.wordDisplay.WordDisplayVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import java.lang.ref.WeakReference
import kotlin.math.max

@SuppressLint("ViewConstructor")
class BackupVC(
    context: Context,
    private val network: MBlockchainNetwork,
    private val words: Array<String>,
    private val isFirstPasscodeProtectedWallet: Boolean,
    // Used when adding new account (not first account!)
    private val passedPasscode: String?
) : WViewController(context) {
    override val TAG = "Backup"

    override val shouldDisplayTopBar = false
    override val ignoreSideGuttering = true

    override val isBackAllowed = true

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
            text = LocaleController.getString("Create Backup")
            setStyle(28f, WFont.SemiBold)
            setTextColor(WColor.PrimaryText.color)
            gravity = Gravity.CENTER
        }
    }

    private val checks = arrayOf(
        "\$safety_rules_one",
        "\$safety_rules_two",
        "\$safety_rules_three"
    )
    private val checkboxViews = checks.mapIndexed { i, it ->
        CheckboxItemView(context, i == 0).apply {
            setText(LocaleController.getString(it).trim().toProcessedSpannableStringBuilder())
        }
    }

    private val toWordsButton: WButton by lazy {
        WButton(context, WButton.Type.PRIMARY).apply {
            text = LocaleController.getString("Go to Words")
            isEnabled = false
            setOnClickListener {
                push(
                    WordDisplayVC(
                        context = context,
                        network = network,
                        words = words,
                        isFirstWalletToAdd = true,
                        isFirstPasscodeProtectedWallet = isFirstPasscodeProtectedWallet,
                        passedPasscode = passedPasscode
                    )
                )
            }
        }
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.layoutDirection = View.LAYOUT_DIRECTION_LTR
        v.addView(animationView, ViewGroup.LayoutParams(132.dp, 132.dp))
        v.addView(titleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        for (checkboxView in checkboxViews) {
            v.addView(checkboxView, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        }
        v.addView(toWordsButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        v.setConstraints {
            toTopPx(
                animationView,
                WNavigationBar.DEFAULT_HEIGHT.dp + (navigationController?.getSystemBars()?.top
                    ?: 0)
            )
            toCenterX(animationView)
            topToBottom(titleLabel, animationView, 24f)
            toCenterX(titleLabel, 10f)
            checkboxViews.forEachIndexed { i, checkboxView ->
                checkboxView.setOnClickListener {
                    checkboxView.isChecked = !checkboxView.isChecked
                    if (checkboxView.isChecked) {
                        checkboxViews.getOrNull(i + 1)?.let {
                            it.isBoxEnabled = true
                        } ?: run {
                            toWordsButton.isEnabled = true
                        }
                    } else {
                        for (i in i + 1 until checks.count())
                            checkboxViews.getOrNull(i)?.isBoxEnabled = false
                        toWordsButton.isEnabled = false
                    }
                }
                if (i == 0) {
                    topToBottom(checkboxView, titleLabel, 40f)
                } else {
                    topToBottom(checkboxView, checkboxViews[i - 1], 16f)
                }
                toCenterX(checkboxView, 10f)
            }
            topToBottom(toWordsButton, checkboxViews.last(), 16f)
            toCenterX(toWordsButton, 32f)
            toBottomPx(
                toWordsButton,
                48.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
        // Push button to bottom of the screen
        v.post {
            if (view.height > v.height) {
                v.setConstraints {
                    topToBottomPx(
                        toWordsButton,
                        checkboxViews.last(),
                        16.dp + view.height - v.height
                    )
                }
            }
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
            124.dp + WNavigationBar.DEFAULT_HEIGHT.dp + (navigationController?.getSystemBars()?.top
                ?: 0)
        scrollView.onScrollChange = { y ->
            if (y > 0) {
                topReversedCornerView?.resumeBlurring()
            } else {
                topReversedCornerView?.pauseBlurring(false)
            }
            if (y > scrollOffsetToShowNav) {
                setNavTitle(LocaleController.getString("Create Backup"))
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
                toWordsButton,
                32.dp +
                    max(
                        (navigationController?.getSystemBars()?.bottom ?: 0),
                        (window?.imeInsets?.bottom ?: 0)
                    )
            )
        }
    }

    override fun updateTheme() {
        scrollingContentView.setBackgroundColor(WColor.SecondaryBackground.color)
    }

}
