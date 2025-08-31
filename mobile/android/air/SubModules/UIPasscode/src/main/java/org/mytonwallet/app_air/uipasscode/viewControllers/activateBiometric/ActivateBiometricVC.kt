package org.mytonwallet.app_air.uipasscode.viewControllers.activateBiometric

import android.annotation.SuppressLint
import android.content.Context
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderAndActionsView
import org.mytonwallet.app_air.uipasscode.R
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MBridgeError

@SuppressLint("ViewConstructor")
class ActivateBiometricVC(context: Context, onCompletion: (activated: Boolean) -> Unit) :
    WViewController(context) {

    override val shouldDisplayTopBar = false

    private val centerView: HeaderAndActionsView by lazy {
        val v = HeaderAndActionsView(
            context,
            null,
            R.drawable.ic_fingerprint,
            false,
            LocaleController.getString("Use Biometrics?"),
            LocaleController.getString("To avoid entering the passcode every time, you can use biometrics."),
            LocaleController.getString("Use Biometrics"),
            LocaleController.getString("Skip"),
            primaryActionPressed = {
                BiometricHelpers.authenticate(
                    window!!,
                    LocaleController.getString("Use Biometrics?"),
                    subtitle = null,
                    description = null,
                    cancel = null,
                    onSuccess = {
                        centerView.primaryActionButton.isLoading = true
                        view.lockView()
                        onCompletion(true)
                    },
                    onCanceled = {}
                )
            },
            secondaryActionPressed = {
                centerView.secondaryActionButton.isLoading = true
                view.lockView()
                onCompletion(false)
            }
        )
        v
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)
        setTopBlur(visible = false, animated = false)

        // Add center view
        view.addView(centerView)

        // Apply constraints to center the view
        view.setConstraints {
            allEdges(centerView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.Background.color)
    }

    override fun showError(error: MBridgeError?) {
        super.showError(error)
        centerView.primaryActionButton.isLoading = false
        centerView.secondaryActionButton.isLoading = false
        view.unlockView()
    }
}
