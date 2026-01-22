package org.mytonwallet.app_air.uicomponents.image

import android.annotation.SuppressLint
import android.content.Context
import android.widget.ImageView
import androidx.core.view.isGone
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WActivityImageView(context: Context, viewSize: Int) : WView(context),
    org.mytonwallet.app_air.uicomponents.widgets.WThemedView {

    val imageView: WCustomImageView by lazy {
        WCustomImageView(context).apply {
            chainSize = this@WActivityImageView.chainSize
            chainOffsetX = 2f.dp
            chainOffsetY = 1f.dp
        }
    }

    private var animationView: WAnimationView? = null
    private var content: Content? = null
    private var currentAnimationRes: Int = 0

    var chainSize: Int = 16.dp
        set(value) {
            field = value
            imageView.chainSize = value
            animationView?.let {
                it.layoutParams?.apply {
                    width = value
                    height = value
                }
            }
        }

    init {
        addView(
            imageView, LayoutParams(
                viewSize,
                viewSize
            )
        )
        clipChildren = false
        clipToPadding = false
    }

    fun setSize(size: Int) {
        imageView.updateLayoutParams {
            width = size
            height = size
        }
    }

    private var fadeOutSubImageAnimation = true
    private var animationVisible = false
    fun set(content: Content?, lowResUrl: String? = null) {
        this.content = content ?: run {
            clear()
            return
        }

        val hasSubAnimation = content.subImageAnimation != 0

        val imageContent = if (hasSubAnimation) {
            content.copy(subImageRes = 0)
        } else {
            content
        }
        imageView.set(imageContent, lowResUrl)

        if (hasSubAnimation) {
            ensureAnimationView()

            if (!animationVisible) {
                animationVisible = true
                animationView?.apply {
                    animate().cancel()
                    isGone = false
                    alpha = 1f
                }
            }

            if (currentAnimationRes != content.subImageAnimation) {
                currentAnimationRes = content.subImageAnimation
                animationView?.play(content.subImageAnimation, repeat = true) {}
            }

        } else {
            hideAnimationView()
        }
    }

    private fun ensureAnimationView() {
        if (animationView != null) return

        animationView = WAnimationView(context).apply {
            scaleType = ImageView.ScaleType.FIT_XY
            layoutParams = LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT
            )
            setPadding(0.66f.dp.roundToInt())
            isGone = true
        }

        animationView?.setBackgroundColor(
            WColor.SecondaryBackground.color,
            chainSize.toFloat()
        )

        addView(animationView)
    }

    private fun hideAnimationView() {
        if (!animationVisible) return

        animationVisible = false

        animationView?.apply {
            animate().cancel()

            if (fadeOutSubImageAnimation) {
                fadeOut {
                    if (!animationVisible) {
                        cancelAnimation()
                        isGone = true
                    }
                }
            } else {
                cancelAnimation()
                isGone = true
            }
        }

        currentAnimationRes = 0
    }

    fun clear() {
        imageView.clear()
        animationView?.let {
            it.cancelAnimation()
            removeView(it)
        }
        animationView = null
        animationVisible = false
        content = null
        currentAnimationRes = 0
    }

    fun setAsset(
        token: org.mytonwallet.app_air.walletcore.models.MToken,
        showChain: Boolean = false
    ) {
        imageView.setAsset(token, showChain)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)

        animationView?.let {
            val animLeft = measuredWidth - chainSize
            val animTop = measuredHeight - chainSize
            it.layout(animLeft, animTop, measuredWidth + 2.dp, measuredHeight + 2.dp)
        }
    }

    override fun updateTheme() {
        imageView.updateTheme()
        animationView?.setBackgroundColor(WColor.SecondaryBackground.color, chainSize.toFloat())
    }
}
