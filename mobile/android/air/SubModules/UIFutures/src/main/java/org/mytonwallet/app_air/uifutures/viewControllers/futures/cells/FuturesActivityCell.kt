package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.core.view.children
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uicomponents.commonViews.cells.ShowAllView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uimarket.viewControllers.market.views.MarketSectionHeaderView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFill

@SuppressLint("ViewConstructor")
class FuturesActivityCell(
    context: Context,
    private val onTap: (MApiPerpsFill) -> Unit,
    private val onShowAll: (() -> Unit)? = null
) : WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private companion object {
        const val SHOW_ALL_ROW_HEIGHT = 56
    }

    private val headerView = MarketSectionHeaderView(context) {}.apply {
        translationY = 5f.dp
        configure(LocaleController.getString("Activity"), showsSeeAll = false)
    }
    private val rowsView = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
    }
    private val rowsById = LinkedHashMap<String, FuturesActivityRowView>()

    // Ends a capped card and opens the whole history, as on the home screen
    private val showAllView = ShowAllView(context).apply {
        configure(
            icon = IconsR.drawable.ic_show_all,
            text = LocaleController.getString("Show All Actions")
        )
        setCounter(null)
        onTap = { onShowAll?.invoke() }
    }

    // Keeps the row's content at full height while its own height animates
    private val showAllContainer = FrameLayout(context).apply {
        visibility = GONE
        addView(showAllView, FrameLayout.LayoutParams(MATCH_PARENT, SHOW_ALL_ROW_HEIGHT.dp))
    }
    private var showAllRevealAnimation: SpringAnimation? = null

    private val loadingView = SkeletonCell(context, drawsBackground = false).apply {
        visibility = GONE
    }
    private val container = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(headerView, LinearLayout.LayoutParams(MATCH_PARENT, 38.dp))
        addView(
            rowsView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = 2.dp }
        )
        addView(loadingView, LinearLayout.LayoutParams(MATCH_PARENT, SkeletonCell.HEIGHT))
        addView(showAllContainer, LinearLayout.LayoutParams(MATCH_PARENT, SHOW_ALL_ROW_HEIGHT.dp))
    }

    override fun setupViews() {
        super.setupViews()

        addView(container, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints { allEdges(container) }
        updateTheme()
    }

    /**
     * [showsAll] adds the row that opens the whole history. With [animatesChanges], a shown card reveals its new activities
     * and collapses the ones it no longer holds, as the home screen does.
     */
    fun configure(
        activities: List<MApiPerpsFill>,
        bottomSpacing: Int,
        isLoading: Boolean = false,
        showsAll: Boolean = false,
        animatesChanges: Boolean = false
    ) {
        setCardPadding(bottomSpacing.dp)
        loadingView.isGone = !isLoading || activities.isNotEmpty()
        val isAnimated = animatesChanges && isAttachedToWindow && rowsById.isNotEmpty()
        updateShowAllRow(showsAll && onShowAll != null, isAnimated)
        if (isAnimated) {
            updateRows(activities)
        } else {
            replaceRows(activities)
        }
        updateTheme()
    }

    private fun updateShowAllRow(isShown: Boolean, isAnimated: Boolean) {
        val wasShown = !showAllContainer.isGone
        showAllContainer.isGone = !isShown
        if (isShown && !wasShown && isAnimated) {
            revealShowAllRow()
        } else if (!isShown || showAllRevealAnimation?.isRunning != true) {
            resetShowAllRow()
        }
    }

    private fun revealShowAllRow() {
        val targetHeight = SHOW_ALL_ROW_HEIGHT.dp.toFloat()
        showAllRevealAnimation?.cancel()
        showAllContainer.updateLayoutParams { height = 0 }
        showAllView.alpha = 0f
        // Content fades in over the last 30% of the growth, as the activity rows do.
        val fadeStartHeight = 0.7f * targetHeight
        showAllRevealAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(0f)
            spring = SpringForce(targetHeight).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                showAllContainer.updateLayoutParams { height = value.toInt() }
                showAllView.alpha =
                    ((value - fadeStartHeight) / (targetHeight - fadeStartHeight)).coerceIn(0f, 1f)
            }
            addEndListener { _, canceled, _, _ ->
                if (!canceled) resetShowAllRow()
            }
            start()
        }
    }

    private fun resetShowAllRow() {
        showAllRevealAnimation?.cancel()
        showAllContainer.updateLayoutParams { height = SHOW_ALL_ROW_HEIGHT.dp }
        showAllView.alpha = 1f
    }

    private fun replaceRows(activities: List<MApiPerpsFill>) {
        rowsView.children.forEach { (it as? FuturesActivityRowView)?.cancelHeightAnimation() }
        rowsView.removeAllViews()
        rowsById.clear()
        activities.forEach { activity ->
            val row = FuturesActivityRowView(context, onTap)
            row.configure(activity, showsTimeOnly = false)
            rowsById[activity.identity] = row
            rowsView.addView(
                row,
                LinearLayout.LayoutParams(MATCH_PARENT, ActivityCell.MAIN_CONTENT_HEIGHT.dp)
            )
        }
    }

    private fun updateRows(activities: List<MApiPerpsFill>) {
        (rowsById.keys - activities.mapTo(HashSet()) { it.identity }).forEach { id ->
            rowsById.remove(id)?.let { row ->
                row.startRemoveAnimation { rowsView.removeView(row) }
            }
        }
        var index = 0
        activities.forEach { activity ->
            while ((rowsView.getChildAt(index) as? FuturesActivityRowView)?.isRemoving ==
                true
            ) {
                index++
            }
            val row = rowsById[activity.identity]
            if (row == null) {
                val newRow = FuturesActivityRowView(context, onTap)
                newRow.configure(activity, showsTimeOnly = false)
                rowsById[activity.identity] = newRow
                rowsView.addView(newRow, index, LinearLayout.LayoutParams(MATCH_PARENT, 0))
                newRow.startInsertAnimation()
            } else {
                row.configure(activity, showsTimeOnly = false)
                if (rowsView.getChildAt(index) !== row) {
                    rowsView.removeView(row)
                    rowsView.addView(row, index)
                }
            }
            index++
        }
    }

    override fun updateTheme() {
        container.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            clipToBounds = true
        )
        headerView.updateTheme()
        showAllView.updateTheme()
        loadingView.updateTheme()
        for (index in 0 until rowsView.childCount) {
            (rowsView.getChildAt(index) as? FuturesActivityRowView)?.updateTheme()
        }
    }
}

/**
 * The activities a card shows, as on the home screen: up to [limit], or one more in place of
 * the Show All row it would otherwise end with.
 */
internal fun <T> List<T>.forActivityCard(limit: Int): Pair<List<T>, Boolean> =
    if (size <= limit + 1) this to false else take(limit) to true
