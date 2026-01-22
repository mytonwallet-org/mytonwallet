package org.mytonwallet.app_air.uiassets.viewControllers.nft.views

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import androidx.constraintlayout.widget.Barrier
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.constraintlayout.widget.Guideline
import org.mytonwallet.app_air.uiassets.viewControllers.nft.NftVC
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import kotlin.math.max
import kotlin.math.min

@SuppressLint("ViewConstructor")
class NftAttributesView(
    context: Context,
) : WView(context), WThemedView {

    data class RowView(
        val titleLabel: WLabel,
        val valueLabel: WLabel,
        val separator: WBaseView,
        val horizontalBarrier: Barrier
    )

    private val titlesBackground = WBaseView(context)
    private val rowViews = mutableListOf<RowView>()

    val collapsedHeight: Int
        get() {
            if (rowViews.isEmpty())
                return 0
            val rowsToShow = min(
                rowViews.size,
                NftVC.COLLAPSED_ATTRIBUTES_COUNT
            )
            val barrierY = rowViews[rowsToShow - 1].horizontalBarrier.y.toInt()
            if (barrierY > 0)
                return barrierY + 10.dp
            var h = 0
            for (i in 0 until rowsToShow) {
                val row = rowViews[i]
                h += 20.dp + max(row.titleLabel.measuredHeight, row.valueLabel.measuredHeight)
            }
            return h
        }

    val fullHeight: Int
        get() {
            val barrierY = rowViews.lastOrNull()?.horizontalBarrier?.y?.toInt() ?: 0
            return if (barrierY > 0)
                barrierY + 10.dp
            else
                measuredHeight
        }

    override fun setupViews() {
        super.setupViews()

        updateTheme()
    }

    fun setupNft(nft: ApiNft) {
        removeAllViews()
        rowViews.clear()
        addView(
            titlesBackground,
            LayoutParams(MATCH_CONSTRAINT, LayoutParams.MATCH_PARENT)
        )
        val attributes = nft.metadata?.attributes ?: emptyList()
        for ((index, attribute) in attributes.withIndex()) {
            val titleLabel = WLabel(context).apply {
                setStyle(15f, WFont.Medium)
                text = attribute.traitType
                setTextColor(WColor.PrimaryText)
                setPaddingLocalized(0, 0, 12.dp, 0)
            }
            val valueLabel = WLabel(context).apply {
                setStyle(15f)
                text = attribute.value
                setTextColor(WColor.PrimaryText)
            }
            val separator = WBaseView(context).apply {
                if (index != attributes.lastIndex) {
                    setBackground(WColor.Separator)
                }
            }
            val horizontalBarrier = Barrier(context).apply {
                id = generateViewId()
                type = Barrier.BOTTOM
                referencedIds = intArrayOf(titleLabel.id, valueLabel.id)
            }
            addView(titleLabel)
            addView(valueLabel)
            addView(separator, LayoutParams(MATCH_CONSTRAINT, 1.dp))
            addView(horizontalBarrier)
            rowViews.add(
                RowView(
                    titleLabel,
                    valueLabel,
                    separator,
                    horizontalBarrier
                )
            )
        }
        val minWidthGuideline = Guideline(context).apply {
            id = generateViewId()
        }
        addView(minWidthGuideline)
        val verticalBarrier = Barrier(context).apply {
            id = generateViewId()
            type = Barrier.END
            referencedIds = (rowViews.map { it.titleLabel.id } + minWidthGuideline.id).toIntArray()
        }
        addView(verticalBarrier)
        setConstraints {
            rowViews.forEachIndexed { i, rowView ->
                val topView: View? =
                    if (i == 0) null else rowViews[i - 1].separator
                // Title
                if (i == 0)
                    toTop(rowView.titleLabel, 10f)
                else
                    topToBottom(rowView.titleLabel, topView!!, 10f)
                toStart(rowView.titleLabel, 12f)
                // Value
                if (i == 0)
                    toTop(rowView.valueLabel, 10f)
                else
                    topToBottom(rowView.valueLabel, topView!!, 10f)
                setHorizontalBias(rowView.valueLabel.id, 0f)
                startToEnd(rowView.valueLabel, verticalBarrier, 16f)
                toEnd(rowView.valueLabel, 12f)
                // Separator
                topToTop(rowView.separator, rowView.horizontalBarrier, 10f)
                toStart(rowView.separator)
                toEnd(rowView.separator)
            }
            rowViews.lastOrNull()?.separator?.let { separator ->
                separator.visibility = INVISIBLE
                toBottom(separator)
            }
            toStart(titlesBackground)
            endToStart(titlesBackground, verticalBarrier, -4f)
        }
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, 8f.dp, 8f.dp, true, WColor.Separator.color, 1)
        titlesBackground.setBackgroundColor(
            WColor.AttributesBackground.color,
            topLeftRadius = 8f.dp,
            topRightRadius = 0f.dp,
            bottomRightRadius = 0f.dp,
            bottomLeftRadius = 8f.dp,
            clipToBounds = true,
            strokeColor = WColor.Separator.color,
            strokeWidth = 1
        )
    }
}
