package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.view.Gravity
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WEmptyIconTitleSubtitleActionView(context: Context) : WView(context), WThemedView {

    private val animationView: WAnimationView by lazy {
        WAnimationView(context)
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(17f, WFont.SemiBold)
            setTextColor(WColor.PrimaryText)
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f)
            setLineHeight(21f)
            setTextColor(WColor.SecondaryText)
        }
    }

    private val actionButton: WLabel by lazy {
        object : WLabel(context) {
            private val ripple = WRippleDrawable.create(20f.dp)

            init {
                background = ripple
            }

            override fun updateTheme() {
                super.updateTheme()
                ripple.rippleColor = WColor.TintRipple.color
            }
        }.apply {
            setPaddingDp(12, 0, 12, 0)
            gravity = Gravity.CENTER_VERTICAL
            setStyle(14f, WFont.DemiBold)
            setTextColor(WColor.Tint)
            updateTheme()
        }
    }

    var startedAnimation = false
        private set

    override fun setupViews() {
        super.setupViews()
        addView(animationView, LayoutParams(100.dp, 100.dp))
        addView(titleLabel, LayoutParams(LayoutParams.MATCH_CONSTRAINT, LayoutParams.WRAP_CONTENT))
        addView(
            subtitleLabel, LayoutParams(
                LayoutParams.MATCH_CONSTRAINT,
                LayoutParams.WRAP_CONTENT
            )
        )
        addView(actionButton, LayoutParams(LayoutParams.WRAP_CONTENT, 40.dp))

        setConstraints {
            toCenterY(animationView)
            toStart(animationView, 24f)

            startToEnd(titleLabel, animationView, 24f)
            toEnd(titleLabel, 24f)
            startToEnd(subtitleLabel, animationView, 24f)
            toEnd(subtitleLabel, 24f)
            startToEnd(actionButton, animationView, 12f)
            toEnd(actionButton, 24f)
            setHorizontalBias(actionButton.id, 0f)

            toTop(titleLabel, 24f)
            topToBottom(subtitleLabel, titleLabel, 6f)
            topToBottom(actionButton, subtitleLabel, 1f)
            toBottom(actionButton, 14f)
        }

        updateTheme()
    }

    fun configure(
        titleText: String,
        subtitleText: String,
        actionText: String,
        animation: Int,
        actionCallback: () -> Unit
    ) {
        startedAnimation = false
        titleLabel.text = titleText
        subtitleLabel.text = subtitleText
        actionButton.text = actionText
        animationView.alpha = 0f
        animationView.play(animation, repeat = true) {
            startedNow()
        }
        actionButton.setOnClickListener { actionCallback() }
    }

    private fun startedNow() {
        if (startedAnimation) {
            return
        }
        startedAnimation = true
        animationView.fadeIn()
    }

    override fun updateTheme() {
        titleLabel.updateTheme()
        subtitleLabel.updateTheme()
        actionButton.updateTheme()
    }
}
