package org.mytonwallet.app_air.uiassets.viewControllers.token.cells

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.PorterDuff
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.method.LinkMovementMethod
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.helper.widget.Flow
import androidx.core.view.doOnLayout
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.DynamicAnimation
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uiassets.viewControllers.token.TokenVM
import org.mytonwallet.app_air.uiassets.viewControllers.token.helpers.formatCompactNumber
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WBottomFadingFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColorLocalized
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.WDateFormatter
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MApiTokenDetails

@SuppressLint("ViewConstructor")
class TokenInfoCell(
    recyclerView: WRecyclerView,
    private val onHeightChange: (isExpanding: Boolean, height: Int) -> Unit,
    private val onShowInfo: (title: String, text: String) -> Unit,
    // Stable resource id for UI automation, set before containerView is anchored to the cell's id
    viewId: Int? = null
) : WCell(recyclerView.context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    companion object {
        const val COLLAPSED_HEIGHT_DP = 64
        val collapsedCellHeight: Int
            get() = COLLAPSED_HEIGHT_DP.dp + ViewConstants.GAP.dp

        private const val CREATED_AT_FORMAT = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        private const val MARKET_DESCRIPTION_MAX_LINES = 3
    }

    private val titleLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(14f)
        text = LocaleController.getString("Info")
    }

    private val expandedDescriptionLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(16f)
        setLineHeight(24f)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val previewDescriptionLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(16f)
        setLineHeight(24f)
        maxLines = MARKET_DESCRIPTION_MAX_LINES
        ellipsize = TextUtils.TruncateAt.END
        visibility = GONE
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val collapsedDescriptionLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(16f)
        setLineHeight(24f)
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
    }

    private val descriptionContainer = WBottomFadingFrameLayout(context).apply {
        addView(expandedDescriptionLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            collapsedDescriptionLabel,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                marginEnd = 32.dp
            }
        )
        addView(previewDescriptionLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private val showMoreLabel = WLabel(context).apply {
        setStyle(16f)
        setLineHeight(24f)
        visibility = GONE
        setOnClickListener { toggleFullDescription() }
    }

    private val descriptionColumn = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(descriptionContainer, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(showMoreLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    private val arrowIcon = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageResource(IconsR.drawable.ic_arrow_right_24)
        drawable.isAutoMirrored = false
        scaleType = ImageView.ScaleType.CENTER
        rotation = 90f
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val skeletonIndicator = WBaseView(context)
    private val skeletonView = SkeletonView(context, isVertical = false)

    private val headerView = WView(context).apply {
        minimumHeight = COLLAPSED_HEIGHT_DP.dp
        addView(titleLabel, LayoutParams(0, 18.dp))
        addView(descriptionColumn, LayoutParams(0, WRAP_CONTENT))
        addView(skeletonIndicator, LayoutParams(0, 24.dp))
        addView(arrowIcon, LayoutParams(24.dp, 24.dp))
        addView(skeletonView, LayoutParams(0, 0))
        setConstraints {
            toTop(titleLabel, 10f)
            toStart(titleLabel, 20f)
            toEnd(titleLabel, 52f)
            topToBottom(descriptionColumn, titleLabel, 3f)
            toStart(descriptionColumn, 20f)
            toEnd(descriptionColumn, 20f)
            toBottom(descriptionColumn, 9f)
            topToBottom(skeletonIndicator, titleLabel, 3f)
            toStart(skeletonIndicator, 20f)
            toEnd(skeletonIndicator, 52f)
            toTop(arrowIcon, 20f)
            toEnd(arrowIcon, 16f)
            allEdges(skeletonView)
        }
    }

    private val detailsContainer = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
    }

    private val contentView = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        addView(headerView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(detailsContainer, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private val containerView = WFrameLayout(context).apply {
        clipChildren = true
        clipToPadding = true
        addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private var state: TokenVM.TokenInfoState? = null
    private var isExpanded = false
    private var hasBalance = true
    private var expansionProgress = 0f
    private var fullDescriptionProgress = 1f
    private var expandedHeight = COLLAPSED_HEIGHT_DP.dp
    private var heightAnimator: SpringAnimation? = null
    private var descriptionToggleAnimator: ValueAnimator? = null
    private var translationAttributionLabel: WLabel? = null
    private var volumeBarView: VolumeBarView? = null
    private var isShowingOriginalDescription = false
    private var pendingStateRenderRunnable: Runnable? = null
    private var pendingHeightUpdateRunnable: Runnable? = null
    private var isExpandedHeightUpdatePending = false

    init {
        viewId?.let { id = it }
        addView(containerView, LayoutParams(MATCH_PARENT, COLLAPSED_HEIGHT_DP.dp))
        setConstraints {
            toTop(containerView)
            toCenterX(containerView)
            toBottom(containerView, ViewConstants.GAP.toFloat())
        }
        headerView.setOnClickListener {
            if (state is TokenVM.TokenInfoState.Details && hasBalance) {
                val expanded = !isExpanded
                if (setExpanded(expanded, animated = true)) {
                    WGlobalStorage.setIsTokenInfoExpanded(expanded)
                }
            }
        }
    }

    fun setHasBalance(hasBalance: Boolean, animated: Boolean) {
        if (this.hasBalance == hasBalance) return
        this.hasBalance = hasBalance
        if (state !is TokenVM.TokenInfoState.Details) {
            applyDescriptionMode()
            updateHeaderAccessibility()
            return
        }
        heightAnimator?.cancel()
        descriptionToggleAnimator?.cancel()
        descriptionToggleAnimator = null
        collapsedDescriptionLabel.animate().cancel()
        arrowIcon.animate().cancel()
        transitionLayout(!hasBalance || WGlobalStorage.getIsTokenInfoExpanded(), animated)
    }

    fun configure(newState: TokenVM.TokenInfoState) {
        val previousState = state
        val stateChanged = previousState != newState
        if (!stateChanged) return
        state = newState
        renderState(newState, previousState)
        updateTheme()
    }

    private fun renderState(state: TokenVM.TokenInfoState, previousState: TokenVM.TokenInfoState?) {
        heightAnimator?.cancel()
        heightAnimator = null
        descriptionToggleAnimator?.cancel()
        descriptionToggleAnimator = null
        collapsedDescriptionLabel.animate().cancel()
        arrowIcon.animate().cancel()
        val shouldExpand = state is TokenVM.TokenInfoState.Details &&
            (!hasBalance || WGlobalStorage.getIsTokenInfoExpanded())
        val wasExpanded = isExpanded
        val shouldShowExpandedImmediately = shouldExpand && when (previousState) {
            null -> true
            is TokenVM.TokenInfoState.Details -> wasExpanded
            else -> false
        }
        isExpanded = shouldShowExpandedImmediately
        isShowingOriginalDescription = false
        applyDescriptionMode()
        showMoreLabel.alpha = 1f
        setExpansionProgress(if (isExpanded) 1f else 0f)
        detailsContainer.importantForAccessibility =
            if (isExpanded) {
                IMPORTANT_FOR_ACCESSIBILITY_AUTO
            } else {
                IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }

        when (state) {
            TokenVM.TokenInfoState.Loading -> {
                expandedDescriptionLabel.text = null
                expandedDescriptionLabel.contentDescription = null
                expandedDescriptionLabel.visibility = INVISIBLE
                collapsedDescriptionLabel.text = null
                collapsedDescriptionLabel.visibility = INVISIBLE
                arrowIcon.alpha = 1f
                arrowIcon.visibility = GONE
                startSkeleton()
            }

            is TokenVM.TokenInfoState.Details -> {
                val shouldFadeIn = stopSkeleton()
                val description = displayDescription(state.info)
                expandedDescriptionLabel.text = description
                expandedDescriptionLabel.contentDescription = description
                collapsedDescriptionLabel.text = description
                previewDescriptionLabel.text = description
                collapsedDescriptionLabel.visibility = VISIBLE
                updateDescriptionDirection(state.info)
                if (shouldFadeIn) {
                    collapsedDescriptionLabel.alpha = 0f
                    collapsedDescriptionLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                }
                arrowIcon.visibility = if (hasBalance) VISIBLE else GONE
                if (shouldFadeIn && hasBalance) {
                    arrowIcon.alpha = 0f
                    arrowIcon.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                } else {
                    arrowIcon.alpha = 1f
                }
            }

            TokenVM.TokenInfoState.Fallback -> {
                val shouldFadeIn = stopSkeleton()
                expandedDescriptionLabel.text = null
                expandedDescriptionLabel.contentDescription = null
                expandedDescriptionLabel.visibility = GONE
                collapsedDescriptionLabel.text =
                    LocaleController.getString("\$token_info_fallback_description")
                setDescriptionDirection(LocaleController.isRTL)
                collapsedDescriptionLabel.visibility = VISIBLE
                if (shouldFadeIn) {
                    collapsedDescriptionLabel.alpha = 0f
                    collapsedDescriptionLabel.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
                }
                arrowIcon.alpha = 1f
                arrowIcon.visibility = GONE
            }
        }
        updateHeaderAccessibility()
        if (previousState == null && isExpanded) {
            containerView.updateLayoutParams { height = WRAP_CONTENT }
        } else if (!isExpanded) {
            setContainerHeight(COLLAPSED_HEIGHT_DP.dp, notify = wasExpanded, isExpanding = false)
        }
        pendingStateRenderRunnable?.let(::removeCallbacks)
        Runnable {
            pendingStateRenderRunnable = null
            if (this.state != state) return@Runnable
            updateExpandedHeight()
            if ((!hasBalance || WGlobalStorage.getIsTokenInfoExpanded()) && !isExpanded) {
                setExpanded(true, animated = true)
            }
        }.also {
            pendingStateRenderRunnable = it
            post(it)
        }
    }

    private fun startSkeleton() {
        skeletonIndicator.visibility = VISIBLE
        skeletonIndicator.alpha = 1f
        skeletonView.visibility = VISIBLE
        skeletonView.alpha = 1f
        skeletonView.doOnLayout {
            skeletonView.applyMask(
                listOf(skeletonIndicator),
                hashMapOf(0 to 4.dp.toFloat())
            )
            skeletonView.startAnimating()
        }
    }

    private fun stopSkeleton(): Boolean {
        if (!skeletonView.isAnimating) {
            skeletonView.visibility = GONE
            skeletonIndicator.visibility = GONE
            return false
        }
        skeletonView.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
            skeletonView.stopAnimating()
            skeletonView.alpha = 1f
        }
        skeletonIndicator.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
            skeletonIndicator.visibility = GONE
            skeletonIndicator.alpha = 1f
        }
        return true
    }

    private fun setExpanded(expanded: Boolean, animated: Boolean): Boolean {
        if (state !is TokenVM.TokenInfoState.Details ||
            heightAnimator != null ||
            descriptionToggleAnimator != null
        ) {
            return false
        }
        collapsedDescriptionLabel.animate().cancel()
        transitionLayout(expanded, animated)
        return true
    }

    private fun toggleFullDescription() {
        if (hasBalance ||
            state !is TokenVM.TokenInfoState.Details ||
            heightAnimator != null ||
            descriptionToggleAnimator != null
        ) {
            return
        }
        WGlobalStorage.setIsTokenInfoExpanded(!WGlobalStorage.getIsTokenInfoExpanded())
        transitionLayout(expanded = true, animated = true)
    }

    private fun transitionLayout(expanded: Boolean, animated: Boolean) {
        val startHeight = containerView.height.coerceAtLeast(COLLAPSED_HEIGHT_DP.dp)
        val startContentHeight = contentView.height
        val startDescriptionHeight = descriptionContainer.height
        val startProgress = expansionProgress
        val startArrowAlpha = if (arrowIcon.isVisible) arrowIcon.alpha else 0f
        val startExpandedAlpha =
            if (expandedDescriptionLabel.isVisible) expandedDescriptionLabel.alpha else 0f
        val startPreviewAlpha =
            if (previewDescriptionLabel.isVisible) previewDescriptionLabel.alpha else 0f
        val startCollapsedAlpha = collapsedDescriptionLabel.alpha
        val isShowMoreInitiallyVisible = showMoreLabel.isVisible
        val startShowMoreAlpha = if (isShowMoreInitiallyVisible) showMoreLabel.alpha else 0f
        val startShowMoreHeight = if (isShowMoreInitiallyVisible) showMoreLabel.height else 0
        val startShowMoreText = showMoreLabel.text

        isExpanded = expanded
        detailsContainer.importantForAccessibility =
            if (expanded) {
                IMPORTANT_FOR_ACCESSIBILITY_AUTO
            } else {
                IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }
        updateHeaderAccessibility()
        applyDescriptionMode()

        val targetProgress = if (expanded) 1f else 0f
        val targetArrowAlpha = if (hasBalance) 1f else 0f
        val targetContentHeight = measureExpandedHeight()
        if (targetContentHeight == null ||
            !animated ||
            !WGlobalStorage.getAreAnimationsActive()
        ) {
            arrowIcon.alpha = 1f
            arrowIcon.isVisible = hasBalance
            showMoreLabel.alpha = 1f
            setExpansionProgress(targetProgress)
            updateExpandedHeight()
            if (!expanded) {
                setContainerHeight(COLLAPSED_HEIGHT_DP.dp, notify = true, isExpanding = false)
            }
            return
        }

        val targetHeight = if (expanded) targetContentHeight else COLLAPSED_HEIGHT_DP.dp
        val targetDescriptionHeight = descriptionContainer.measuredHeight
        val isExpandedFinallyVisible = expandedDescriptionLabel.isVisible
        val isPreviewFinallyVisible = previewDescriptionLabel.isVisible
        val targetExpandedAlpha = targetProgress * fullDescriptionProgress
        val targetPreviewAlpha = targetProgress * (1f - fullDescriptionProgress)
        val targetCollapsedAlpha = 1f - targetProgress
        val isShowMoreFinallyVisible = showMoreLabel.isVisible
        val targetShowMoreAlpha = if (isShowMoreFinallyVisible) 1f else 0f
        val targetShowMoreHeight =
            if (isShowMoreFinallyVisible) showMoreLabel.measuredHeight else 0
        measureFullDescription()
        val fullDescriptionHeight = expandedDescriptionLabel.measuredHeight
        val animatesDescriptionHeight = startDescriptionHeight != targetDescriptionHeight
        val targetShowMoreText = showMoreLabel.text
        val swapsShowMoreText = isShowMoreInitiallyVisible &&
            isShowMoreFinallyVisible &&
            startShowMoreText != targetShowMoreText
        if (swapsShowMoreText) showMoreLabel.text = startShowMoreText

        expandedDescriptionLabel.isVisible = startExpandedAlpha > 0f || targetExpandedAlpha > 0f
        previewDescriptionLabel.isVisible = startPreviewAlpha > 0f || targetPreviewAlpha > 0f
        showMoreLabel.isVisible = isShowMoreInitiallyVisible || isShowMoreFinallyVisible
        arrowIcon.isVisible = startArrowAlpha > 0f || targetArrowAlpha > 0f
        expandedHeight = targetContentHeight
        contentView.updateLayoutParams {
            height = max(startContentHeight, targetContentHeight)
        }
        val isExpanding = targetHeight >= startHeight

        fun lerp(start: Float, end: Float, fraction: Float) = start + (end - start) * fraction
        fun lerp(start: Int, end: Int, fraction: Float) =
            (start + (end - start) * fraction).roundToInt()

        fun crossfade(start: Float, end: Float, fraction: Float) = if (end >= start) {
            lerp(start, end, (fraction * 2f).coerceAtMost(1f))
        } else {
            lerp(start, end, (fraction * 2f - 1f).coerceAtLeast(0f))
        }

        val animator = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(0f)
            setMinimumVisibleChange(DynamicAnimation.MIN_VISIBLE_CHANGE_SCALE)
            spring = SpringForce(1f).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                val fraction = value.coerceIn(0f, 1f)
                setExpansionProgress(lerp(startProgress, targetProgress, fraction))
                expandedDescriptionLabel.alpha =
                    crossfade(startExpandedAlpha, targetExpandedAlpha, fraction)
                previewDescriptionLabel.alpha =
                    crossfade(startPreviewAlpha, targetPreviewAlpha, fraction)
                collapsedDescriptionLabel.alpha =
                    crossfade(startCollapsedAlpha, targetCollapsedAlpha, fraction)
                arrowIcon.alpha = lerp(startArrowAlpha, targetArrowAlpha, fraction)
                showMoreLabel.alpha = lerp(startShowMoreAlpha, targetShowMoreAlpha, fraction)
                if (swapsShowMoreText) {
                    if (fraction >= 0.5f) showMoreLabel.text = targetShowMoreText
                    showMoreLabel.alpha *= abs(1f - fraction * 2f)
                }
                if (animatesDescriptionHeight) {
                    val descriptionHeight =
                        lerp(startDescriptionHeight, targetDescriptionHeight, fraction)
                    descriptionContainer.updateLayoutParams { height = descriptionHeight }
                    descriptionContainer.bottomFadeStrength =
                        (
                            (fullDescriptionHeight - descriptionHeight).toFloat() /
                                descriptionContainer.verticalFadingEdgeLength
                            ).coerceIn(0f, 1f) * expandedDescriptionLabel.alpha
                }
                showMoreLabel.updateLayoutParams {
                    height = lerp(startShowMoreHeight, targetShowMoreHeight, fraction)
                }
                setContainerHeight(
                    lerp(startHeight, targetHeight, fraction),
                    notify = true,
                    isExpanding = isExpanding
                )
            }
            addEndListener { animation, canceled, _, _ ->
                if (heightAnimator !== animation) return@addEndListener
                heightAnimator = null
                descriptionContainer.updateLayoutParams { height = WRAP_CONTENT }
                descriptionContainer.bottomFadeStrength = 0f
                showMoreLabel.updateLayoutParams { height = WRAP_CONTENT }
                showMoreLabel.text = targetShowMoreText
                if (canceled) return@addEndListener
                expandedDescriptionLabel.isVisible = isExpandedFinallyVisible
                previewDescriptionLabel.isVisible = isPreviewFinallyVisible
                showMoreLabel.isVisible = isShowMoreFinallyVisible
                arrowIcon.isVisible = hasBalance
                arrowIcon.alpha = 1f
                showMoreLabel.alpha = 1f
                setExpansionProgress(targetProgress)
                contentView.updateLayoutParams { height = targetContentHeight }
                setContainerHeight(targetHeight, notify = true, isExpanding = isExpanding)
            }
        }
        heightAnimator = animator
        animator.start()
    }

    private fun applyDescriptionMode() {
        val showsFullDescription = hasBalance || WGlobalStorage.getIsTokenInfoExpanded()
        fullDescriptionProgress = if (showsFullDescription) 1f else 0f
        val isDetails = state is TokenVM.TokenInfoState.Details
        if (isDetails) {
            expandedDescriptionLabel.isVisible = showsFullDescription
            previewDescriptionLabel.isVisible = !showsFullDescription
        } else {
            previewDescriptionLabel.isVisible = false
        }
        val exposesMarketDescription = isDetails && !hasBalance
        expandedDescriptionLabel.importantForAccessibility =
            if (exposesMarketDescription && showsFullDescription) {
                IMPORTANT_FOR_ACCESSIBILITY_AUTO
            } else {
                IMPORTANT_FOR_ACCESSIBILITY_NO
            }
        previewDescriptionLabel.importantForAccessibility =
            if (exposesMarketDescription && !showsFullDescription) {
                IMPORTANT_FOR_ACCESSIBILITY_AUTO
            } else {
                IMPORTANT_FOR_ACCESSIBILITY_NO
            }
        collapsedDescriptionLabel.importantForAccessibility =
            if (exposesMarketDescription) {
                IMPORTANT_FOR_ACCESSIBILITY_NO
            } else {
                IMPORTANT_FOR_ACCESSIBILITY_AUTO
            }
        showMoreLabel.text =
            LocaleController.getString(if (showsFullDescription) "Show Less" else "Show More")
    }

    private fun updateShowMoreVisibility() {
        showMoreLabel.isVisible = !hasBalance &&
            (state as? TokenVM.TokenInfoState.Details)?.info?.displayDescription != null &&
            fullDescriptionLineCount() > MARKET_DESCRIPTION_MAX_LINES
    }

    private fun fullDescriptionLineCount(): Int {
        measureFullDescription()
        return expandedDescriptionLabel.lineCount
    }

    private fun measureFullDescription() {
        expandedDescriptionLabel.measure(
            View.MeasureSpec.makeMeasureSpec(containerView.width - 40.dp, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
    }

    private fun setExpansionProgress(progress: Float) {
        expansionProgress = progress
        expandedDescriptionLabel.alpha = progress * fullDescriptionProgress
        previewDescriptionLabel.alpha = progress * (1f - fullDescriptionProgress)
        collapsedDescriptionLabel.alpha = 1f - progress
        arrowIcon.rotation = 90f + 180f * progress
        arrowIcon.translationY = -13.dp * progress
        detailsContainer.alpha = progress
    }

    private fun setContainerHeight(height: Int, notify: Boolean, isExpanding: Boolean) {
        if (containerView.layoutParams.height == height) return
        containerView.updateLayoutParams {
            this.height = height
        }
        if (notify) {
            onHeightChange(isExpanding, height)
        }
    }

    private fun updateExpandedHeight() {
        if (containerView.width == 0) {
            if (!isExpandedHeightUpdatePending) {
                isExpandedHeightUpdatePending = true
                containerView.doOnLayout {
                    isExpandedHeightUpdatePending = false
                    if (state != null && containerView.width > 0) updateExpandedHeight()
                }
            }
            return
        }
        val measuredHeight = measureExpandedHeight() ?: return
        if (contentView.layoutParams.height != measuredHeight) {
            contentView.updateLayoutParams {
                height = measuredHeight
            }
        }
        expandedHeight = measuredHeight
        if (isExpanded && heightAnimator == null && descriptionToggleAnimator == null) {
            setContainerHeight(expandedHeight, notify = true, isExpanding = true)
        }
    }

    private fun measureExpandedHeight(): Int? {
        if (containerView.width == 0) return null
        updateShowMoreVisibility()
        contentView.measure(
            View.MeasureSpec.makeMeasureSpec(containerView.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        return max(contentView.measuredHeight, COLLAPSED_HEIGHT_DP.dp)
    }

    private fun updateHeaderAccessibility() {
        val info = LocaleController.getString("Info")
        headerView.isClickable = state is TokenVM.TokenInfoState.Details && hasBalance
        headerView.isFocusable = headerView.isClickable
        headerView.contentDescription = if (headerView.isClickable) {
            val expandedState = LocaleController.getString(
                if (isExpanded) "Expanded" else "Collapsed"
            )
            val hint = LocaleController.getString(
                if (isExpanded) "\$token_info_collapse_hint" else "\$token_info_expand_hint"
            )
            "$info, $expandedState. $hint"
        } else {
            info
        }
    }

    override val isTinted = true

    override fun updateTheme() {
        descriptionToggleAnimator?.cancel()
        descriptionToggleAnimator = null
        setBackgroundColor(WColor.SecondaryBackground.color)
        containerView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            clipToBounds = true
        )
        titleLabel.setTextColor(WColor.SecondaryText.color)
        val descriptionColor =
            if (
                (state as? TokenVM.TokenInfoState.Details)?.info?.displayDescription != null
            ) {
                WColor.PrimaryText.color
            } else {
                WColor.SecondaryText.color
            }
        expandedDescriptionLabel.setTextColor(descriptionColor)
        collapsedDescriptionLabel.setTextColor(descriptionColor)
        previewDescriptionLabel.setTextColor(descriptionColor)
        showMoreLabel.setTextColor(WColor.Tint.color)
        arrowIcon.setColorFilter(WColor.SecondaryText.color, PorterDuff.Mode.SRC_IN)
        skeletonIndicator.setBackgroundColor(WColor.SecondaryBackground.color, 4.dp.toFloat())
        skeletonView.updateTheme()

        detailsContainer.removeAllViews()
        translationAttributionLabel = null
        volumeBarView = null
        (state as? TokenVM.TokenInfoState.Details)?.let { details ->
            val description = if (isShowingOriginalDescription) {
                details.info.originalDescriptionText
            } else {
                details.info.displayDescription
            } ?: displayDescription(details.info)
            expandedDescriptionLabel.text = description
            expandedDescriptionLabel.contentDescription = description
            collapsedDescriptionLabel.text = description
            previewDescriptionLabel.text = description
            updateDescriptionDirection(details.info)
            buildDetails(details.info)
        }
        pendingHeightUpdateRunnable?.let(::removeCallbacks)
        Runnable {
            pendingHeightUpdateRunnable = null
            updateExpandedHeight()
        }.also {
            pendingHeightUpdateRunnable = it
            post(it)
        }
    }

    private fun buildDetails(info: MApiTokenDetails.TokenInfo) {
        if (info.localizedDescriptionText != null &&
            info.originalDescriptionText != null
        ) {
            val attributionView = createTranslationAttributionView(info)
            translationAttributionLabel = attributionView
            detailsContainer.addView(
                attributionView,
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    marginStart = 20.dp
                    marginEnd = 20.dp
                    bottomMargin = 12.dp
                }
            )
        }

        val links = displayLinks(info)
        if (links.isNotEmpty()) {
            detailsContainer.addView(
                createLinksView(links),
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    marginStart = 20.dp
                    marginEnd = 20.dp
                    topMargin = 4.dp
                    bottomMargin = 13.dp
                }
            )
        }

        val supply = supplyDetails(info)
        fun addRow(view: View) {
            detailsContainer.addView(view)
        }

        info.marketCap?.let {
            addRow(
                createDetailRow(
                    LocaleController.getString("Market Cap"),
                    LocaleController.getString("\$token_info_market_cap_hint"),
                    formatCurrency(it)
                )
            )
        }
        supply?.let {
            addRow(createDetailRow(it.title, it.hint, it.value))
        }
        info.createdAt?.let(::formatCreatedAt)?.let {
            addRow(createDetailRow(LocaleController.getString("Created"), null, it))
        }
        info.volume24h?.let {
            addRow(createVolumeView(it))
        }
    }

    private fun createTranslationAttributionView(info: MApiTokenDetails.TokenInfo): WLabel {
        val attributionText = createTranslationAttributionText(info)
        return WLabel(context).apply {
            setStyle(13f)
            setTextColor(WColor.SecondaryText.color)
            textDirection = if (LocaleController.isRTL) {
                View.TEXT_DIRECTION_RTL
            } else {
                View.TEXT_DIRECTION_LTR
            }
            movementMethod = LinkMovementMethod.getInstance()
            highlightColor = Color.TRANSPARENT
            text = attributionText
            contentDescription = attributionText.toString()
            isFocusable = true
            isClickable = true
            setOnClickListener { toggleDescription(info) }
        }
    }

    private fun createTranslationAttributionText(
        info: MApiTokenDetails.TokenInfo
    ): SpannableStringBuilder {
        val action = LocaleController.getString(
            if (isShowingOriginalDescription) "Show Translation" else "Show Original"
        )
        return SpannableStringBuilder().apply {
            append(
                LocaleController.getString(
                    if (isShowingOriginalDescription) {
                        "Original Text"
                    } else {
                        "Translated from English"
                    }
                )
            )
            append(" ")
            val actionStart = length
            append(action)
            setSpan(
                WClickableSpan("") { toggleDescription(info) },
                actionStart,
                length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    private fun toggleDescription(info: MApiTokenDetails.TokenInfo) {
        if (descriptionToggleAnimator != null || heightAnimator != null) return
        val showOriginalDescription = !isShowingOriginalDescription
        val description = if (showOriginalDescription) {
            info.originalDescriptionText
        } else {
            info.localizedDescriptionText
        } ?: return
        isShowingOriginalDescription = showOriginalDescription
        val attributionText = createTranslationAttributionText(info)

        if (!WGlobalStorage.getAreAnimationsActive()) {
            applyDescription(info, description, attributionText)
            updateExpandedHeight()
            return
        }

        val previousExpandedDescription = expandedDescriptionLabel.text
        val previousExpandedContentDescription = expandedDescriptionLabel.contentDescription
        val previousCollapsedDescription = collapsedDescriptionLabel.text
        val previousAttribution = translationAttributionLabel?.text
        val previousAttributionContentDescription =
            translationAttributionLabel?.contentDescription
        val previousTextDirection = expandedDescriptionLabel.textDirection
        val previousGravity = expandedDescriptionLabel.gravity
        val startHeaderHeight = headerView.height
        applyDescription(info, description, attributionText)
        val targetHeight = measureExpandedHeight()
        val targetHeaderHeight = headerView.measuredHeight
        expandedDescriptionLabel.text = previousExpandedDescription
        expandedDescriptionLabel.contentDescription = previousExpandedContentDescription
        collapsedDescriptionLabel.text = previousCollapsedDescription
        previewDescriptionLabel.text = previousCollapsedDescription
        translationAttributionLabel?.text = previousAttribution
        translationAttributionLabel?.contentDescription =
            previousAttributionContentDescription
        expandedDescriptionLabel.textDirection = previousTextDirection
        collapsedDescriptionLabel.textDirection = previousTextDirection
        previewDescriptionLabel.textDirection = previousTextDirection
        expandedDescriptionLabel.gravity = previousGravity
        collapsedDescriptionLabel.gravity = previousGravity
        previewDescriptionLabel.gravity = previousGravity
        if (targetHeight == null) {
            applyDescription(info, description, attributionText)
            updateExpandedHeight()
            return
        }

        val startHeight = containerView.height.coerceAtLeast(COLLAPSED_HEIGHT_DP.dp)
        val isGrowing = targetHeight > startHeight
        expandedHeight = targetHeight
        contentView.updateLayoutParams { height = targetHeight }
        var hasSwappedText = false
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                if (!hasSwappedText && progress >= 0.5f) {
                    hasSwappedText = true
                    applyDescription(info, description, attributionText)
                }
                val textAlpha = when {
                    progress < 0.4f -> 1f - progress / 0.4f
                    progress > 0.6f -> (progress - 0.6f) / 0.4f
                    else -> 0f
                }
                expandedDescriptionLabel.alpha = textAlpha
                previewDescriptionLabel.alpha = textAlpha
                translationAttributionLabel?.alpha = textAlpha
                val headerHeightChange = (targetHeaderHeight - startHeaderHeight).toFloat()
                detailsContainer.translationY = if (hasSwappedText) {
                    -headerHeightChange * (1f - progress)
                } else {
                    headerHeightChange * progress
                }
                val height = (startHeight + (targetHeight - startHeight) * progress)
                    .roundToInt()
                setContainerHeight(height, notify = true, isExpanding = isGrowing)
            }
            addListener(object : AnimatorListenerAdapter() {
                private var isCanceled = false

                override fun onAnimationCancel(animation: Animator) {
                    isCanceled = true
                }

                override fun onAnimationEnd(animation: Animator) {
                    if (descriptionToggleAnimator !== animation) return
                    descriptionToggleAnimator = null
                    if (isCanceled) {
                        if (!hasSwappedText) {
                            applyDescription(info, description, attributionText)
                        }
                        setExpansionProgress(if (isExpanded) 1f else 0f)
                        translationAttributionLabel?.alpha = 1f
                        detailsContainer.translationY = 0f
                        return
                    }
                    if (!hasSwappedText) {
                        applyDescription(info, description, attributionText)
                    }
                    setExpansionProgress(1f)
                    translationAttributionLabel?.alpha = 1f
                    detailsContainer.translationY = 0f
                    setContainerHeight(targetHeight, notify = true, isExpanding = isGrowing)
                }
            })
        }
        descriptionToggleAnimator = animator
        animator.start()
    }

    private fun applyDescription(
        info: MApiTokenDetails.TokenInfo,
        description: String,
        attributionText: SpannableStringBuilder
    ) {
        expandedDescriptionLabel.text = description
        expandedDescriptionLabel.contentDescription = description
        collapsedDescriptionLabel.text = description
        previewDescriptionLabel.text = description
        translationAttributionLabel?.text = attributionText
        translationAttributionLabel?.contentDescription = attributionText.toString()
        updateDescriptionDirection(info)
    }

    private fun updateDescriptionDirection(info: MApiTokenDetails.TokenInfo) {
        val isRtl = LocaleController.isRTL &&
            (
                info.displayDescription == null ||
                    (!isShowingOriginalDescription && info.localizedDescriptionText != null)
                )
        setDescriptionDirection(isRtl)
    }

    private fun displayDescription(info: MApiTokenDetails.TokenInfo): String =
        info.displayDescription
            ?: LocaleController.getString("\$token_info_no_description")

    private fun setDescriptionDirection(isRtl: Boolean) {
        val textDirection = if (isRtl) View.TEXT_DIRECTION_RTL else View.TEXT_DIRECTION_LTR
        val gravity = if (isRtl) Gravity.RIGHT else Gravity.LEFT
        expandedDescriptionLabel.textDirection = textDirection
        collapsedDescriptionLabel.textDirection = textDirection
        previewDescriptionLabel.textDirection = textDirection
        expandedDescriptionLabel.gravity = gravity
        collapsedDescriptionLabel.gravity = gravity
        previewDescriptionLabel.gravity = gravity
    }

    private fun createLinksView(links: List<DisplayLink>): WView {
        val flow = Flow(context).apply {
            id = generateViewId()
            setWrapMode(Flow.WRAP_CHAIN)
            setHorizontalStyle(Flow.CHAIN_PACKED)
            setHorizontalAlign(Flow.HORIZONTAL_ALIGN_START)
            setHorizontalBias(0f)
            setHorizontalGap(8.dp)
            setVerticalGap(8.dp)
        }
        return WView(context).apply {
            val chips = links.map { link ->
                createLinkChip(link).also {
                    addView(it, LayoutParams(WRAP_CONTENT, (33.5f.dp).roundToInt()))
                }
            }
            addView(flow, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            flow.referencedIds = chips.map { it.id }.toIntArray()
            setConstraints { allEdges(flow) }
        }
    }

    private fun createLinkChip(link: DisplayLink): LinearLayout {
        val startPadding = when (link.icon) {
            IconsR.drawable.ic_telegram, IconsR.drawable.ic_world -> 7.dp
            else -> 10.dp
        }
        val iconSize = when (link.icon) {
            IconsR.drawable.ic_telegram, IconsR.drawable.ic_world -> 25.dp
            else -> 20.dp
        }
        val icon = AppCompatImageView(context).apply {
            setImageResource(link.icon)
            setColorFilter(WColor.PrimaryText.color, PorterDuff.Mode.SRC_IN)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
        }
        val label = WLabel(context).apply {
            setStyle(14f, WFont.Medium)
            setTextColor(WColor.PrimaryText.color)
            text = link.title
            gravity = Gravity.CENTER_VERTICAL
            setSingleLine()
        }
        return LinearLayout(context).apply {
            id = generateViewId()
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingLocalized(startPadding, 0, (11.5f.dp).roundToInt(), 0)
            addView(icon, LinearLayout.LayoutParams(iconSize, iconSize))
            addView(
                label,
                LinearLayout.LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
                    marginStart = 4.dp
                }
            )
            background = WRippleDrawable.create(16.75f.dp).apply {
                backgroundColor = WColor.SecondaryBackground.color
                rippleColor = WColor.BackgroundRipple.color
            }
            contentDescription =
                "${link.title}. ${LocaleController.getString("\$token_info_open_in_browser_hint")}"
            setOnClickListener {
                WalletCore.notifyEvent(WalletEvent.OpenUrl(link.url))
            }
        }
    }

    private fun createDetailRow(title: String, hint: String?, value: String): WView {
        val valueLabel = WLabel(context).apply {
            setStyle(17f)
            setTextColor(WColor.PrimaryText.color)
            text = value
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            setSingleLine()
        }
        return createDetailRow(title, hint, valueLabel)
    }

    private fun createDetailRow(title: String, hint: String?, valueView: View): WView {
        val titleLabel = WLabel(context).apply {
            setStyle(17f)
            setTextColor(WColor.SecondaryText.color)
            text = title
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        val infoButton = hint?.let {
            AppCompatImageView(context).apply {
                id = generateViewId()
                setImageResource(IconsR.drawable.ic_info_24)
                setColorFilter(WColor.SecondaryText.color, PorterDuff.Mode.SRC_IN)
                imageAlpha = 128
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                contentDescription = hint
                setOnClickListener { onShowInfo(title, hint) }
            }
        }
        if (valueView.id == NO_ID) {
            valueView.id = generateViewId()
        }

        return WView(context).apply {
            addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            infoButton?.let { addView(it, LayoutParams(24.dp, 24.dp)) }
            addView(valueView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            setConstraints {
                toEnd(valueView, 20f)
                toCenterY(valueView)
                toStart(titleLabel, 20f)
                toCenterY(titleLabel)
                constrainedWidth(titleLabel.id, true)
                setHorizontalBias(titleLabel.id, 0f)
                if (infoButton != null) {
                    endToStart(titleLabel, valueView, 34f)
                    startToEnd(infoButton, titleLabel, 2f)
                    toCenterY(infoButton)
                } else {
                    endToStart(titleLabel, valueView, 8f)
                }
            }
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, 50.dp)
        }
    }

    private fun createVolumeView(volume: MApiTokenDetails.Volume): LinearLayout {
        val shouldShowVolumeBar = volume.buy > 0.0 || volume.sell > 0.0
        val valueGroup = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        valueGroup.addView(
            WLabel(context).apply {
                setStyle(17f)
                setTextColor(WColor.PrimaryText.color)
                text = formatCurrency(volume.buy + volume.sell)
                gravity = Gravity.CENTER_VERTICAL
                setSingleLine()
            },
            LinearLayout.LayoutParams(WRAP_CONTENT, MATCH_PARENT)
        )
        volume.percentChange?.let { percentChange ->
            valueGroup.addView(
                WLabel(context).apply {
                    setStyle(14f)
                    setTextColor(
                        if (percentChange >= 0) WColor.Buy.color else WColor.Sell.color
                    )
                    text = formatPercent(percentChange)
                    gravity = Gravity.CENTER_VERTICAL
                    setSingleLine()
                },
                LinearLayout.LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
                    marginStart = 6.dp
                }
            )
        }

        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(
                createDetailRow(
                    LocaleController.getString("Volume · 24h"),
                    LocaleController.getString("\$token_info_volume_hint"),
                    valueGroup
                ),
                LinearLayout.LayoutParams(MATCH_PARENT, 50.dp)
            )
            if (shouldShowVolumeBar) {
                val volumeBar = VolumeBarView(context).also {
                    it.configure(volume.buy, volume.sell)
                    volumeBarView = it
                }
                addView(
                    volumeBar,
                    LinearLayout.LayoutParams(MATCH_PARENT, 26.dp).apply {
                        marginStart = 20.dp
                        marginEnd = 20.dp
                        bottomMargin = 16.dp
                    }
                )
            }
            layoutParams = LinearLayout.LayoutParams(
                MATCH_PARENT,
                if (shouldShowVolumeBar) 92.dp else 50.dp
            )
        }
    }

    private fun supplyDetails(info: MApiTokenDetails.TokenInfo): SupplyDetails? {
        val circulating = info.supply?.circulating
        val total = info.supply?.total
        val hint = LocaleController.getString("\$token_info_supply_hint")
        return when {
            circulating != null && total != null -> SupplyDetails(
                LocaleController.getString("Circulating / Total Supply"),
                hint,
                "${formatCompactNumber(circulating)} / ${formatCompactNumber(total)}"
            )

            circulating != null -> SupplyDetails(
                LocaleController.getString("Circulating Supply"),
                null,
                formatCompactNumber(circulating)
            )

            total != null -> SupplyDetails(
                LocaleController.getString("Total Supply"),
                null,
                formatCompactNumber(total)
            )

            else -> null
        }
    }

    private fun displayLinks(info: MApiTokenDetails.TokenInfo): List<DisplayLink> {
        val links = buildList {
            info.links.orEmpty().forEach { link ->
                val type = link.type?.lowercase()
                add(
                    DisplayLink(
                        link.url,
                        when (type) {
                            "x" -> "X"
                            "telegram" -> "Telegram"
                            else -> "Website"
                        },
                        when (type) {
                            "x" -> IconsR.drawable.ic_x_20
                            "telegram" -> IconsR.drawable.ic_telegram
                            else -> IconsR.drawable.ic_world
                        }
                    )
                )
            }
        }
        return links
            .filter { it.url.isNotBlank() }
            .distinctBy { it.url }
    }

    private fun formatCurrency(value: Double) = "\$${formatCompactNumber(value)}"

    private fun formatPercent(value: Double): String {
        val formatter = DecimalFormat("+0.##;-0.##", DecimalFormatSymbols(Locale.US))
        return (if (LocaleController.isRTL) "\u202D" else "") + formatter.format(value) + "%"
    }

    private fun formatCreatedAt(rawValue: String): String? {
        val position = ParsePosition(0)
        val formatter = SimpleDateFormat(CREATED_AT_FORMAT, Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
            isLenient = false
        }
        val date = formatter.parse(rawValue, position)
            ?.takeIf { position.index == rawValue.length }
            ?: return null
        val pattern =
            if (WDateFormatter.isDayBeforeMonth(WGlobalStorage.getLangCode())) {
                "d MMM yyyy"
            } else {
                "MMM d, yyyy"
            }
        return WDateFormatter.of(pattern, WGlobalStorage.getLangCode()).format(date)
    }

    fun onDestroy() {
        pendingStateRenderRunnable?.let(::removeCallbacks)
        pendingStateRenderRunnable = null
        pendingHeightUpdateRunnable?.let(::removeCallbacks)
        pendingHeightUpdateRunnable = null
        heightAnimator?.cancel()
        heightAnimator = null
        descriptionToggleAnimator?.cancel()
        descriptionToggleAnimator = null
        skeletonView.onDestroy()
        headerView.setOnClickListener(null)
        detailsContainer.removeAllViews()
        translationAttributionLabel = null
        state = null
    }

    private data class SupplyDetails(val title: String, val hint: String?, val value: String)

    private data class DisplayLink(val url: String, val title: String, val icon: Int)

    private inner class VolumeBarView(context: android.content.Context) :
        LinearLayout(context),
        WThemedView {
        private var hasBuyVolume = false
        private var hasSellVolume = false

        private val buyLabel = WLabel(context).apply {
            setStyle(13f, WFont.Medium)
            setTextColor(Color.WHITE)
            gravity =
                (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT) or
                Gravity.CENTER_VERTICAL
            setPaddingLocalized(10.dp, 0, 8.dp, 0)
            setSingleLine()
        }
        private val sellLabel = WLabel(context).apply {
            setStyle(13f, WFont.Medium)
            setTextColor(Color.WHITE)
            gravity =
                (if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT) or
                Gravity.CENTER_VERTICAL
            setPaddingLocalized(8.dp, 0, 10.dp, 0)
            setSingleLine()
        }

        init {
            orientation = HORIZONTAL
            addView(
                buyLabel,
                LinearLayout.LayoutParams(WRAP_CONTENT, MATCH_PARENT, 1f).apply {
                    marginEnd = 4.dp
                }
            )
            addView(sellLabel, LinearLayout.LayoutParams(WRAP_CONTENT, MATCH_PARENT, 1f))
        }

        fun configure(buy: Double, sell: Double) {
            val safeBuy = buy.coerceAtLeast(0.0)
            val safeSell = sell.coerceAtLeast(0.0)
            val total = max(safeBuy + safeSell, 1.0)
            hasBuyVolume = safeBuy > 0.0
            hasSellVolume = safeSell > 0.0
            buyLabel.visibility = if (hasBuyVolume) VISIBLE else GONE
            sellLabel.visibility = if (hasSellVolume) VISIBLE else GONE
            buyLabel.updateLayoutParams<LinearLayout.LayoutParams> {
                weight = (safeBuy / total).toFloat()
                marginEnd = if (hasBuyVolume && hasSellVolume) 4.dp else 0
            }
            sellLabel.updateLayoutParams<LinearLayout.LayoutParams> {
                weight = (safeSell / total).toFloat()
            }
            buyLabel.text = formatCurrency(safeBuy)
            sellLabel.text = formatCurrency(safeSell)
            updateTheme()
        }

        override fun updateTheme() {
            val outerRadius = 13.dp.toFloat()
            val innerRadius = 3.dp.toFloat()
            val buyTrailingRadius = if (hasSellVolume) innerRadius else outerRadius
            val sellLeadingRadius = if (hasBuyVolume) innerRadius else outerRadius
            buyLabel.setBackgroundColorLocalized(
                WColor.Buy.color,
                outerRadius,
                buyTrailingRadius,
                buyTrailingRadius,
                outerRadius
            )
            sellLabel.setBackgroundColorLocalized(
                WColor.Sell.color,
                sellLeadingRadius,
                outerRadius,
                outerRadius,
                sellLeadingRadius
            )
        }
    }
}
