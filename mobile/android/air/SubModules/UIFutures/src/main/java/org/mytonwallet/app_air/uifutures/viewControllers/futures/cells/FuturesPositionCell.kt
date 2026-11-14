package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.abs
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.pnlColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPercentString
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.wrapLtrInRtl
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition

internal const val POSITIONS_CARD_BOTTOM_SPACING = 12

@SuppressLint("ViewConstructor")
class FuturesPositionCell(context: Context, private val onTap: (MApiPerpsNativePosition) -> Unit) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private val ripple = WRippleDrawable.create(0f)
    private val cardView = WView(context)
    private val rowView = WView(context)
    private val iconView = WCustomImageView(context)

    private val topLeftLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    private val bottomLeftLabel = WLabel(context).apply {
        setStyle(14f)
        setSingleLine()
    }

    private val topRightLabel = WSensitiveDataContainer(
        WLabel(context).apply {
            setStyle(16f)
            setSingleLine()
        },
        WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
    ).apply { id = generateViewId() }

    private val bottomRightLabel = WSensitiveDataContainer(
        WLabel(context).apply {
            setStyle(14f)
            setSingleLine()
        },
        WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
    ).apply { id = generateViewId() }

    private val warningView = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageResource(IconsR.drawable.ic_warning_red_14)
    }

    init {
        rowView.background = ripple
        rowView.addView(iconView, LayoutParams(44.dp, 44.dp))
        rowView.addView(topLeftLabel, LayoutParams(0, WRAP_CONTENT))
        rowView.addView(bottomLeftLabel, LayoutParams(0, WRAP_CONTENT))
        rowView.addView(topRightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        rowView.addView(bottomRightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        rowView.addView(warningView, LayoutParams(14.dp, 14.dp))
        rowView.setConstraints {
            // Icon View
            toStart(iconView, 12f)
            toTop(iconView, 8f)
            // Top Row
            startToEnd(topLeftLabel, iconView, 12f)
            endToStart(topLeftLabel, topRightLabel, 8f)
            toTop(topLeftLabel, 9f)
            toEnd(topRightLabel, 16f)
            toTop(topRightLabel, 9f)
            // Bottom Row
            startToStart(bottomLeftLabel, topLeftLabel)
            endToStart(bottomLeftLabel, bottomRightLabel, 8f)
            toBottom(bottomLeftLabel, 9f)
            toEnd(bottomRightLabel, 16f)
            toBottom(bottomRightLabel, 9f)
            endToStart(warningView, bottomRightLabel, 4f)
            centerYToCenterY(warningView, bottomRightLabel)
        }
        rowView.setOnClickListener { position?.let(onTap) }

        cardView.addView(rowView, LayoutParams(MATCH_PARENT, ROW_HEIGHT.dp))
        cardView.setConstraints {
            allEdges(rowView)
        }
        addView(cardView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            allEdges(cardView)
        }
    }

    override fun updateTheme() {
        cardView.setPositionsCardBackground(isFirst, isLast)
        ripple.backgroundColor = Color.TRANSPARENT
        ripple.rippleColor = WColor.BackgroundRipple.color
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        topRightLabel.contentView.setTextColor(WColor.PrimaryText.color)
        bottomRightLabel.contentView.setTextColor(pnlColor(position?.pnl ?: 0.0))
    }

    private var position: MApiPerpsNativePosition? = null
    private var isFirst = false
    private var isLast = false

    fun configure(
        position: MApiPerpsNativePosition,
        isFirst: Boolean,
        isLast: Boolean,
        isStale: Boolean = false
    ) {
        this.position = position
        this.isFirst = isFirst
        this.isLast = isLast
        val valueAlpha = if (isStale) STALE_ALPHA else 1f
        topRightLabel.contentView.alpha = valueAlpha
        bottomRightLabel.contentView.alpha = valueAlpha
        configureCard(isLast)
        rowView.updateLayoutParams { height = (if (isLast) LAST_ROW_HEIGHT else ROW_HEIGHT).dp }
        val bottomMargin = if (isLast) LAST_ROW_BOTTOM_MARGIN else ROW_VERTICAL_MARGIN
        rowView.setConstraints {
            toBottom(bottomLeftLabel, bottomMargin)
            toBottom(bottomRightLabel, bottomMargin)
        }
        val amountCols = MASK_MIN_COLS + abs(position.coin.hashCode() % MASK_COLS_RANGE)
        topRightLabel.setMaskCols(amountCols)
        bottomRightLabel.setMaskCols(MASK_MIN_COLS + 1 + amountCols % (MASK_COLS_RANGE - 2))
        val image = position.image
        if (image != null) {
            iconView.set(Content.ofUrl(image, position.asset?.isRwaStock == true))
        } else {
            iconView.clear()
        }
        topLeftLabel.text = position.symbol
        bottomLeftLabel.text = position.sideText
        topRightLabel.contentView.text = position.value.toUsdString()
        bottomRightLabel.contentView.text = wrapLtrInRtl(
            "${position.pnl.toUsdString(
                showPositiveSign = true
            )} (${position.pnlPercent.toPercentString()})"
        )
        warningView.isGone = position.isNearLiquidation != true
        updateTheme()
    }

    private companion object {
        const val MASK_MIN_COLS = 4
        const val MASK_COLS_RANGE = 8
        const val ROW_HEIGHT = 60
        const val LAST_ROW_HEIGHT = 58
        const val ROW_VERTICAL_MARGIN = 9f
        const val LAST_ROW_BOTTOM_MARGIN = 7f
    }
}

internal fun WCell.configureCard(isLast: Boolean) {
    setCardPadding(if (isLast) POSITIONS_CARD_BOTTOM_SPACING.dp else 0)
}

// Call on bind, so a gutter change applies
internal fun View.setCardPadding(bottom: Int) {
    val gutter = ViewConstants.HORIZONTAL_PADDINGS.dp
    setPaddingLocalized(gutter, 0, gutter, bottom)
}

internal fun WView.setPositionsCardBackground(isFirst: Boolean, isLast: Boolean) {
    setBackgroundColor(
        WColor.Background.color,
        if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f,
        if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f,
        clipToBounds = true
    )
}
