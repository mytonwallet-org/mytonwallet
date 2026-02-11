package org.mytonwallet.app_air.uisettings.viewControllers.security

import android.content.Context
import android.os.Build
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.generateViewId
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WEditableItemView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uisettings.viewControllers.RecoveryPhraseVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.AutoLockHelper
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.models.MAutoLockOption
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class SecurityVC(context: Context, private var currentPasscode: String) : WViewController(context) {
    override val TAG = "Security"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayBottomBar = true

    private val separatorBackgroundDrawable = SeparatorBackgroundDrawable().apply {
        backgroundWColor = WColor.Background
        offsetStart = 20f.dp
        offsetEnd = 20f.dp
        forceSeparator = true
    }

    private val backupTitleLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("\$back_up_security"),
            titleColor = WColor.Tint,
            HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val backupRow = KeyValueRowView(
        context,
        LocaleController.getString("Show Recovery Phrase"),
        "",
        KeyValueRowView.Mode.PRIMARY,
        isLast = true,
    ).apply {
        setOnClickListener {
            WalletCore.call(
                ApiMethod.Settings.FetchMnemonic(
                    AccountStore.activeAccountId!!,
                    currentPasscode
                ), callback = { words, err ->
                    if (words == null || err != null) {
                        return@call
                    }
                    navigationController?.push(
                        RecoveryPhraseVC(context, displayedAccount.network, words)
                    )
                })
        }
    }

    private val spacer1: WBaseView by lazy {
        val v = WBaseView(context)
        v
    }

    private val passcodeTitleLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("Passcode"),
            titleColor = WColor.Tint,
            HeaderCell.TopRounding.NORMAL
        )
    }

    private val biometricLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.text = LocaleController.getString("Biometric Authentication")
        lbl
    }

    private val biometricSwitch: WSwitch by lazy {
        val switchView = WSwitch(context)
        switchView.isChecked = WGlobalStorage.isBiometricActivated()
        switchView.setOnCheckedChangeListener { _, isChecked ->
            WGlobalStorage.setIsBiometricActivated(isChecked)
            if (isChecked) {
                WSecureStorage.setBiometricPasscode(window!!, currentPasscode)
            } else {
                WSecureStorage.deleteBiometricPasscode(window!!)
            }
        }
        switchView
    }

    private val biometricAuthRow: WView by lazy {
        val v = WView(context)
        v.addView(biometricLabel)
        v.addView(biometricSwitch)
        v.setConstraints {
            toStart(biometricLabel, 20f)
            toCenterY(biometricLabel)
            toEnd(biometricSwitch, 20f)
            toCenterY(biometricSwitch)
        }
        v.setOnClickListener {
            biometricSwitch.isChecked = !biometricSwitch.isChecked
        }
        v.isGone = !BiometricHelpers.canAuthenticate(context)
        v
    }

    private val changePasscodeRow =
        KeyValueRowView(
            context,
            LocaleController.getString("Change Passcode"),
            "",
            KeyValueRowView.Mode.PRIMARY,
            isLast = true,
        ).apply {
            setOnClickListener {
                changePasscodePressed()
            }
        }

    private val spacer2 = WBaseView(context)

    private val appLockLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("App Lock"),
            titleColor = WColor.Tint,
            HeaderCell.TopRounding.NORMAL
        )
    }

    private val lockTimeView = WEditableItemView(context).apply {
        id = generateViewId()
        drawable = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18
        )
        setText(WGlobalStorage.getAppLock().displayName)
    }

    private val autoLockRow =
        KeyValueRowView(
            context,
            LocaleController.getString("Lock the app after"),
            "",
            KeyValueRowView.Mode.PRIMARY,
            isLast = true,
        ).apply {
            setValueView(lockTimeView)
            setOnClickListener {
                WMenuPopup.present(
                    lockTimeView,
                    listOf(
                        MAutoLockOption.NEVER,
                        MAutoLockOption.THIRTY_SECONDS,
                        MAutoLockOption.THREE_MINUTES,
                        MAutoLockOption.TEN_MINUTES
                    ).map {
                        WMenuPopup.Item(
                            null,
                            it.displayName,
                            false
                        ) {
                            WGlobalStorage.setAutoLock(it)
                            lockTimeView.setText(it.displayName)
                            AutoLockHelper.start(it.period)
                        }
                    },
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.BELOW,
                    windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                        lockTimeView,
                        roundRadius = 40f.dp
                    )
                )
            }
        }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        if (AccountStore.activeAccount?.accountType == MAccount.AccountType.MNEMONIC) {
            v.addView(backupTitleLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            v.addView(backupRow)
            v.addView(spacer1, ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
        }
        v.addView(passcodeTitleLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(biometricAuthRow, ConstraintLayout.LayoutParams(MATCH_PARENT, 50.dp))
        v.addView(changePasscodeRow)
        v.addView(spacer2, ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
        v.addView(appLockLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(autoLockRow, ConstraintLayout.LayoutParams(MATCH_PARENT, 50.dp))
        v.setConstraints {
            if (AccountStore.activeAccount?.isViewOnly != true) {
                toTop(backupTitleLabel)
                topToBottom(backupRow, backupTitleLabel)
                toCenterX(backupRow)
                topToBottom(spacer1, backupRow)
                topToBottom(passcodeTitleLabel, spacer1)
            } else {
                toTop(passcodeTitleLabel)
            }
            topToBottom(biometricAuthRow, passcodeTitleLabel)
            topToBottom(changePasscodeRow, biometricAuthRow)
            topToBottom(spacer2, changePasscodeRow)
            topToBottom(appLockLabel, spacer2)
            topToBottom(autoLockRow, appLockLabel)
            toBottomPx(autoLockRow, (navigationController?.getSystemBars()?.bottom ?: 0))
        }
        v
    }

    private val scrollView: ScrollView by lazy {
        ScrollView(context).apply {
            id = generateViewId()
            isVerticalScrollBarEnabled = false
            addView(scrollingContentView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setOnScrollChangeListener { _, _, scrollY, _, _ ->
                    updateBlurViews(scrollView = this, computedOffset = scrollY)
                }
            }
            overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
        }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Security"))
        setupNavBar(true)

        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.setConstraints {
            topToBottom(scrollView, navigationBar!!)
            toCenterX(scrollView)
            toBottom(scrollView)
        }

        updateTheme()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        updateBlurViews(scrollView, 0)
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
        if (AccountStore.activeAccount?.isViewOnly != true) {
            backupTitleLabel.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.TOOLBAR_RADIUS.dp,
                0f,
            )
            backupRow.setBackgroundColor(WColor.Background.color)
            passcodeTitleLabel.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp,
                0f,
            )
        } else {
            passcodeTitleLabel.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.TOOLBAR_RADIUS.dp,
                0f,
            )
        }
        biometricAuthRow.background = separatorBackgroundDrawable
        biometricAuthRow.addRippleEffect(WColor.SecondaryBackground.color)
        biometricLabel.setTextColor(WColor.PrimaryText.color)
        changePasscodeRow.setBackgroundColor(WColor.Background.color)
        appLockLabel.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f,
        )
        autoLockRow.setBackgroundColor(WColor.Background.color)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            scrollView.setOnScrollChangeListener(null)
        }
        biometricAuthRow.setOnClickListener(null)
    }

    private fun changePasscodePressed() {
        lateinit var changePasscodeVC: PasscodeConfirmVC
        changePasscodeVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.Default(
                LocaleController.getString("Change Passcode"),
                "",
                LocaleController.getString("Change Passcode"),
                showNavigationSeparator = false,
                startWithBiometrics = false
            ),
            task = { newPasscode ->
                confirmNewPasscode(changePasscodeVC, newPasscode)
            },
            ignoreBiometry = true
        ).apply {
            customPasscodeVerifier = {
                // Accept any passcode
                true
            }
            isTaskAsync = false
        }

        navigationController?.push(changePasscodeVC)
    }

    private fun confirmNewPasscode(changePasscodeVC: PasscodeConfirmVC, newPasscode: String) {
        val confirmPasscodeVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.Default(
                LocaleController.getString("Re-enter your new code"),
                "",
                LocaleController.getString("Confirm Passcode"),
                showNavigationSeparator = false,
                startWithBiometrics = false
            ), task = { _ ->
                WalletCore.call(
                    ApiMethod.Settings.ChangePassword(
                        currentPasscode,
                        newPasscode,
                    )
                ) { _, err ->
                    if (err != null)
                        return@call
                    if (WGlobalStorage.isBiometricActivated())
                        WSecureStorage.setBiometricPasscode(window!!, newPasscode)
                    currentPasscode = newPasscode
                    navigationController?.removePrevViewControllers(2)
                    navigationController?.pop(true)
                }
            },
            ignoreBiometry = true
        ).apply {
            customPasscodeVerifier = {
                // Verify new passcode
                it == newPasscode
            }
            onWrongInput = {
                navigationController?.pop(true)
            }
            isTaskAsync = false
        }
        navigationController?.push(confirmPasscodeVC, onCompletion = {
            changePasscodeVC.restartAuth()
        })
    }
}
