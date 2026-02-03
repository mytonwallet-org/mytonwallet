package org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout
import me.vkryl.core.random
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.drawable.MotionBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.resetAccounts
import org.mytonwallet.app_air.walletcore.stores.AuthCooldownError
import org.mytonwallet.app_air.walletcore.stores.AuthStore

@SuppressLint("ViewConstructor")
class PasscodeConfirmVC(
    context: Context,
    private val passcodeViewState: PasscodeViewState,
    private val task: (passcode: String) -> Unit,
    private val allowedToCancel: Boolean = true,
    private val ignoreBiometry: Boolean = false,
) : WViewController(context), PasscodeScreenView.Delegate {
    override val TAG = "PasscodeConfirm"

    override val protectFromScreenRecord = true

    private var isDoingTask = false

    override val isLockedScreen: Boolean
        get() = !allowedToCancel

    override val isBackAllowed: Boolean
        get() = !isDoingTask

    override val isSwipeBackAllowed: Boolean
        get() = !isDoingTask

    var isTaskAsync = true
    var customPasscodeVerifier: ((String) -> Boolean)? = null
    var onWrongInput: ((() -> Unit)?) = null

    override val shouldDisplayBottomBar =
        (passcodeViewState as? PasscodeViewState.Default)?.showMotionBackgroundDrawable != true

    private val bgDrawable = MotionBackgroundDrawable().apply {
        phase = random(0, 7)
    }

    private val passcodeScreenView: PasscodeScreenView by lazy {
        val v = PasscodeScreenView(this, passcodeViewState, ignoreBiometry)
        v.id = View.generateViewId()
        if (passcodeViewState is PasscodeViewState.CustomHeader) {
            v.topLinearLayout.addView(
                passcodeViewState.headerView, 0,
                ConstraintLayout.LayoutParams(MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            )
        }
        v.delegate = this
        v
    }

    private val shouldShowNav = passcodeViewState is PasscodeViewState.CustomHeader ||
        (passcodeViewState is PasscodeViewState.Default && passcodeViewState.showNavBar)

    override fun setupViews() {
        super.setupViews()

        if ((passcodeViewState is PasscodeViewState.CustomHeader && passcodeViewState.showNavbarTitle)
            || passcodeViewState is PasscodeViewState.Default
        ) {
            setNavTitle(passcodeViewState.navbarTitle ?: "")
        }
        if (shouldShowNav)
            setupNavBar(true)

        if ((navigationController?.viewControllers?.size ?: 0) < 2)
            navigationBar?.addCloseButton()

        view.addView(passcodeScreenView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.setConstraints {
            toTopPx(
                passcodeScreenView, (navigationController?.getSystemBars()?.top ?: 0) +
                    (if (shouldShowNav) WNavigationBar.DEFAULT_HEIGHT.dp else 0)
            )
            toBottom(passcodeScreenView)
        }
        updateTheme()

        if (passcodeViewState is PasscodeViewState.Default) {
            if (passcodeViewState.showMotionBackgroundDrawable) {
                passcodeScreenView.doOnNumPadClick = {
                    bgDrawable.switchToNextPosition(true)
                }
            }
        }
    }

    override fun didSetupViews() {
        bottomReversedCornerView?.pauseBlurring()
    }

    override fun updateTheme() {
        super.updateTheme()
        if (passcodeViewState is PasscodeViewState.Default && passcodeViewState.showMotionBackgroundDrawable) {
            val colors = MotionBackgroundDrawable.generateColorVariations(WColor.Tint.color)
            view.background = bgDrawable
            bgDrawable.setColors(WColor.Tint.color, colors[0], colors[1], colors[2])
        } else {
            view.setBackgroundColor(WColor.SecondaryBackground.color)
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        if (passcodeViewState !is PasscodeViewState.Default || !passcodeViewState.showMotionBackgroundDrawable) {
            passcodeScreenView.setPadding(
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0,
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                if (passcodeViewState is PasscodeViewState.CustomHeader) 48.dp else 0
            )
        }
    }

    override fun viewWillAppear() {
        super.viewWillAppear()

        val startWithBiometrics =
            (passcodeViewState as? PasscodeViewState.Default)?.startWithBiometrics
                ?: (passcodeViewState as? PasscodeViewState.CustomHeader)?.startWithBiometrics
                ?: false;

        if (window?.isPaused == true ||
            !startWithBiometrics ||
            !passcodeScreenView.allowBiometry ||
            ignoreBiometry ||
            AuthStore.getCooldownDate() > System.currentTimeMillis()
        ) {
            passcodeScreenView.inBiometry.animatedValue = false
        } else {
            if (!isDoingTask)
                passcodeScreenView.tryBiometrics()
        }

        passcodeScreenView.setupCooldown(AuthStore.getCooldownDate())
    }

    override fun onDestroy() {
        super.onDestroy()
        passcodeScreenView.clearCooldown()
    }

    override fun onBackPressed(): Boolean {
        if (isDoingTask)
            return false // prevent back button action
        return super.onBackPressed()
    }

    override fun onEnterPasscode(
        passcode: String,
        callback: (wasCorrect: Boolean, cooldownDate: Long?) -> Unit
    ) {
        fun onPasscodeVerified() {
            view.lockView()
            isDoingTask = true
            Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "onPasscodeVerified: Running task")
            task(passcode)
            if (isTaskAsync && passcodeViewState !is PasscodeViewState.Default) {
                navigationBar?.fadeOutActions()
                passcodeScreenView.showIndicator()
            }
        }
        if (customPasscodeVerifier != null) {
            val isCorrect = customPasscodeVerifier!!(passcode)
            callback(isCorrect, null)
            if (isCorrect) {
                onPasscodeVerified()
            } else {
                onWrongInput?.invoke()
            }
        } else {
            if ((passcodeViewState as? PasscodeViewState.Default)?.isUnlockScreen == true) {
                if (!WalletCore.isBridgeReady) {
                    passcodeScreenView.showIndicator(animateToGreen = false)
                }
            }
            WalletCore.doOnBridgeReady {
                try {
                    AuthStore.verifyPassword(passcode) { success, cooldownDate ->
                        callback(success, cooldownDate)
                        if (success) {
                            onPasscodeVerified()
                        } else {
                            onWrongInput?.invoke()
                        }
                    }
                } catch (e: AuthCooldownError) {
                    callback(false, e.cooldownDate)
                }
            }
        }
    }

    override fun signOutPressed() {
        super.signOutPressed()
        showAlert(
            LocaleController.getString("Sign Out"),
            LocaleController.getString("\$logout_warning")
                .toProcessedSpannableStringBuilder(),
            LocaleController.getString("Sign Out"),
            buttonPressed = {
                view.lockView()
                WalletCore.resetAccounts { ok, err ->
                    if (ok != true || err != null) {
                        view.unlockView()
                        showError(err)
                    }
                    Logger.d(Logger.LogTag.ACCOUNT, "signOutPressed: Resetting accounts")
                    WGlobalStorage.deleteAllWallets()
                    WSecureStorage.deleteAllWalletValues()
                    WalletContextManager.delegate?.restartApp()
                }
            },
            LocaleController.getString("Cancel"),
            primaryIsDanger = true
        )
    }

    fun restartAuth() {
        isDoingTask = false
        view.unlockView()
        passcodeScreenView.clearPasscode()
        if (isTaskAsync)
            navigationBar?.fadeInActions()
    }
}
