package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
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
) : WView(context) {

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

    private var animatingTextTo: String? = null
    private var isLoading: Boolean = false
    private var animatingIsLoadingTo: Boolean? = null

    private fun updateProgressView() {
        progressView.clearAnimation()
        progressView.isGone = !isLoading
        progressView.alpha = if (isLoading) 1f else 0f
    }

    var setTextRunnable: Runnable? = null
    fun setText(
        text: String,
        isLoading: Boolean,
        animated: Boolean = true,
        updateLabelAppearance: (() -> Unit)? = null
    ) {
        if (isLoading == this.isLoading && text == label.text) {
            // Nothing changed, just update the appearance.
            updateLabelAppearance?.invoke()
            return
        }
        if (isLoading == this.animatingIsLoadingTo && text == animatingTextTo) {
            // The appearing (animating) state is same, just return.
            return
        }

        if (!animated) {
            animatingTextTo = null
            animatingIsLoadingTo = null
            setTextRunnable = null
            translationX = 0f
            scaleX = 1f
            scaleY = 1f
            label.text = text
            this.isLoading = isLoading
            updateLabelAppearance?.invoke()
            updateProgressView()
            return
        }

        animatingTextTo = text
        animatingIsLoadingTo = isLoading

        setTextRunnable = Runnable {
            setTextRunnable = null
            updateLabelAppearance?.invoke()
            this.isLoading = animatingIsLoadingTo == true
            if (progressView.alpha < 1f && this.isLoading) {
                progressView.visibility = VISIBLE
                progressView.fadeIn { }
            } else if (!this.isLoading) {
                updateProgressView()
            }
            animatingTextTo = null
            animatingIsLoadingTo = null
            label.text = text
            translationX = 0f

            animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .start()
        }

        if (alpha == 0f) {
            setTextRunnable?.run()
        } else {
            animate()
                .alpha(0f)
                .translationX(-20f * LocaleController.rtlMultiplier)
                .setDuration(AnimationConstants.QUICK_ANIMATION)
                .withEndAction {
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
