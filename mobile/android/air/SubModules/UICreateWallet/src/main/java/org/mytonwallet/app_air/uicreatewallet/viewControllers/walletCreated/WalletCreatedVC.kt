package org.mytonwallet.app_air.uicreatewallet.viewControllers.walletCreated

import android.annotation.SuppressLint
import android.content.Context
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderAndActionsView
import org.mytonwallet.app_air.uicreatewallet.viewControllers.wordDisplay.WordDisplayVC
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color

@SuppressLint("ViewConstructor")
class WalletCreatedVC(
    context: Context,
    private val words: Array<String>,
    private val isFirstWallet: Boolean,
    // Used when adding new account (not first account!)
    private val passedPasscode: String?
) :
    WViewController(context) {

    override val shouldDisplayTopBar = false

    override var isSwipeBackAllowed = false

    private val centerView: HeaderAndActionsView by lazy {
        val v = HeaderAndActionsView(
            context,
            R.raw.animation_congrats,
            null,
            false,
            LocaleController.getString("Congratulations!"),
            LocaleController.getString("The wallet is ready") + ".",
            LocaleController.getString("Proceed"),
            LocaleController.getString("Cancel"),
            primaryActionPressed = {
                push(WordDisplayVC(context, words, isFirstWallet, passedPasscode))
            },
            secondaryActionPressed = {
                pop()
            }
        )
        v
    }

    override fun setupViews() {
        super.setupViews()

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

    override fun viewWillDisappear() {
        super.viewWillDisappear()
    }
}
