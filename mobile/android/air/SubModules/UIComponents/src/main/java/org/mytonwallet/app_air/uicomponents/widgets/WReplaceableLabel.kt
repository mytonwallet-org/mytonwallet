package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
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
        setPadding(0, 0, 11.dp, 0)
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

    fun setText(
        text: String,
        isLoading: Boolean,
        animated: Boolean = true,
        wasHidden: Boolean = false,
        beforeNewTextAppearance: (() -> Unit)? = null
    ) {
        if (text == label.text || text == animatingTextTo) return

        if (!animated) {
            animatingTextTo = null
            translationX = 0f
            scaleX = 1f
            scaleY = 1f
            label.text = text
            if (isLoading) {
                progressView.visibility = VISIBLE
                progressView.alpha = 1f
            } else {
                progressView.visibility = GONE
                progressView.alpha = 0f
            }
            this.isLoading = isLoading
            return
        }

        val isLonger = text.length > (label.text?.length ?: 0)

        animatingTextTo = text

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

            if (isLonger) {
                animate()
                    .setDuration(if (wasHidden) 0 else 200)
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
                .translationX(-20f)
                .setDuration(300)
                .withEndAction { setNewText() }
                .start()
        }
    }
}
