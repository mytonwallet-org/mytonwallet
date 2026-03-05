package org.mytonwallet.app_air.uiassets.viewControllers.assets.cells

import android.animation.ObjectAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.LinearInterpolator
import androidx.core.content.ContextCompat
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setSizeBounds
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WSpacingSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.image.WNftImageView
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore

@SuppressLint("ViewConstructor")
class AssetCell(
    context: Context,
    val mode: AssetsVC.Mode
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    companion object {
        private val NFT_NUMBER_REGEX = Regex("""^(.*\S)\s*([#№][\d/]+)$""")
    }

    private val ripple = WRippleDrawable.create(16f.dp)

    var onTap: ((transaction: ApiNft) -> Unit)? = null

    private val imageView: WNftImageView by lazy {
        WNftImageView(context, 48.dp, 4.dp, 16f.dp)
    }

    private val animationView: WAnimationView by lazy {
        val v = WAnimationView(context)
        v.setBackgroundColor(Color.TRANSPARENT, 16f.dp, true)
        v.visibility = GONE
        v
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.DemiBold)
            setLineHeight(24f)
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
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        imageView.updateTheme()
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged) return
        _isDarkThemeApplied = ThemeManager.isDark
        ripple.rippleColor = WColor.SecondaryBackground.color
        if (mode == AssetsVC.Mode.COMPLETE) {
            nft?.let {
                setNftTitle(it)
                setNftSubtitle(it)
            }
            titleLabel.updateTheme()
            subtitleLabel.updateTheme()
        }
    }

    private fun setNftTitle(nft: ApiNft) {
        val nftName = nft.name
        if (nftName == null) {
            titleLabel.text = SpannableStringBuilder(nft.address.formatStartEndAddress()).apply {
                styleDots()
            }
            return
        }
        val match = NFT_NUMBER_REGEX.find(nftName)
        titleLabel.text = if (match != null) {
            val beforeHash = match.groupValues[1]
            val fromHash = match.groupValues[2]
            SpannableStringBuilder().apply {
                inSpans(WTypefaceSpan(WFont.DemiBold, WColor.PrimaryText)) {
                    append("$beforeHash ")
                }
                inSpans(WTypefaceSpan(WFont.DemiBold, WColor.SecondaryText)) {
                    append(fromHash)
                }
            }
        } else {
            nftName
        }
    }

    private fun setNftSubtitle(nft: ApiNft) {
        val subtitleText = nft.collectionName ?: LocaleController.getString("Standalone NFT")
        val chainDrawable = subtitleChainIconDrawable(nft)
        subtitleLabel.text = if (chainDrawable != null) {
            buildSpannedString {
                inSpans(
                    VerticalImageSpan(
                        chainDrawable,
                        verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                    )
                ) { append(" ") }
                inSpans(WSpacingSpan(4.dp)) { append(" ") }
                append(subtitleText)
            }
        } else {
            subtitleText
        }
    }

    private fun subtitleChainIconDrawable(nft: ApiNft): Drawable? {
        val chain = nft.chain ?: return null
        val iconRes = chain.symbolIconPadded ?: chain.symbolIcon ?: return null
        return ContextCompat.getDrawable(context, iconRes)?.mutate()?.apply {
            setTint(WColor.SecondaryText.color)
            setSizeBounds(12.dp, 12.dp)
        }
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
        imageView.setNftImage(nft.thumbnail)
        if (mode == AssetsVC.Mode.COMPLETE) {
            setNftTitle(nft)
            setNftSubtitle(nft)
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
        updateTheme()
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
