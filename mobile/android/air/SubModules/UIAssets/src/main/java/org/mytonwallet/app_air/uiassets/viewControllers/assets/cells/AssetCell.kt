package org.mytonwallet.app_air.uiassets.viewControllers.assets.cells

import android.animation.ObjectAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.LinearInterpolator
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVM
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.CheckboxDrawable
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
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

@SuppressLint("ViewConstructor")
class AssetCell(
    context: Context,
    val viewMode: AssetsVC.ViewMode
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    companion object {
        private val NFT_NUMBER_REGEX = Regex("""^(.*\S)\s*([#№][\d/]+)$""")
        const val CORNER_RADIUS_COMPLETE = 16f
        const val CORNER_RADIUS_THUMB = 8f
    }

    private val ripple = WRippleDrawable.create(16f.dp)

    var onTap: ((transaction: ApiNft) -> Unit)? = null
    var onLongPress: ((anchorView: WNftImageView, nft: ApiNft) -> Unit)? = null

    private val imageCornerRadius = if (viewMode == AssetsVC.ViewMode.THUMB) {
        CORNER_RADIUS_THUMB
    } else {
        CORNER_RADIUS_COMPLETE
    }.dp

    private val imageView: WNftImageView by lazy {
        WNftImageView(context, 48.dp, 4.dp, imageCornerRadius)
    }

    private val saleBadgeView: AppCompatImageView by lazy {
        AppCompatImageView(context).apply {
            id = generateViewId()
            setImageResource(org.mytonwallet.app_air.uiassets.R.drawable.ic_nft_sale)
            isGone = true
        }
    }

    private val expiryInfoView = WLabel(context).apply {
        id = generateViewId()
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        setStyle(12f, WFont.SemiBold)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.MARQUEE
        marqueeRepeatLimit = -1
        isHorizontalFadingEdgeEnabled = true
        isSelected = true
        setBackgroundColor(WColor.Red.color, 0f, imageCornerRadius)
        isGone = true
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
            useCustomEmoji = true
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

    private val checkboxDrawable = CheckboxDrawable {
        invalidate()
    }

    private val checkboxImageView = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageDrawable(checkboxDrawable)
        isGone = true
    }

    init {
        background = ripple
        setPadding((if (viewMode == AssetsVC.ViewMode.COMPLETE) 8 else 4).dp)
        clipToPadding = false

        addView(imageView, LayoutParams(0, 0))
        if (viewMode == AssetsVC.ViewMode.COMPLETE) {
            addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(subtitleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }

        addView(animationView, LayoutParams(0, 0))
        addView(expiryInfoView, LayoutParams(0, 24.dp))
        addView(saleBadgeView, LayoutParams(28.dp, 30.dp))
        val checkboxSize = if (viewMode == AssetsVC.ViewMode.COMPLETE) 22.dp else 20.dp
        addView(checkboxImageView, LayoutParams(checkboxSize, checkboxSize))

        setConstraints {
            toTop(imageView)
            toStart(imageView)
            toEnd(imageView)
            toCenterX(imageView)
            setDimensionRatio(imageView.id, "1:1")
            edgeToEdge(animationView, imageView)
            toTop(checkboxImageView, 10f)
            toEnd(checkboxImageView, 10f)
            if (viewMode == AssetsVC.ViewMode.COMPLETE) {
                topToBottom(titleLabel, imageView, 8f)
                toCenterX(titleLabel)
                topToBottom(subtitleLabel, titleLabel)
                toCenterX(subtitleLabel)
                toBottom(subtitleLabel)
            } else {
                toBottom(imageView)
            }
            bottomToBottom(expiryInfoView, imageView)
            centerXToCenterX(expiryInfoView, imageView)
            topToTop(saleBadgeView, imageView, -2f)
            endToEnd(saleBadgeView, imageView, 16f)
        }

        setOnClickListener {
            nft?.let {
                onTap?.invoke(it)
            }
        }
        setOnLongClickListener {
            if (interactionMode != AssetsVM.InteractionMode.NORMAL) {
                return@setOnLongClickListener false
            }
            nft?.let {
                onLongPress?.invoke(imageView, it)
            }
            nft != null && onLongPress != null
        }
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        imageView.updateTheme()
        checkboxDrawable.checkedColor = WColor.Tint.color
        checkboxDrawable.uncheckedColor = WColor.White.color
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged) return
        _isDarkThemeApplied = ThemeManager.isDark
        ripple.rippleColor = WColor.SecondaryBackground.color
        if (viewMode == AssetsVC.ViewMode.COMPLETE) {
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
    private var interactionMode: AssetsVM.InteractionMode = AssetsVM.InteractionMode.NORMAL
    private var animationsPaused = false
    private var daysUntilExpiration: Int? = null
    fun configure(
        nft: ApiNft,
        interactionMode: AssetsVM.InteractionMode,
        animationsPaused: Boolean,
        isSelected: Boolean,
        daysUntilExpiration: Int? = null
    ) {
        if (this.nft == nft &&
            this.interactionMode == interactionMode &&
            this.animationsPaused == animationsPaused &&
            this.isSelected == isSelected &&
            this.daysUntilExpiration == daysUntilExpiration
        ) {
            updateTheme()
            return
        }
        val nftChanged = this.nft?.address != nft.address
        val selectionModeChanged = !nftChanged &&
            (this.interactionMode == AssetsVM.InteractionMode.SELECTION) != (interactionMode == AssetsVM.InteractionMode.SELECTION)
        val selectedChanged = !nftChanged && this.isSelected != isSelected
        val onSaleChanged = this.nft?.address == nft.address && this.nft?.isOnSale != nft.isOnSale
        val expiryChanged = !nftChanged && this.daysUntilExpiration != daysUntilExpiration
        this.nft = nft
        this.interactionMode = interactionMode
        this.animationsPaused = animationsPaused
        this.isSelected = isSelected
        this.daysUntilExpiration = daysUntilExpiration
        imageView.setNftImage(nft.thumbnail)
        val isInSelectionMode = interactionMode == AssetsVM.InteractionMode.SELECTION
        val shouldShowSaleBadge = nft.isOnSale && !isInSelectionMode
        if (onSaleChanged || selectionModeChanged) {
            if (shouldShowSaleBadge) {
                showSaleBadge()
            } else {
                hideSaleBadge()
            }
        } else {
            saleBadgeView.isVisible = shouldShowSaleBadge
            saleBadgeView.alpha = if (shouldShowSaleBadge) 1f else 0f
        }
        val shouldShowExpiryInfo = daysUntilExpiration != null
        if (expiryChanged) {
            if (shouldShowExpiryInfo) {
                showExpiryInfo(daysUntilExpiration)
            } else {
                hideExpiryInfo()
            }
        } else {
            expiryInfoView.animate().cancel()
            if (shouldShowExpiryInfo) expiryInfoView.text = expiryText(daysUntilExpiration)
            expiryInfoView.isVisible = shouldShowExpiryInfo
            expiryInfoView.alpha = if (shouldShowExpiryInfo) 1f else 0f
        }
        if (viewMode == AssetsVC.ViewMode.COMPLETE) {
            setNftTitle(nft)
            setNftSubtitle(nft)
        }
        if (viewMode == AssetsVC.ViewMode.COMPLETE || DevicePerformanceClassifier.isHighClass) {
            animationView.visibility = GONE
            if (nft.metadata?.lottie?.isNotBlank() == true) {
                animationView.visibility = VISIBLE
                animationView.playFromUrl(
                    url = nft.metadata!!.lottie!!,
                    play = !animationsPaused,
                    onStart = {})
            }
        }
        if (interactionMode == AssetsVM.InteractionMode.DRAG) {
            startShake()
        } else {
            stopShake()
        }
        if (selectionModeChanged) {
            if (isInSelectionMode) {
                showSelectionControl()
            } else {
                hideSelectionControl()
            }
        } else {
            checkboxImageView.isVisible = isInSelectionMode
        }
        checkboxDrawable.setChecked(this.isSelected, selectedChanged)
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

    private fun showSelectionControl() {
        with(checkboxImageView) {
            isVisible = true
            alpha = 0f
            fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        }
    }

    private fun hideSelectionControl() {
        with(checkboxImageView) {
            fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                isGone = true
            }
        }
    }

    private fun showSaleBadge() {
        with(saleBadgeView) {
            animate().cancel()
            isVisible = true
            alpha = 0f
            fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        }
    }

    private fun hideSaleBadge() {
        with(saleBadgeView) {
            animate().cancel()
            fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                isGone = true
            }
        }
    }

    private fun expiryText(days: Int): String {
        if (days < 0) return LocaleController.getString("\$nft_expired")
        val daysStr = LocaleController.getPlural(days, "\$in_days")
        return LocaleController.getString("\$one_domain_expires %days%")
            .replace("%days%", daysStr)
    }

    private fun showExpiryInfo(days: Int) {
        with(expiryInfoView) {
            text = expiryText(days)
            animate().cancel()
            isVisible = true
            alpha = 0f
            fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        }
    }

    private fun hideExpiryInfo() {
        with(expiryInfoView) {
            animate().cancel()
            fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                isGone = true
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopShake()
    }
}
