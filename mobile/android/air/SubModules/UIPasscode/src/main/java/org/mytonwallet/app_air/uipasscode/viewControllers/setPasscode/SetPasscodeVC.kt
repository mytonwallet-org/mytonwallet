package org.mytonwallet.app_air.uipasscode.viewControllers.setPasscode

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderAndActionsView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.fadeInObjectAnimator
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.shakeView
import org.mytonwallet.app_air.uipasscode.commonViews.PasscodeInputView
import org.mytonwallet.app_air.uipasscode.viewControllers.activateBiometric.ActivateBiometricVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import java.lang.ref.WeakReference
import kotlin.math.max

const val is6DigitPassSupported = false

@SuppressLint("ViewConstructor")
class SetPasscodeVC(
    context: Context,
    private val askToActivateBiometrics: Boolean,
    private val confirmingPasscode: String?,
    private val onCompletion: (passcode: String, isBiometricRequested: Boolean) -> Unit
) : WViewController(context), PasscodeInputView.Delegate {
    override val TAG = "SetPasscode"

    override val shouldDisplayTopBar = false

    override val isSwipeBackAllowed: Boolean = confirmingPasscode != null
    private var confirmedPasscode = false

    private val headerView: HeaderAndActionsView by lazy {
        val v = HeaderAndActionsView(
            context,
            HeaderAndActionsView.Media.Animation(
                animation = R.raw.animation_guard,
                repeat = true
            ),
            title = LocaleController.getString("The wallet is ready"),
            subtitle = LocaleController.getString(if (confirmingPasscode == null) "Create a code to protect it" else "Enter your code again"),
            onStarted = {
                passcodeInputView.fadeInObjectAnimator()?.start()
                switchLengthButton.fadeInObjectAnimator()?.start()
            },
            textsGap = 13f
        )
        v
    }

    private val passcodeInputView: PasscodeInputView by lazy {
        val v = PasscodeInputView(context, WeakReference(this), showKeyboardOnFocus = true)
        if (confirmingPasscode != null)
            v.passLength = confirmingPasscode.length
        v.alpha = 0f
        v.setOnClickListener {
            v.requestFocus()
        }
        v
    }

    private val switchLengthButton: WButton by lazy {
        val v = WButton(context, WButton.Type.SECONDARY)
        v.text =
            LocaleController.getString("Use 6-digit Passcode")
        v.alpha = 0f
        v.setOnClickListener {
            passcodeInputView.passcode = ""
            if (passcodeInputView.passLength == 4) {
                passcodeInputView.passLength = 6
                v.text =
                    LocaleController.getString("Use 4-digit Passcode")
            } else {
                passcodeInputView.passLength = 4
                v.text =
                    LocaleController.getString("Use 6-digit Passcode")
            }
        }
        v
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(headerView)
        view.addView(passcodeInputView)
        if (is6DigitPassSupported && confirmingPasscode == null)
            view.addView(switchLengthButton)

        view.setConstraints {
            toTopPx(
                headerView,
                WNavigationBar.DEFAULT_HEIGHT.dp +
                    (navigationController?.getSystemBars()?.top ?: 0)
            )
            toCenterX(headerView)
            topToBottom(passcodeInputView, headerView, 38f)
            toCenterX(passcodeInputView)
            if (is6DigitPassSupported && confirmingPasscode == null) {
                toBottomPx(
                    switchLengthButton, 16.dp + max(
                        (window?.imeInsets?.bottom ?: 0),
                        (navigationController?.getSystemBars()?.bottom ?: 0)
                    )
                )
                toCenterX(switchLengthButton)
            }
        }

        if (confirmingPasscode != null) {
            setupNavBar(true)
            setTopBlur(false, false)
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.Background.color)
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        passcodeInputView.post {
            passcodeInputView.requestFocus()
            // Workaround to make sure `passcodeInputView` appears when resume from background
            passcodeInputView.postDelayed({
                passcodeInputView.requestFocus()
            }, 500)
        }
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        // Workaround to make sure variables are updated after pop
        insetsUpdated()
    }

    private var insetsUpdatedBefore = false
    private var wasShowingKeyboard = false
    override fun insetsUpdated() {
        super.insetsUpdated()
        view.constraintSet().apply {
            toBottomPx(
                switchLengthButton,
                16.dp + max(
                    (window?.imeInsets?.bottom ?: 0),
                    (navigationController?.getSystemBars()?.bottom ?: 0)
                )
            )
        }.layoutAnimated(AnimationConstants.VERY_QUICK_ANIMATION)
        // Handle keyboard close event
        if (
            navigationController?.viewControllers?.lastOrNull() == this &&
            insetsUpdatedBefore &&
            (window?.imeInsets?.bottom ?: 0) == 0
        ) {
            if (!confirmedPasscode) {
                if (wasShowingKeyboard)
                    pop()
                else
                    passcodeInputView.requestFocus()
            }
        }
        wasShowingKeyboard = isKeyboardOpen
        insetsUpdatedBefore = true
    }

    override fun didChangePasscode(passcode: String) {
        //headerView.toggle(passcode.isNotEmpty())
    }

    override fun didEnterPasscode(passcode: String) {
        if (confirmingPasscode == null) {
            push(SetPasscodeVC(context, askToActivateBiometrics, passcode, onCompletion)) {
                passcodeInputView.passcode = ""
                headerView.toggle(false)
            }
        } else {
            if (passcode == confirmingPasscode) {
                confirmedPasscode = true
                Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "didEnterPasscode: Passcode confirmed successfully")
                passcodeInputView.showIndicator(true)
                fun finalize(isBiometricsActivated: Boolean) {
                    Logger.d(Logger.LogTag.PASSCODE_CONFIRM, "finalize: isBiometricsActivated=$isBiometricsActivated")
                    view.lockView()
                    view.hideKeyboard()
                    onCompletion(confirmingPasscode, isBiometricsActivated)
                }
                if (askToActivateBiometrics && BiometricHelpers.canAuthenticate(context)) {
                    view.hideKeyboard()
                    push(
                        ActivateBiometricVC(
                            context,
                            onCompletion = { isBiometricsActivated ->
                                finalize(isBiometricsActivated)
                            }),
                        onCompletion = {
                            // Pushed ActivateBiometricVC, Now remove confirming passcode from the navigation stack
                            navigationController?.removePrevViewControllerOnly()
                        }
                    )
                } else {
                    finalize(false)
                }
            } else {
                wrongPasscode()
            }
        }
    }

    private fun wrongPasscode() {
        view.lockView()
        passcodeInputView.shakeView()
        Handler(Looper.getMainLooper()).postDelayed({
            pop()
        }, 500)
    }

    override fun onBackPressed(): Boolean {
        // Should not go back or accidentally close the app, from set passcode vc :)
        if (confirmingPasscode == null)
            return true
        return super.onBackPressed()
    }

    override fun viewWillDisappear() {
        // Override to prevent keyboard from being dismissed!
    }

}
