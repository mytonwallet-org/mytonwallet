package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class WEmptyIconView(
    context: Context,
    val animation: Int,
    val text: String
) : WView(context), WThemedView {

    private val animationView: WAnimationView by lazy {
        val v = WAnimationView(context)
        v
    }

    private val textLabel: WLabel by lazy {
        val v = WLabel(context)
        v.setStyle(16f)
        v.textAlignment = TEXT_ALIGNMENT_CENTER
        v
    }

    override fun setupViews() {
        super.setupViews()

        addView(animationView, LayoutParams(124.dp, 124.dp))
        addView(textLabel)

        setConstraints {
            toTop(animationView, 12F)
            toCenterX(animationView)
            topToBottom(textLabel, animationView, 8F)
            toCenterX(textLabel)
            toBottom(textLabel)
        }

        alpha = 0f
        animationView.play(animation, false, onStart = {
            startedNow()
        })
        textLabel.text = text
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
        textLabel.setTextColor(WColor.PrimaryText.color)
    }
}
