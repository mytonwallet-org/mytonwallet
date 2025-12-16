package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isGone
import kotlinx.coroutines.Runnable
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WReplaceableLabel(
    context: Context,
) : WView(context), WThemedView {

    init {
        clipChildren = false
        clipToPadding = false
    }

    val label: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.gravity = Gravity.CENTER
        lbl
    }

    private val roundDrawable = RoundProgressDrawable(context, 13.dp, 1f.dp).apply {
        color = WColor.SecondaryText.color
    }

    private val progressView = AppCompatImageView(context).apply {
        id = generateViewId()
        setPaddingLocalized(
            0,
            0,
            11.dp,
            0
        )
        layoutParams = LayoutParams(24.dp, 13.dp)
        setImageDrawable(roundDrawable)
        scaleType = ImageView.ScaleType.CENTER_INSIDE
        alpha = 0f
        visibility = GONE
    }

    override fun setupViews() {
        super.setupViews()
        addView(label, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(progressView)
        setConstraints {
            toCenterY(progressView)
            toStart(progressView, 1f)
            startToEnd(label, progressView)
            toEnd(label)
            toCenterY(label)
        }
    }

    override fun updateTheme() {
        label.setCompoundDrawables(null, null, config?.trailingDrawable?.apply {
            setTint(WColor.PrimaryText.color)
        }, null)
    }

    data class Config(
        val text: String,
        val isLoading: Boolean,
        val trailingDrawable: Drawable? = null
    )

    private var animatingConfig: Config? = null
    private var config: Config? = null

    private fun updateProgressView() {
        progressView.animate().cancel()
        progressView.isGone = config?.isLoading != true
        progressView.alpha = if (config?.isLoading == true) 1f else 0f
    }

    var setTextRunnable: Runnable? = null
    private var isFadingOut = false
    fun setText(
        config: Config,
        animated: Boolean = true,
        updateLabelAppearance: (() -> Unit)? = null
    ) {
        if (animatingConfig == null &&
            config.isLoading == this.config?.isLoading &&
            config.text == label.text
        ) {
            // Nothing changed, just update the appearance.
            updateLabelAppearance?.invoke()
            return
        }
        if (animated &&
            config.isLoading == this.animatingConfig?.isLoading &&
            config.text == this.animatingConfig?.text
        ) {
            // The appearing (animating) state is same, just return.
            return
        }
        config.trailingDrawable?.apply {
            setBounds(
                0,
                0,
                config.trailingDrawable.intrinsicWidth,
                config.trailingDrawable.intrinsicHeight
            )
        }

        if (!animated) {
            animatingConfig = null
            setTextRunnable = null
            isFadingOut = false
            translationX = 0f
            scaleX = 1f
            scaleY = 1f
            label.text = config.text
            label.setCompoundDrawables(null, null, config.trailingDrawable, null)
            this.config = config
            updateLabelAppearance?.invoke()
            updateProgressView()
            animate().cancel()
            alpha = 1f
            return
        }

        animatingConfig = config

        setTextRunnable = Runnable {
            setTextRunnable = null
            updateLabelAppearance?.invoke()
            this.animatingConfig = null
            this.config = config
            if (progressView.alpha < 1f && config.isLoading) {
                progressView.visibility = VISIBLE
                progressView.fadeIn { }
            } else if (!config.isLoading) {
                updateProgressView()
            }
            label.text = config.text
            label.setCompoundDrawables(null, null, config.trailingDrawable, null)
            translationX = 0f

            animate().cancel()
            if (alpha < 1f)
                animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                    .start()
        }

        if (alpha == 0f || label.text.isNullOrEmpty()) {
            isFadingOut = false
            setTextRunnable?.run()
        } else {
            if (isFadingOut)
                return
            isFadingOut = true
            animate().cancel()
            animate()
                .alpha(0f)
                .translationX(if (animatingConfig?.text.isNullOrEmpty()) 0f else -20f * LocaleController.rtlMultiplier)
                .setDuration(AnimationConstants.QUICK_ANIMATION)
                .withEndAction {
                    isFadingOut = false
                    setTextRunnable?.let {
                        scaleX = 0.8f
                        scaleY = 0.8f
                        setTextRunnable?.run()
                    }
                }
                .start()
        }
    }
}
