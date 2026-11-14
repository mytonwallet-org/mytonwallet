package org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.PorterDuff
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.doOnLayout
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.DynamicAnimation
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uiassets.viewControllers.token.helpers.formatCompactNumber
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WBottomFadingFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.setCardPadding
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.fundingText
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset

@SuppressLint("ViewConstructor")
class FuturesPositionInfoCell(
    context: Context,
    private val onShowInfo: (title: String, text: String) -> Unit
) : WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private var isExpanded = WGlobalStorage.getIsTokenInfoExpanded(default = false)
    private var hasDescription = false
    private var isConfigured = false
    private var description: String? = null

    /** Without a position the card stays expanded and offers Show More, like token info without a balance. */
    private var isCollapsible = true
    private var showsFullDescription = false
    private var isDescriptionLong = false
    private var expansionProgress = 0f
    private var heightAnimator: SpringAnimation? = null

    private val ripple = WRippleDrawable.create(ViewConstants.BLOCK_RADIUS.dp)
    private val cardView = WFrameLayout(context).apply {
        id = generateViewId()
    }
    private val contentView = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
    }
    private val headerView = WView(context)

    private val titleLabel = WLabel(context).apply {
        setStyle(14f)
        text = LocaleController.getString("Info")
    }

    private val collapsedDescriptionLabel = WLabel(context).apply {
        setStyle(16f)
        ellipsize = TextUtils.TruncateAt.END
        maxLines = 1
    }

    private val expandedDescriptionLabel = WLabel(context).apply {
        setStyle(16f)
    }

    private val descriptionView = WBottomFadingFrameLayout(context).apply {
        addView(collapsedDescriptionLabel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(expandedDescriptionLabel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private val showMoreLabel = WLabel(context).apply {
        setStyle(16f)
        visibility = GONE
        setOnClickListener { toggleFullDescription() }
    }

    private val descriptionColumn = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(descriptionView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(showMoreLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    private val arrowIcon = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageResource(IconsR.drawable.ic_arrow_right_24)
        rotation = COLLAPSED_ROTATION
    }

    private val rowsView = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
    }

    init {
        headerView.background = ripple
        headerView.addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        headerView.addView(descriptionColumn, LayoutParams(0, WRAP_CONTENT))
        headerView.addView(arrowIcon, LayoutParams(24.dp, 24.dp))
        headerView.setConstraints {
            toTop(titleLabel, 10f)
            toStart(titleLabel, 20f)
            endToStart(titleLabel, arrowIcon, 8f)
            topToBottom(descriptionColumn, titleLabel, 2f)
            startToStart(descriptionColumn, titleLabel)
            endToStart(descriptionColumn, arrowIcon, 8f)
            toBottom(descriptionColumn, 14f)
            toTop(arrowIcon, 20f)
            toEnd(arrowIcon, 16f)
        }
        headerView.setOnClickListener { if (isCollapsible) toggle() }

        contentView.addView(headerView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        contentView.addView(rowsView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        cardView.addView(contentView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(cardView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            allEdges(cardView)
        }
    }

    fun configure(asset: MApiPerpsListedAsset?, description: String?, isCollapsible: Boolean) {
        setCardPadding(ViewConstants.GAP.dp)
        updateRows(asset)
        val text = description?.takeIf { it.isNotBlank() }
        if (isConfigured &&
            text == this.description &&
            isCollapsible == this.isCollapsible
        ) {
            return
        }
        val animatesModeChange = isConfigured &&
            isCollapsible != this.isCollapsible &&
            isAttachedToWindow &&
            cardView.height > 0 &&
            WGlobalStorage.getAreAnimationsActive()
        isConfigured = true
        this.description = text
        val modeChanged = this.isCollapsible != isCollapsible
        this.isCollapsible = isCollapsible
        if (!isCollapsible) {
            isExpanded = true
            showsFullDescription = WGlobalStorage.getIsTokenInfoExpanded()
        } else if (modeChanged) {
            isExpanded = WGlobalStorage.getIsTokenInfoExpanded(default = false)
        }
        hasDescription = text != null
        collapsedDescriptionLabel.text = text
        collapsedDescriptionLabel.maxLines = if (isCollapsible) 1 else MARKET_DESCRIPTION_MAX_LINES
        expandedDescriptionLabel.text = text
        headerView.isClickable = hasDescription && isCollapsible
        if (!hasDescription) isDescriptionLong = false
        heightAnimator?.cancel()
        heightAnimator = null
        if (animatesModeChange) {
            measureShowMore()
            animateToTarget()
            updateTheme()
            return
        }
        setExpansionProgress(targetProgress)
        applyFinalVisibility()
        descriptionView.updateLayoutParams { height = WRAP_CONTENT }
        descriptionView.bottomFadeStrength = 0f
        showMoreLabel.alpha = 1f
        contentView.updateLayoutParams { height = WRAP_CONTENT }
        cardView.updateLayoutParams { height = WRAP_CONTENT }
        updateTheme()
        if (!isCollapsible) {
            descriptionColumn.doOnLayout { updateShowMore() }
        }
    }

    fun onDestroy() {
        heightAnimator?.cancel()
    }

    private fun updateRows(asset: MApiPerpsListedAsset?) {
        rowsView.removeAllViews()
        val rows = rows(asset)
        rows.forEachIndexed { index, row ->
            row.setLast(index == rows.lastIndex)
            rowsView.addView(row)
        }
    }

    /** Progress toward the full description: the card's expansion, or Show More without a position. */
    private val targetProgress: Float
        get() {
            val showsFull = if (isCollapsible) {
                isExpanded
            } else {
                showsFullDescription &&
                    isDescriptionLong
            }
            return if (showsFull) 1f else 0f
        }

    private fun updateShowMore() {
        measureShowMore()
        setExpansionProgress(targetProgress)
        applyFinalVisibility()
    }

    private fun measureShowMore() {
        isDescriptionLong = if (isCollapsible || !hasDescription || descriptionColumn.width == 0) {
            false
        } else {
            expandedDescriptionLabel.measure(
                MeasureSpec.makeMeasureSpec(descriptionColumn.width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            )
            expandedDescriptionLabel.lineCount > MARKET_DESCRIPTION_MAX_LINES
        }
    }

    private fun toggleFullDescription() {
        if (isCollapsible || !isDescriptionLong) return
        showsFullDescription = !showsFullDescription
        WGlobalStorage.setIsTokenInfoExpanded(showsFullDescription)
        animateFullDescription()
    }

    /** Resizes the description in place so the rows below follow it, as token info does. */
    private fun animateFullDescription() {
        heightAnimator?.cancel()
        heightAnimator = null
        val targetProgress = targetProgress
        if (!WGlobalStorage.getAreAnimationsActive() || descriptionView.width == 0) {
            setExpansionProgress(targetProgress)
            applyFinalVisibility()
            return
        }

        val startProgress = expansionProgress
        val startHeight = descriptionView.height
        val startShowMoreText = showMoreLabel.text
        val widthSpec = MeasureSpec.makeMeasureSpec(descriptionView.width, MeasureSpec.EXACTLY)
        val heightSpec = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        expandedDescriptionLabel.measure(widthSpec, heightSpec)
        collapsedDescriptionLabel.measure(widthSpec, heightSpec)
        val fullHeight = expandedDescriptionLabel.measuredHeight
        val targetHeight =
            if (targetProgress == 1f) fullHeight else collapsedDescriptionLabel.measuredHeight
        applyFinalVisibility()
        val targetShowMoreText = showMoreLabel.text
        showMoreLabel.text = startShowMoreText
        collapsedDescriptionLabel.visibility = VISIBLE
        expandedDescriptionLabel.visibility = VISIBLE
        descriptionView.updateLayoutParams { height = startHeight }

        fun crossfade(start: Float, end: Float, fraction: Float) = if (end >= start) {
            start + (end - start) * (fraction * 2f).coerceAtMost(1f)
        } else {
            start + (end - start) * (fraction * 2f - 1f).coerceAtLeast(0f)
        }

        heightAnimator = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(0f)
            setMinimumVisibleChange(DynamicAnimation.MIN_VISIBLE_CHANGE_SCALE)
            spring = SpringForce(1f).apply {
                stiffness = SPRING_STIFFNESS
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                val fraction = value.coerceIn(0f, 1f)
                setExpansionProgress(startProgress + (targetProgress - startProgress) * fraction)
                expandedDescriptionLabel.alpha =
                    crossfade(startProgress, targetProgress, fraction)
                collapsedDescriptionLabel.alpha =
                    crossfade(1f - startProgress, 1f - targetProgress, fraction)
                if (fraction >= 0.5f) showMoreLabel.text = targetShowMoreText
                showMoreLabel.alpha = abs(1f - fraction * 2f)
                val height = (startHeight + (targetHeight - startHeight) * fraction).roundToInt()
                descriptionView.updateLayoutParams { this.height = height }
                descriptionView.bottomFadeStrength =
                    ((fullHeight - height).toFloat() / descriptionView.verticalFadingEdgeLength)
                        .coerceIn(0f, 1f) * expandedDescriptionLabel.alpha
            }
            addEndListener { animation, _, _, _ ->
                if (heightAnimator !== animation) return@addEndListener
                heightAnimator = null
                descriptionView.updateLayoutParams { height = WRAP_CONTENT }
                descriptionView.bottomFadeStrength = 0f
                showMoreLabel.alpha = 1f
                setExpansionProgress(targetProgress)
                applyFinalVisibility()
            }
            start()
        }
    }

    private fun rows(asset: MApiPerpsListedAsset?) = listOfNotNull(
        asset?.context?.fundingText()?.let {
            row(
                "Funding Rate",
                it,
                hintKey = "\$perps_funding_rate_hint"
            )
        },
        asset?.let {
            row(
                "Max Leverage",
                "${it.maxLeverage}x",
                hintKey = "\$perps_max_leverage_hint"
            )
        },
        asset?.context?.dayNtlVlm?.toDoubleOrNull()?.let {
            row(
                "24h Volume",
                "\$${formatCompactNumber(it)}",
                hintKey = "\$perps_volume_24h_hint"
            )
        },
        asset?.context?.let { context ->
            val openInterest = context.openInterest?.toDoubleOrNull()
            val markPrice = context.markPx?.toDoubleOrNull()
            if (openInterest == null || markPrice == null) return@let null
            row(
                "Open Interest",
                "\$${formatCompactNumber(openInterest * markPrice)}",
                hintKey = "\$perps_open_interest_hint"
            )
        }
    )

    private fun row(key: String, value: CharSequence, hintKey: String) =
        KeyValueRowView(context, LocaleController.getString(key), value).apply {
            setHint { onShowInfo(this.key, LocaleController.getString(hintKey)) }
        }

    private fun toggle() {
        if (!hasDescription) return
        isExpanded = !isExpanded
        WGlobalStorage.setIsTokenInfoExpanded(isExpanded)
        animateToTarget()
    }

    private fun animateToTarget() {
        heightAnimator?.cancel()
        heightAnimator = null
        val targetProgress = targetProgress
        if (!WGlobalStorage.getAreAnimationsActive() || cardView.width == 0) {
            setExpansionProgress(targetProgress)
            applyFinalVisibility()
            return
        }

        val startHeight = cardView.height
        val startContentHeight = contentView.height
        val startProgress = expansionProgress
        applyFinalVisibility()
        contentView.updateLayoutParams { height = WRAP_CONTENT }
        contentView.measure(
            MeasureSpec.makeMeasureSpec(cardView.width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        val targetHeight = contentView.measuredHeight
        collapsedDescriptionLabel.visibility = VISIBLE
        expandedDescriptionLabel.visibility = VISIBLE
        rowsView.visibility = VISIBLE
        contentView.updateLayoutParams { height = max(startContentHeight, targetHeight) }
        cardView.updateLayoutParams { height = startHeight }

        heightAnimator = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(0f)
            setMinimumVisibleChange(DynamicAnimation.MIN_VISIBLE_CHANGE_SCALE)
            spring = SpringForce(1f).apply {
                stiffness = SPRING_STIFFNESS
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                val fraction = value.coerceIn(0f, 1f)
                setExpansionProgress(startProgress + (targetProgress - startProgress) * fraction)
                cardView.updateLayoutParams {
                    height = (startHeight + (targetHeight - startHeight) * fraction).roundToInt()
                }
            }
            addEndListener { animation, canceled, _, _ ->
                if (heightAnimator !== animation || canceled) return@addEndListener
                heightAnimator = null
                applyFinalVisibility()
                contentView.updateLayoutParams { height = WRAP_CONTENT }
                cardView.updateLayoutParams { height = WRAP_CONTENT }
            }
            start()
        }
    }

    private fun setExpansionProgress(progress: Float) {
        expansionProgress = progress
        collapsedDescriptionLabel.alpha = 1f - progress
        expandedDescriptionLabel.alpha = progress
        rowsView.alpha = if (hasDescription && isCollapsible) progress else 1f
        arrowIcon.rotation =
            COLLAPSED_ROTATION + (EXPANDED_ROTATION - COLLAPSED_ROTATION) * progress
        arrowIcon.translationY = -ARROW_EXPANDED_SHIFT.dp * progress
    }

    private fun applyFinalVisibility() {
        val showsFull = targetProgress == 1f
        descriptionColumn.isGone = !hasDescription
        arrowIcon.isGone = !hasDescription || !isCollapsible
        collapsedDescriptionLabel.visibility =
            if (showsFull) INVISIBLE else VISIBLE
        expandedDescriptionLabel.isGone = !showsFull
        rowsView.isGone = hasDescription && !isExpanded
        showMoreLabel.isGone = isCollapsible || !isDescriptionLong
        showMoreLabel.text =
            LocaleController.getString(if (showsFullDescription) "Show Less" else "Show More")
    }

    override fun updateTheme() {
        cardView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            clipToBounds = true
        )
        ripple.rippleColor = WColor.BackgroundRipple.color
        titleLabel.setTextColor(WColor.SecondaryText.color)
        collapsedDescriptionLabel.setTextColor(WColor.PrimaryText.color)
        expandedDescriptionLabel.setTextColor(WColor.PrimaryText.color)
        showMoreLabel.setTextColor(WColor.Tint.color)
        arrowIcon.setColorFilter(WColor.SecondaryText.color, PorterDuff.Mode.SRC_IN)
    }

    private companion object {
        const val COLLAPSED_ROTATION = 90f
        const val EXPANDED_ROTATION = 270f
        const val SPRING_STIFFNESS = 500f
        const val ARROW_EXPANDED_SHIFT = 13f
        const val MARKET_DESCRIPTION_MAX_LINES = 3
    }
}
