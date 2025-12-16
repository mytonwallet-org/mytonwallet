package org.mytonwallet.app_air.uitonconnect.viewControllers.signed

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView.ScaleType
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class SignedVC(context: Context) : WViewController(context) {
    override val TAG = "Signed"

    override val isBackAllowed: Boolean = false

    private val continueButton by lazy {
        WButton(context).apply {
            id = View.generateViewId()
        }.apply {
            text = LocaleController.getString("Close")
            setOnClickListener {
                window?.dismissLastNav()
            }
        }
    }

    override fun setupViews() {
        super.setupViews()

        title = LocaleController.getString("Data Signed!")
        setupNavBar(true)
        navigationBar?.addCloseButton()

        val animationView = WAnimationView(context).apply {
            alpha = 0f
            scaleType = ScaleType.FIT_CENTER
            layoutParams =
                LayoutParams(124.dp, 124.dp)
        }
        animationView.play(R.raw.animation_thumb, onStart = {
            animationView.fadeIn()
        })
        view.addView(animationView)
        view.addView(continueButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            topToBottom(animationView, navigationBar!!, 16f)
            toCenterX(animationView)
            toCenterX(continueButton, 20f)
            toBottomPx(
                continueButton, 20.dp +
                    (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }
}
