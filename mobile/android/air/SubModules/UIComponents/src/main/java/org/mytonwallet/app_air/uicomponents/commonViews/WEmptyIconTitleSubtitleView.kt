package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class WEmptyIconTitleSubtitleView(
    context: Context,
    val animation: Int,
    val title: String,
    val subtitle: String,
) : WView(context), WThemedView {

    private val animationView: WAnimationView by lazy {
        WAnimationView(context)
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(17f, WFont.SemiBold)
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(17f)
            gravity = Gravity.CENTER
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(animationView, LayoutParams(124.dp, 124.dp))
        addView(titleLabel)
        addView(
            subtitleLabel,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, LayoutParams.WRAP_CONTENT)
        )

        setConstraints {
            toTop(animationView)
            toCenterX(animationView)
            topToBottom(titleLabel, animationView, 24f)
            toCenterX(titleLabel)
            topToBottom(subtitleLabel, titleLabel, 22f)
            toCenterX(subtitleLabel, 4f)
            toBottom(subtitleLabel)
        }

        alpha = 0f
        animationView.play(animation, onStart = {
            startedNow()
        })
        titleLabel.text = title
        subtitleLabel.text = subtitle
        // If animation did not start in a few seconds, fade in anyway!
        Handler(Looper.getMainLooper()).postDelayed({
            startedNow()
        }, 3000)

        updateTheme()
    }

    var startedAnimation = false
        private set

    private fun startedNow() {
        if (startedAnimation)
            return
        startedAnimation = true
        fadeIn()
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }
}
