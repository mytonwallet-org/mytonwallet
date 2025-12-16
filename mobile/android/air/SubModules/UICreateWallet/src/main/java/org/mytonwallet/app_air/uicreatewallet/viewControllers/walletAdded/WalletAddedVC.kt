package org.mytonwallet.app_air.uicreatewallet.viewControllers.walletAdded

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderAndActionsView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.ConfettiView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.uihome.tabs.TabsVC

class WalletAddedVC(context: Context, isNew: Boolean) : WViewController(context) {
    override val TAG = "WalletAdded"

    override val shouldDisplayTopBar = false

    val confettiView = ConfettiView(context).apply {
        id = View.generateViewId()
    }

    private val headerView: HeaderAndActionsView by lazy {
        val v = HeaderAndActionsView(
            context,
            HeaderAndActionsView.Media.Animation(
                animation = R.raw.animation_happy,
                repeat = true
            ),
            mediaSize = 160.dp,
            title = LocaleController.getString("All Set!"),
            subtitle = (
                (if (isNew)
                    LocaleController.getString("\$wallet_create_done")
                else
                    LocaleController.getPlural(1, "\$wallet_import_done")) +
                    "\n\n" +
                    LocaleController.getString("\$wallet_done_description")
                ).toProcessedSpannableStringBuilder(),
            onStarted = {
                animationStarted()
            }
        )
        v.alpha = 0f
        v
    }

    private val openWalletButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Open Wallet")
        setOnClickListener {
            val navigationController = WNavigationController(window!!)
            navigationController.setRoot(TabsVC(context))
            window!!.replace(navigationController, true)
        }
        alpha = 0f
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(confettiView)
        view.addView(headerView)
        view.addView(openWalletButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            allEdges(confettiView)
            toTopPx(headerView, 80.dp + (navigationController?.getSystemBars()?.top ?: 0))
            toCenterX(headerView)
            toBottomPx(
                openWalletButton,
                32.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
            toCenterX(openWalletButton, 32f)
        }
        view.post {
            confettiView.triggerConfetti()
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.Background.color)
    }

    private fun animationStarted() {
        headerView.fadeIn()
        openWalletButton.fadeIn()
    }
}
