package org.mytonwallet.app_air.uisettings.viewControllers.security

import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.generateViewId
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import me.vkryl.android.AnimatorUtils
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SwitchCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WEditableItemView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uisettings.viewControllers.RecoveryPhraseVC
import org.mytonwallet.app_air.uisettings.viewControllers.mfa.MfaVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.uicomponents.helpers.spans.ChainBadgeSpan
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.AutoLockHelper
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.models.MAutoLockOption
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference

private fun buildMfaRowTitle(): CharSequence {
    val title = LocaleController.getString("2FA with Telegram")
    return android.text.SpannableStringBuilder(title).apply {
        append("  ")
        val start = length
        append("TON")
        setSpan(
            ChainBadgeSpan(
                text = "TON",
                textColorInt = WColor.SecondaryText.color,
                backgroundColorInt = WColor.SecondaryBackground.color,
            ),
            start,
            length,
            android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
        )
    }
}

class SecurityVC(context: Context, private var currentPasscode: String) : WViewController(context) {
    override val TAG = "Security"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayBottomBar = true

    private val shouldShowMfa: Boolean
        get() {
            val account = AccountStore.activeAccount ?: return false
            if (!account.isChainSupported(org.mytonwallet.app_air.walletcore.TON_CHAIN) ||
                account.isViewOnly ||
                account.accountType != MAccount.AccountType.MNEMONIC ||
                !AccountStore.isCurrentVersionW5
            ) {
                return false
            }
            return WGlobalStorage.getAccountConfigIsMfaEnabled(account.accountId) ||
                account.byChain[org.mytonwallet.app_air.walletcore.TON_CHAIN]?.mfa != null
        }

