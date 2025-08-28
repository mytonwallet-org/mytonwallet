package org.mytonwallet.app_air.uisend.sent

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.text.SpannableStringBuilder
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import kotlin.math.max

@SuppressLint("ViewConstructor")
class SentVC(
    context: Context,
    val topTitle: String,
    private val sentText: String,
    private val sentEquivalentText: SpannableStringBuilder?,
    private val description: SpannableStringBuilder?
) :
    WViewController(context) {

    override var isSwipeBackAllowed: Boolean = false
    override val ignoreSideGuttering = true

    private val headerView: WAnimationView by lazy {
        val v = WAnimationView(context)
        v
    }

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(36f, WFont.Medium)
        lbl.text = sentText
        lbl.gravity = Gravity.CENTER
        lbl
    }

    private val sentEquivalentLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(22f, WFont.Medium)
        lbl.text = sentEquivalentText
        lbl.gravity = Gravity.CENTER
        lbl
    }

    private val descriptionLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.text = description
        lbl.gravity = Gravity.CENTER
        lbl
    }

    private val centerView: WView by lazy {
        val v = WView(context)
        v.addView(headerView, ConstraintLayout.LayoutParams(124.dp, 124.dp))
        v.addView(titleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        v.addView(sentEquivalentLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        v.addView(descriptionLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        v.setConstraints {
            toTop(headerView)
            toCenterX(headerView)
            topToBottom(titleLabel, headerView, 24f)
            toCenterX(titleLabel, 8f)
            topToBottom(sentEquivalentLabel, titleLabel, 8f)
            toCenterX(sentEquivalentLabel, 8f)
            topToBottom(descriptionLabel, sentEquivalentLabel, 8f)
            toCenterX(descriptionLabel, 8f)
            toBottom(descriptionLabel)
        }
        v
    }
    private val doneButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.PRIMARY)
        btn.text =
            LocaleController.getString("Done")
        btn.setOnClickListener {
            navigationController?.onBackPressed()
        }
        btn
    }

    override fun setupViews() {
        super.setupViews()

        centerView.alpha = 0f

        setNavTitle(topTitle)
        setupNavBar(true)
        if ((navigationController?.viewControllers?.size ?: 0) < 2)
            navigationBar?.addCloseButton()

        view.addView(centerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(doneButton, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        view.setConstraints {
            toCenterX(doneButton, 20f)
            toBottomPx(
                doneButton,
                20.dp + max(
                    navigationController?.getSystemBars()?.bottom ?: 0,
                    window?.imeInsets?.bottom ?: 0
                )
            )
            topToBottom(centerView, navigationBar!!)
            toCenterX(centerView)
            bottomToTop(centerView, doneButton)
        }

        headerView.play(R.raw.animation_congrats, false, onStart = {
            startedNow()
        })
        // If animation did not start in a few seconds, fade in anyway!
        Handler(Looper.getMainLooper()).postDelayed({
            startedNow()
        }, 3000)

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.Background.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        sentEquivalentLabel.setTextColor(WColor.SecondaryText.color)
        descriptionLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var startedAnimation = false
    private fun startedNow() {
        if (startedAnimation)
            return
        startedAnimation = true
        centerView.fadeIn()
    }

}
