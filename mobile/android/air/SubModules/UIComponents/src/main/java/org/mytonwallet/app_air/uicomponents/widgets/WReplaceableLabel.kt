package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color

class WReplaceableLabel(
    context: Context,
) : WView(context) {

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
        clipChildren = false
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
        progressView.isGone = !isLoading
        progressView.alpha = if (isLoading) 1f else 0f
    }

    fun setText(
        text: String,
        isLoading: Boolean,
        animated: Boolean = true,
        wasHidden: Boolean = false,
        beforeNewTextAppearance: (() -> Unit)? = null
    ) {
        if (isLoading == this.isLoading && text == label.text) {
            beforeNewTextAppearance?.invoke()
            return
        }
        if (isLoading == this.animatingIsLoadingTo && text == animatingTextTo) {
            return
        }

        if (!animated) {
            animatingTextTo = null
            animatingIsLoadingTo = null
            translationX = 0f
            scaleX = 1f
            scaleY = 1f
            label.text = text
            this.isLoading = isLoading
            beforeNewTextAppearance?.invoke()
            updateProgressView()
            return
        }

        val isLonger = text.length > (label.text?.length ?: 0)

        animatingTextTo = text
        animatingIsLoadingTo = isLoading

        fun setNewText() {
            if (animatingTextTo != text)
                return
            beforeNewTextAppearance?.invoke()
            if (isLoading && !this.isLoading) {
                progressView.visibility = VISIBLE
                progressView.fadeIn { }
            }
            this.isLoading = isLoading
            animatingTextTo = null
            animatingIsLoadingTo = null
            label.text = text
            translationX = 0f
            scaleX = 0.8f
            scaleY = 0.8f

            fun fadeInAndGrow() {
                animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(300)
                    .start()
            }

            if (isLonger && !wasHidden) {
                animate()
                    .setDuration(200)
                    .withEndAction { fadeInAndGrow() }
                    .start()
            } else {
                fadeInAndGrow()
            }
        }

        if (wasHidden) {
            setNewText()
        } else {
            if (!isLoading && this.isLoading) {
                progressView.fadeOut {
                    progressView.visibility = GONE
                }
            }
            animate()
                .alpha(0f)
                .translationX(-20f * LocaleController.rtlMultiplier)
                .setDuration(AnimationConstants.QUICK_ANIMATION)
                .withEndAction { setNewText() }
                .start()
        }
    }
}
