package org.mytonwallet.app_air.uisettings.viewControllers.mintCard

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toBoldSpannableStringBuilder
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcore.stores.AccountStore

@SuppressLint("ViewConstructor")
class MintCardDoneVC(context: Context) : WViewController(context) {
    override val TAG = "MintCardDone"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false

    override val isBackAllowed = false
    override val isSwipeBackAllowed = false

    private val animationView = WAnimationView(context)

    private val resultLabel = WLabel(context).apply {
        setStyle(16f)
        gravity = Gravity.CENTER
        setTextColor(WColor.PrimaryText.color)
        text = LocaleController.getString("\$mint_card_result").toProcessedSpannableStringBuilder()
    }

    private val centerView = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        addView(animationView, LinearLayout.LayoutParams(160.dp, 160.dp))
        addView(
            resultLabel,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                topMargin = 16.dp
            }
        )
    }

    private val doneButton = WButton(context).apply {
        text = LocaleController.getString("Done")
        setOnClickListener {
            window?.dismissLastNav { }
        }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Card has been upgraded!"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(centerView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        view.addView(doneButton, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))

        view.setConstraints {
            topToBottom(centerView, navigationBar!!)
            bottomToTop(centerView, doneButton)
            toCenterX(centerView, 32f)
            toCenterX(doneButton, 16f)
            toBottom(doneButton, 16f)
        }

        animationView.play(R.raw.animation_thumb, false, onStart = {})

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setPadding(0, 0, 0, navigationController?.getSystemBars()?.bottom ?: 0)
    }
}