    private val backupRow = SettingsItemCell(context).apply {
        configure(
            SettingsItem(
                identifier = SettingsItem.Identifier.NONE,
                icon = org.mytonwallet.app_air.uisettings.R.drawable.ic_export,
                title = LocaleController.getString("Back Up & Export"),
                value = null,
                hasTintColor = false,
            ),
            subtitle = null,
            isFirst = true,
            isLast = true,
            isEnabled = true,
            onTap = {
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
        )
    }

    private val spacer1: WBaseView by lazy {
        val v = WBaseView(context)
        v
    }

    private val biometricAuthRow: SwitchCell by lazy {
        SwitchCell(
            context,
            title = LocaleController.getString("Biometric Authentication"),
            isChecked = WGlobalStorage.isBiometricActivated(),
            isFirst = true,
            isLast = false,
            leadingIconRes = org.mytonwallet.app_air.uisettings.R.drawable.ic_biometric_auth,
            onChange = { isChecked ->
                if (WGlobalStorage.isBiometricActivated() == isChecked) return@SwitchCell
                if (isChecked) {
                    val activated = WSecureStorage.setBiometricPasscode(window!!, currentPasscode)
                    WGlobalStorage.setIsBiometricActivated(activated)
                    if (!activated) biometricAuthRow.isChecked = false
                } else {
                    WSecureStorage.deleteBiometricPasscode(window!!)
                    WGlobalStorage.setIsBiometricActivated(false)
                }
            }
        ).apply {
            isGone = !BiometricHelpers.canAuthenticate(context)
        }
    }

    private val changePasscodeRow =
        KeyValueRowView(
            context,
            LocaleController.getString("Change Passcode"),
            "",
            KeyValueRowView.Mode.LINK,
            isLast = true,
        ).apply {
            if (biometricAuthRow.isGone)
                setTopRadius(ViewConstants.BLOCK_RADIUS.dp)
            setOnClickListener {
                changePasscodePressed()
            }
        }

    private val changePasscodeFooterLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            text = LocaleController.getString("The passcode will be changed for all your wallets.")
            gravity = android.view.Gravity.START
            setTextColor(WColor.SecondaryText)
        }
    }

    private val spacer2 = WBaseView(context)

    private val mfaRow: SettingsItemCell by lazy {
        SettingsItemCell(context).apply {
            configure(
                SettingsItem(
                    identifier = SettingsItem.Identifier.MFA,
                    icon = org.mytonwallet.app_air.uisettings.R.drawable.ic_mfa,
                    title = buildMfaRowTitle(),
                    value = null,
                    hasTintColor = false,
                ),
                subtitle = null,
                isFirst = true,
                isLast = true,
                isEnabled = true,
                onTap = {
                    navigationController?.push(MfaVC(context))
                }
            )
        }
    }

    private val mfaFooterLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            text = LocaleController.getString("Approve sign-in in Telegram as a second step.")
            gravity = android.view.Gravity.START
            setTextColor(WColor.SecondaryText)
        }
    }

    private val mfaSpacer: WBaseView by lazy { WBaseView(context) }

    private val allowAppLockRow: SwitchCell by lazy {
        SwitchCell(
            context,
            title = LocaleController.getString("Allow App Lock"),
            isChecked = WGlobalStorage.isAppLockEnabled(),
            isFirst = false,
            isLast = false,
            onChange = { isChecked ->
                WGlobalStorage.setIsAppLockEnabled(isChecked)
                if (isChecked) {
                    AutoLockHelper.start(WGlobalStorage.getAppLock().period)
                } else {
                    AutoLockHelper.stop()
                }
                animateAutoLockRow(visible = isChecked)
            }
        )
    }

    private val lockTimeView = WEditableItemView(context).apply {
        id = generateViewId()
        drawable = context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18)
        setText(WGlobalStorage.getAppLock().displayName)
    }

    private val autoLockRow =
        KeyValueRowView(
            context,
            LocaleController.getString("Lock the app after"),
            "",
            KeyValueRowView.Mode.PRIMARY,
            isLast = false,
        ).apply {
            isGone = !WGlobalStorage.isAppLockEnabled()
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

    private val appLockContainerView: WView by lazy {
        WView(context).apply {
            id = generateViewId()
            addView(
                allowAppLockRow,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            addView(
                autoLockRow,
                ConstraintLayout.LayoutParams(MATCH_PARENT, 50.dp)
            )
            setConstraints {
                toTop(allowAppLockRow)
                toCenterX(allowAppLockRow)
                topToBottom(autoLockRow, allowAppLockRow)
                toCenterX(autoLockRow)
            }
            clipToOutline = true
            clipChildren = true
        }
    }

    private val appLockFooterLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            text = LocaleController.getString("\$app_lock_description")
                .replace(
                    "%app_name%",
                    context.getString(org.mytonwallet.app_air.walletbasecontext.R.string.app_name)
                )
            gravity = android.view.Gravity.START
            setTextColor(WColor.SecondaryText)
        }
    }

    private val spacer3 = WBaseView(context)

    private val disableScreenRecordWarningRow = SwitchCell(
        context,
        title = LocaleController.getString("Disable Screen Record Warning"),
        isChecked = WGlobalStorage.getIsScreenRecordWarningDisabled(),
        isFirst = true,
        isLast = true,
        onChange = { isChecked ->
            WGlobalStorage.setIsScreenRecordWarningDisabled(isChecked)
        }
    )

    private val spacer4 = WBaseView(context)

    private val allowSuspiciousActionsRow = SwitchCell(
        context,
        title = LocaleController.getString("Allow Suspicious Actions"),
        isChecked = AccountStore.activeAccountId?.let {
            WGlobalStorage.getIsAllowSuspiciousActions(it)
        } ?: false,
        isFirst = true,
        isLast = true,
        onChange = { isChecked ->
            AccountStore.activeAccountId?.let {
                WGlobalStorage.setIsAllowSuspiciousActions(it, isChecked)
            }
        }
    )

    private val allowSuspiciousActionsFooterLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            text = LocaleController.getString("\$allow_suspicious_actions_description")
            gravity = android.view.Gravity.START
            setTextColor(WColor.SecondaryText)
        }
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        if (AccountStore.activeAccount?.accountType == MAccount.AccountType.MNEMONIC) {
            v.addView(backupRow)
            v.addView(spacer1, ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
        }
        v.addView(biometricAuthRow, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(changePasscodeRow)
        v.addView(changePasscodeFooterLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(spacer2, ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
        if (shouldShowMfa) {
            v.addView(mfaRow, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            v.addView(mfaFooterLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            v.addView(mfaSpacer, ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
        }
        v.addView(appLockContainerView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(appLockFooterLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(spacer3, ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
        v.addView(allowSuspiciousActionsRow, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(allowSuspiciousActionsFooterLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(spacer4, ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
        v.addView(disableScreenRecordWarningRow)
        v.setConstraints {
            if (AccountStore.activeAccount?.isViewOnly != true) {
                toTop(backupRow)
                toCenterX(backupRow)
                topToBottom(spacer1, backupRow)
                topToBottom(biometricAuthRow, spacer1)
            } else {
                toTop(biometricAuthRow)
            }
            topToBottom(changePasscodeRow, biometricAuthRow)
            topToBottom(changePasscodeFooterLabel, changePasscodeRow, 8f)
            toCenterX(changePasscodeFooterLabel, 16f)
            topToBottom(spacer2, changePasscodeFooterLabel, 4f)
            if (shouldShowMfa) {
                topToBottom(mfaRow, spacer2)
                topToBottom(mfaFooterLabel, mfaRow, 8f)
                toCenterX(mfaFooterLabel, 16f)
                topToBottom(mfaSpacer, mfaFooterLabel, 4f)
                topToBottom(appLockContainerView, mfaSpacer)
            } else {
                topToBottom(appLockContainerView, spacer2)
            }
            toCenterX(appLockContainerView)
            topToBottom(appLockFooterLabel, appLockContainerView, 8f)
            toCenterX(appLockFooterLabel, 16f)
            topToBottom(spacer3, appLockFooterLabel, 4f)
            topToBottom(allowSuspiciousActionsRow, spacer3)
            toCenterX(allowSuspiciousActionsRow)
            topToBottom(allowSuspiciousActionsFooterLabel, allowSuspiciousActionsRow, 8f)
            toCenterX(allowSuspiciousActionsFooterLabel, 16f)
            topToBottom(spacer4, allowSuspiciousActionsFooterLabel, 4f)
            topToBottom(disableScreenRecordWarningRow, spacer4)
            toBottomPx(
                disableScreenRecordWarningRow,
                (navigationController?.bottomInset ?: 0)
            )
        }
        v
    }

    private val scrollView: WScrollView by lazy {
        WScrollView(WeakReference(this)).apply {
            addView(scrollingContentView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            onScrollStateChange = {
                updateBlurViews(scrollView = this)
            }
            setOnScrollChangeListener { _, _, _, _, _ ->
                updateBlurViews(scrollView = this)
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

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
        changePasscodeRow.setBackgroundColor(WColor.Background.color)
        autoLockRow.setBackgroundColor(WColor.Background.color, 0f, 0f)
        appLockContainerView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
        )
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollingContentView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        scrollView.setOnScrollChangeListener(null)
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
                    if (WGlobalStorage.isBiometricActivated()) {
                        val activated = WSecureStorage.setBiometricPasscode(window!!, newPasscode)
                        if (!activated)
                            WGlobalStorage.setIsBiometricActivated(false)
                    }
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

    private var autoLockHeightAnim: android.animation.ValueAnimator? = null

    private fun animateAutoLockRow(visible: Boolean) {
        autoLockHeightAnim?.cancel()
        autoLockHeightAnim = null

        val autoLockHeight = 50.dp
        val allowRowHeight = allowAppLockRow.height.takeIf { it > 0 } ?: autoLockHeight
        val expandedHeight = allowRowHeight + autoLockHeight

        autoLockRow.isGone = false

        if (!WGlobalStorage.getAreAnimationsActive()) {
            appLockContainerView.layoutParams.height =
                if (visible) expandedHeight else allowRowHeight
            appLockContainerView.requestLayout()
            return
        }

        val startHeight = appLockContainerView.height.takeIf { it > 0 } ?: allowRowHeight
        val targetHeight = if (visible) expandedHeight else allowRowHeight

        autoLockHeightAnim =
            android.animation.ValueAnimator.ofInt(startHeight, targetHeight).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                interpolator = AnimatorUtils.ACCELERATE_DECELERATE_INTERPOLATOR
                addUpdateListener { animator ->
                    appLockContainerView.updateLayoutParams {
                        height = animator.animatedValue as Int
                    }
                }
                addListener(object : android.animation.AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: android.animation.Animator) {
                        appLockContainerView.updateLayoutParams {
                            height = targetHeight
                        }
                        autoLockHeightAnim = null
                    }
                })
                start()
            }
    }
}
