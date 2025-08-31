package org.mytonwallet.app_air.uicomponents.image

import android.content.Context
import android.widget.ImageView
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import kotlin.math.roundToInt

class WActivityImageView(context: Context) : WView(context),
    org.mytonwallet.app_air.uicomponents.widgets.WThemedView {

    val imageView: WCustomImageView by lazy {
        WCustomImageView(context).apply {
            chainSize = this@WActivityImageView.chainSize
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
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT
            )
        )
    }

    fun set(content: Content, lowResUrl: String? = null) {
        this.content = content

        val imageContent = if (content.subImageAnimation != 0) {
            content.copy(subImageRes = 0)
        } else {
            content
        }
        imageView.set(imageContent, lowResUrl)

        if (content.subImageAnimation != 0) {
            if (animationView == null) {
                animationView = WAnimationView(context).apply {
                    scaleType = ImageView.ScaleType.FIT_XY
                    layoutParams =
                        LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
                    setPadding(0.66f.dp.roundToInt())
                }
                animationView?.setBackgroundColor(
                    WColor.SecondaryBackground.color,
                    chainSize.toFloat()
                )
                addView(animationView)
            }
            if (currentAnimationRes != content.subImageAnimation) {
                currentAnimationRes = content.subImageAnimation
                animationView?.play(content.subImageAnimation, repeat = true) {}
            }
        } else {
            animationView?.let {
                it.cancelAnimation()
                removeView(it)
            }
            animationView = null
            currentAnimationRes = 0
        }
    }

    fun clear() {
        imageView.clear()
        animationView?.let {
            it.cancelAnimation()
            removeView(it)
        }
        animationView = null
        content = null
        currentAnimationRes = 0
    }

    fun setAsset(
        token: org.mytonwallet.app_air.walletcore.models.MToken,
        alwaysShowChain: Boolean = false
    ) {
        imageView.setAsset(token, alwaysShowChain)
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
