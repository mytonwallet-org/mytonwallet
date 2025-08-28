package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class HeaderAndActionsView(
    context: Context,
    animation: Int?,
    val image: Int? = null,
    repeat: Boolean,
    title: String,
    subtitle: CharSequence,
    primaryActionTitle: String? = null,
    secondaryActionTitle: String? = null,
    trinaryActionTitle: String? = null,
    val primaryActionPressed: (() -> Unit)? = null,
    private val secondaryActionPressed: (() -> Unit)? = null,
    private val trinaryActionPressed: (() -> Unit)? = null,
    val headerPadding: Float = 0f,
    var onStarted: (() -> Unit)? = null
) :
    WView(context, LayoutParams(0, WRAP_CONTENT)), WThemedView {

    private val headerView: View by lazy {
        val v = if (animation != null) WAnimationView(context) else WImageView(context)
        v.setPadding(headerPadding.dp.roundToInt())
        v
    }

    private val titleLabel: WLabel by lazy {
        val v = WLabel(context)
        v
    }

    private val subTitleLabel: WLabel by lazy {
        val v = WLabel(context)
        v
    }

    val primaryActionButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.PRIMARY)
        btn.text = primaryActionTitle
        btn.setOnClickListener {
            primaryActionPressed?.invoke()
        }
        btn
    }

    val secondaryActionButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.SECONDARY)
        btn.text = secondaryActionTitle
        btn.setOnClickListener {
            secondaryActionPressed?.invoke()
        }
        btn
    }

    private val trinaryActionButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.SECONDARY)
        btn.text = trinaryActionTitle
        btn.setOnClickListener {
            trinaryActionPressed?.invoke()
        }
        btn
    }

    init {
        addView(headerView, LayoutParams(124.dp, 124.dp))
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(subTitleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        if (primaryActionTitle != null) {
            addView(primaryActionButton, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        if (secondaryActionTitle != null) {
            addView(secondaryActionButton, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        if (trinaryActionTitle != null) {
            addView(trinaryActionButton, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }

        setConstraints {
            toTop(headerView, 12F)
            toCenterX(headerView)
            topToBottom(titleLabel, headerView, 24F)
            toCenterX(titleLabel)
            topToBottom(subTitleLabel, titleLabel, 12F)
            toCenterX(subTitleLabel, 32F)
            if (primaryActionTitle != null) {
                topToBottom(primaryActionButton, subTitleLabel, 32F)
                toCenterX(primaryActionButton, 32F)
            }
            if (secondaryActionTitle != null) {
                topToBottom(secondaryActionButton, primaryActionButton, 16F)
                toCenterX(secondaryActionButton, 32F)
            }
            if (trinaryActionTitle != null) {
                topToBottom(trinaryActionButton, secondaryActionButton, 16F)
                toCenterX(trinaryActionButton, 32F)
            }
        }

        titleLabel.text = title
        titleLabel.setStyle(28F, WFont.Medium)
        subTitleLabel.text = subtitle
        subTitleLabel.setStyle(17f)
        subTitleLabel.textAlignment = TEXT_ALIGNMENT_CENTER
        subTitleLabel.setLineHeight(24f)

        alpha = 0f
        if (animation != null)
            (headerView as WAnimationView).play(animation, repeat, onStart = {
                startedNow()
            })
        else
            startedNow()
        // If animation did not start in a few seconds, fade in anyway!
        Handler(Looper.getMainLooper()).postDelayed({
            startedNow()
        }, 3000)

        updateTheme()
    }

    private var startedAnimation = false
    private fun startedNow() {
        if (startedAnimation)
            return
        startedAnimation = true
        fadeIn()
        onStarted?.invoke()
    }

    private var lastToggle = true
    fun toggle(on: Boolean) {
        val headerAnimation = headerView as WAnimationView
        if (lastToggle == on)
            return
        lastToggle = on
        if (on) {
            if (headerAnimation.progress < 0.5) {
                headerAnimation.speed = 1f
                headerAnimation.setMaxProgress(0.5f)
            } else {
                headerAnimation.speed = -1f
                headerAnimation.setMinProgress(0.5f)
            }
        } else {
            if (headerAnimation.progress == 0f) {
                headerAnimation.setMaxProgress(0f)
                return
            }
            if (headerAnimation.progress < 0.5) {
                headerAnimation.speed = -1f
                headerAnimation.setMinProgress(0.0f)
            } else {
                headerAnimation.speed = 1f
                headerAnimation.setMaxProgress(1f)
            }
        }
        headerAnimation.resumeAnimation()
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subTitleLabel.setTextColor(WColor.PrimaryText.color)
        if (image != null) {
            val drawable = ContextCompat.getDrawable(context, image)!!
            drawable.mutate()
            drawable.setTint(WColor.Tint.color)
            (headerView as WImageView).setImageDrawable(drawable)
        }
    }
}
