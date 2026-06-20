package org.mytonwallet.app_air.uisettings.viewControllers.mfa

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderAndActionsView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class MfaInstalledVC(context: Context) : WViewController(context) {
    override val TAG = "MfaInstalled"

    override val shouldDisplayTopBar = false

    private val headerView: HeaderAndActionsView by lazy {
        HeaderAndActionsView(
            context,
            HeaderAndActionsView.Media.Animation(
                animation = R.raw.animation_happy,
                repeat = true,
            ),
            mediaSize = 160.dp,
            title = LocaleController.getString("All Set!"),
            subtitle = LocaleController.getString(
                "Telegram will be used to confirm transfers and important actions.",
            ),
            onStarted = { animationStarted() },
        ).apply { alpha = 0f }
    }

    private val doneButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Done")
        setOnClickListener { pop() }
        alpha = 0f
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(headerView)
        view.addView(doneButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            toTopPx(headerView, 80.dp + (navigationController?.getSystemBars()?.top ?: 0))
            toCenterX(headerView)
            toBottomPx(
                doneButton,
                32.dp + (navigationController?.getSystemBars()?.bottom ?: 0),
            )
            toStartPx(doneButton, 32.dp + systemBarStartInset)
            toEndPx(doneButton, 32.dp + systemBarEndInset)
        }

        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setConstraints {
            toTopPx(headerView, 80.dp + (navigationController?.getSystemBars()?.top ?: 0))
            toBottomPx(
                doneButton,
                32.dp + (navigationController?.getSystemBars()?.bottom ?: 0),
            )
            toStartPx(doneButton, 32.dp + systemBarStartInset)
            toEndPx(doneButton, 32.dp + systemBarEndInset)
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.Background.color)
    }

    private fun animationStarted() {
        headerView.fadeIn()
        doneButton.fadeIn()
    }
}
