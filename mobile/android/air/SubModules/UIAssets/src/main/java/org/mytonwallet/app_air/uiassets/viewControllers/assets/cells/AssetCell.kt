package org.mytonwallet.app_air.uiassets.viewControllers.assets.cells

import android.animation.ObjectAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.LinearInterpolator
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

@SuppressLint("ViewConstructor")
class AssetCell(
    context: Context,
    val mode: AssetsVC.Mode
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private val ripple = WRippleDrawable.create(16f.dp)

    var onTap: ((transaction: ApiNft) -> Unit)? = null

    private val imageView: WImageView by lazy {
        val img = WImageView(context, 16.dp)
        img
    }

    private val animationView: WAnimationView by lazy {
        val v = WAnimationView(context)
        v.setBackgroundColor(Color.TRANSPARENT, 16f.dp, true)
        v.visibility = GONE
        v
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            setTextColor(WColor.PrimaryText)
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            setTextColor(WColor.SecondaryText)
        }
    }

    init {
        background = ripple
        setPadding((if (mode == AssetsVC.Mode.COMPLETE) 8 else 4).dp)

        addView(imageView, LayoutParams(0, 0))
        if (mode == AssetsVC.Mode.COMPLETE) {
            addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(subtitleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }

        addView(animationView, LayoutParams(0, 0))

        setConstraints {
            toTop(imageView)
            toCenterX(imageView)
            setDimensionRatio(imageView.id, "1:1")
            edgeToEdge(animationView, imageView)
            if (mode == AssetsVC.Mode.COMPLETE) {
                topToBottom(titleLabel, imageView, 8f)
                toCenterX(titleLabel)
                topToBottom(subtitleLabel, titleLabel)
                toCenterX(subtitleLabel)
                toBottom(subtitleLabel)
            } else {
                toBottom(imageView)
            }
        }

        setOnClickListener {
            nft?.let {
                onTap?.invoke(it)
            }
        }

        updateTheme()
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged)
            return
        _isDarkThemeApplied = ThemeManager.isDark
        ripple.rippleColor = WColor.SecondaryBackground.color
        titleLabel.updateTheme()
        subtitleLabel.updateTheme()
    }

    private var nft: ApiNft? = null
    private var isInDragMode = false
    private var animationsPaused = false
    fun configure(
        nft: ApiNft,
        isInDragMode: Boolean,
        animationsPaused: Boolean
    ) {
        if (this.nft == nft && this.isInDragMode == isInDragMode && this.animationsPaused == animationsPaused) {
            updateTheme()
            return
        }
        this.nft = nft
        this.isInDragMode = isInDragMode
        this.animationsPaused = animationsPaused
        imageView.loadUrl(nft.thumbnail ?: "")
        if (mode == AssetsVC.Mode.COMPLETE) {
            nft.name?.let {
                titleLabel.text = it
            } ?: run {
                titleLabel.text =
                    SpannableStringBuilder(nft.address.formatStartEndAddress()).apply {
                        styleDots()
                    }
            }
            subtitleLabel.text =
                nft.collectionName ?: LocaleController.getString("Standalone NFT")
        }
        if (mode == AssetsVC.Mode.COMPLETE || DevicePerformanceClassifier.isHighClass) {
            animationView.visibility = GONE
            if (nft.metadata?.lottie?.isNotBlank() == true) {
                animationView.visibility = VISIBLE
                animationView.playFromUrl(
                    url = nft.metadata!!.lottie!!,
                    play = !animationsPaused,
                    onStart = {})
            }
        }
        if (isInDragMode) {
            startShake()
        } else {
            stopShake()
        }
    }

    fun pauseAnimation() {
        animationView.pauseAnimation()
    }

    fun resumeAnimation() {
        animationView.resumeAnimation()
    }

    private var shakeAnimator: ObjectAnimator? = null
    private fun startShake() {
        stopShake()
        shakeAnimator = ObjectAnimator.ofFloat(this, "rotation", 0f, -1f, 2f, -1f, 2f, 0f).apply {
            duration = AnimationConstants.SLOW_ANIMATION
            repeatCount = ObjectAnimator.INFINITE
            interpolator = LinearInterpolator()
            start()
        }
    }

    private fun stopShake() {
        shakeAnimator?.cancel()
        shakeAnimator = null
        rotation = 0f
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopShake()
    }
}
