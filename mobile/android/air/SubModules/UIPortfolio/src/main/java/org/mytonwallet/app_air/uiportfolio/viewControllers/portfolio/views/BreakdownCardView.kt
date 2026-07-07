package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.views

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioBreakdownSlice
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class BreakdownCardView(
    context: Context,
    titleText: String,
    private val showLegend: Boolean,
    private val legendRowCount: Int = 10,
    private val emptyText: String? = null,
) : WView(context), WThemedView {

    private val titleLabel = WLabel(context).apply {
        id = generateViewId()
        text = titleText
        setStyle(14f, WFont.Medium)
        setTextColor(WColor.Tint)
    }
    private val cylinder = CylinderStackView(context).apply {
        id = generateViewId()
    }
    private val legend = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
    }
    private val emptyLabel = WLabel(context).apply {
        id = generateViewId()
        text = emptyText
        setStyle(14f, WFont.Regular)
        setTextColor(WColor.SecondaryText)
        gravity = Gravity.CENTER
        maxLines = 2
        visibility = GONE
    }
    val cardSkeletonPlaceholder = WBaseView(context).apply {
        id = generateViewId()
        alpha = 0f
        visibility = GONE
    }

    init {
        setPadding(16.dp, 16.dp, 16.dp, 14.dp)
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        val cylH = BreakdownSectionView.CYLINDER_HEIGHT_DP.dp
        addView(cylinder, LayoutParams(80.dp, cylH))
        if (showLegend) {
            addView(legend, LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        }
        if (emptyText != null) {
            addView(emptyLabel, LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        }
        addView(cardSkeletonPlaceholder, LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
        setConstraints {
            toTop(titleLabel)
            if (showLegend) toStart(titleLabel, 4f) else toCenterX(titleLabel)
            topToBottom(cylinder, titleLabel, 15f)
            if (showLegend) toStart(cylinder, 8f) else toCenterX(cylinder)
            toBottom(cylinder)
            if (showLegend) {
                toStart(legend, 112f)
                toEnd(legend, 8f)
                setHorizontalBias(legend.id, 0f)
                topToTop(legend, cylinder)
                bottomToBottom(legend, cylinder)
            }
            if (emptyText != null) {
                toStart(emptyLabel, 16f)
                toEnd(emptyLabel, 16f)
                topToBottom(emptyLabel, titleLabel, 15f)
                toBottom(emptyLabel)
            }
            toTop(cardSkeletonPlaceholder, 36f)
            toCenterX(cardSkeletonPlaceholder)
            toBottom(cardSkeletonPlaceholder)
        }
    }

    fun render(slices: List<PortfolioBreakdownSlice>) {
        if (slices.isEmpty()) {
            cylinder.visibility = INVISIBLE
            if (showLegend) legend.visibility = INVISIBLE
            if (emptyText != null) emptyLabel.visibility = VISIBLE
            return
        }
        if (emptyText != null) emptyLabel.visibility = GONE
        cylinder.visibility = VISIBLE
        cylinder.setSlices(slices)
        if (showLegend) {
            legend.visibility = VISIBLE
            renderLegend(slices)
        }
    }

    fun fadeInLegend() {
        if (!showLegend || legend.visibility != VISIBLE) return
        legend.alpha = 0f
        legend.fadeIn()
    }

    fun maskTarget(): Pair<android.view.View, Float> =
        cardSkeletonPlaceholder to ViewConstants.BLOCK_RADIUS.dp

    fun crossFadeTargets(): List<android.view.View> =
        if (showLegend) listOf(cylinder, legend) else listOf(cylinder)

    fun showPlaceholders(animated: Boolean = false) {
        cylinder.visibility = VISIBLE
        if (showLegend) legend.visibility = VISIBLE
        cardSkeletonPlaceholder.visibility = VISIBLE
        if (animated) {
            cardSkeletonPlaceholder.fadeIn()
        } else {
            cardSkeletonPlaceholder.alpha = 1f
        }
    }

    fun hidePlaceholders() {
        cardSkeletonPlaceholder.fadeOut { cardSkeletonPlaceholder.visibility = INVISIBLE }
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        cylinder.updateTheme()
        cardSkeletonPlaceholder.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp,
        )
    }

    @SuppressLint("SetTextI18n")
    private fun renderLegend(slices: List<PortfolioBreakdownSlice>) {
        legend.removeAllViews()
        slices.take(legendRowCount).forEachIndexed { index, slice ->
            val rowView = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            val label = WLabel(context).apply {
                text = slice.label
                setStyle(14f, WFont.Medium)
                setTextColor(slice.color)
            }
            val pct = WLabel(context).apply {
                text = "${(slice.ratio * 100).roundToInt()}%"
                setStyle(14f, WFont.Regular)
                setTextColor(WColor.SecondaryText)
            }
            rowView.addView(label, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            rowView.addView(pct, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            legend.addView(
                rowView,
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    if (index > 0) topMargin = 4.dp
                }
            )
        }
    }
}
