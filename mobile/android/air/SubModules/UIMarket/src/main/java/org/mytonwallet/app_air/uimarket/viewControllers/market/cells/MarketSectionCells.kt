package org.mytonwallet.app_air.uimarket.viewControllers.market.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.GridLayout
import android.widget.LinearLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketSection
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketToken
import org.mytonwallet.app_air.uimarket.viewControllers.market.views.MarketGridItemView
import org.mytonwallet.app_air.uimarket.viewControllers.market.views.MarketMoverItemView
import org.mytonwallet.app_air.uimarket.viewControllers.market.views.MarketSectionHeaderView
import org.mytonwallet.app_air.uimarket.viewControllers.market.views.MarketTokenRowView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

private const val GRID_HORIZONTAL_PADDING = 6
const val SECTION_BOTTOM_SPACING = 12

@SuppressLint("ViewConstructor")
class MarketMoversSectionCell(
    context: Context,
    private val onSeeAll: (MarketSection) -> Unit,
    private val onTokenTap: (MarketToken) -> Unit,
    private val showsHeader: Boolean = true
) : WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    private var marketSection: MarketSection? = null
    private val headerView = MarketSectionHeaderView(context) {
        marketSection?.let(onSeeAll)
    }
    private val recyclerView = RecyclerView(context).apply {
        layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
        isHorizontalScrollBarEnabled = false
        clipToPadding = false
        setPaddingLocalized(16.dp, if (showsHeader) 4.dp else 16.dp, 16.dp, 16.dp)
        addItemDecoration(object : RecyclerView.ItemDecoration() {
            override fun getItemOffsets(
                outRect: Rect,
                view: View,
                parent: RecyclerView,
                state: RecyclerView.State
            ) {
                if (parent.getChildAdapterPosition(view) > 0) {
                    if (parent.layoutDirection == View.LAYOUT_DIRECTION_RTL) {
                        outRect.right = 16.dp
                    } else {
                        outRect.left = 16.dp
                    }
                }
            }
        })
    }
    private val container = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        if (showsHeader) addView(headerView, LinearLayout.LayoutParams(MATCH_PARENT, 48.dp))
        addView(
            recyclerView,
            LinearLayout.LayoutParams(MATCH_PARENT, if (showsHeader) 180.dp else 192.dp)
        )
    }
    private val itemsAdapter = object : RecyclerView.Adapter<MarketMoverHolder>() {
        var tokens = emptyList<MarketToken>()

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): MarketMoverHolder {
            val item = MarketMoverItemView(context, onTokenTap).apply {
                layoutParams = RecyclerView.LayoutParams(160.dp, 160.dp)
            }
            return MarketMoverHolder(item)
        }

        override fun onBindViewHolder(holder: MarketMoverHolder, position: Int) {
            holder.view.configure(tokens[position])
        }

        override fun getItemCount(): Int = tokens.size
    }

    private class MarketMoverHolder(val view: MarketMoverItemView) : RecyclerView.ViewHolder(view)

    init {
        setPadding(0, 0, 0, SECTION_BOTTOM_SPACING.dp)
        recyclerView.adapter = itemsAdapter
        addView(container, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints { allEdges(container) }
        updateTheme()
    }

    @SuppressLint("NotifyDataSetChanged")
    fun configure(section: MarketSection, bottomSpacing: Int = SECTION_BOTTOM_SPACING) {
        setPadding(0, 0, 0, bottomSpacing.dp)
        marketSection = section
        headerView.configure(section.title, section.showsSeeAll)
        val visibleTokens = section.visibleTokens
        if (itemsAdapter.tokens != visibleTokens) {
            itemsAdapter.tokens = visibleTokens
            itemsAdapter.notifyDataSetChanged()
        }
        updateTheme()
    }

    override fun updateTheme() {
        container.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        headerView.updateTheme()
        for (index in 0 until recyclerView.childCount) {
            (recyclerView.getChildAt(index) as? MarketMoverItemView)?.updateTheme()
        }
    }
}

@SuppressLint("ViewConstructor")
class MarketGridSectionCell(
    context: Context,
    private val onSeeAll: (MarketSection) -> Unit,
    private val onTokenTap: (MarketToken) -> Unit
) : WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    private var marketSection: MarketSection? = null
    private val headerView = MarketSectionHeaderView(context) {
        marketSection?.let(onSeeAll)
    }
    private var gridNeedsRebuild = true
    private var configuredColumnCount = DEFAULT_COLUMN_COUNT
    private val gridView = GridLayout(context).apply {
        columnCount = configuredColumnCount
        alignmentMode = GridLayout.ALIGN_BOUNDS
        useDefaultMargins = false
        setPadding(GRID_HORIZONTAL_PADDING.dp, 4.dp, GRID_HORIZONTAL_PADDING.dp, 18.dp)
        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            post { maybeRebuildGrid() }
        }
    }
    private val container = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(headerView, LinearLayout.LayoutParams(MATCH_PARENT, 48.dp))
        addView(gridView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    init {
        setPadding(0, 0, 0, SECTION_BOTTOM_SPACING.dp)
        addView(container, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints { allEdges(container) }
        updateTheme()
    }

    fun configure(section: MarketSection, bottomSpacing: Int = SECTION_BOTTOM_SPACING) {
        setPadding(0, 0, 0, bottomSpacing.dp)
        val tokensChanged = marketSection?.tokens != section.tokens ||
            marketSection?.visibleLimit != section.visibleLimit
        marketSection = section
        configureHeader(section)
        if (tokensChanged) {
            gridNeedsRebuild = true
            maybeRebuildGrid()
            gridView.requestLayout()
        }
        updateTheme()
    }

    private fun configureHeader(section: MarketSection) {
        val showsSeeAll = section.showsSeeAll ||
            section.tokens.size > visibleCount(section, configuredColumnCount)
        headerView.configure(section.title, showsSeeAll)
    }

    private fun visibleCount(section: MarketSection, columnCount: Int): Int {
        val target = section.visibleLimit?.let {
            ((it + columnCount - 1) / columnCount) * columnCount
        } ?: (columnCount * MAX_ROWS)
        return min(section.tokens.size, target)
    }

    private fun maybeRebuildGrid(
        availableWidth: Int = (
            gridView.width - gridView.paddingLeft - gridView.paddingRight
            ).coerceAtLeast(0)
    ) {
        val tokens = marketSection?.tokens ?: return
        if (availableWidth == 0) return
        val newColumnCount = calculateNoOfColumns(availableWidth, tokens.size)
        if (gridNeedsRebuild || newColumnCount != configuredColumnCount) {
            rebuildGrid(availableWidth)
        }
    }

    private fun rebuildGrid(availableWidth: Int) {
        val section = marketSection ?: return
        val tokens = section.tokens
        gridView.removeAllViews()
        configuredColumnCount = calculateNoOfColumns(availableWidth, tokens.size)
        gridView.columnCount = configuredColumnCount
        val visibleTokens = tokens.take(visibleCount(section, configuredColumnCount))
        configureHeader(section)
        val slotCount = (
            (visibleTokens.size + configuredColumnCount - 1) / configuredColumnCount
            ) * configuredColumnCount
        val lastRow = slotCount / configuredColumnCount - 1
        repeat(slotCount) { index ->
            val row = index / configuredColumnCount
            val token = visibleTokens.getOrNull(index)
            val item = if (token != null) {
                MarketGridItemView(context, onTokenTap).apply { configure(token) }
            } else {
                View(context).apply { visibility = View.INVISIBLE }
            }
            gridView.addView(
                item,
                GridLayout.LayoutParams(
                    GridLayout.spec(row),
                    GridLayout.spec(index % configuredColumnCount, 1f)
                ).apply {
                    width = 0
                    height = 112.dp
                    if (row < lastRow) {
                        bottomMargin = 6.dp
                    }
                }
            )
        }
        gridNeedsRebuild = false
    }

    private fun calculateNoOfColumns(availableWidth: Int, itemCount: Int): Int {
        if (itemCount == 0) return 1
        val widthBasedCount = if (availableWidth > 0) {
            max(MIN_COLUMN_COUNT, availableWidth / MIN_ITEM_WIDTH.dp)
        } else {
            DEFAULT_COLUMN_COUNT
        }
        return min(itemCount, widthBasedCount)
    }

    override fun updateTheme() {
        container.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        headerView.updateTheme()
        for (index in 0 until gridView.childCount) {
            (gridView.getChildAt(index) as? MarketGridItemView)?.updateTheme()
        }
    }

    private companion object {
        const val DEFAULT_COLUMN_COUNT = 4
        const val MIN_COLUMN_COUNT = 2
        const val MIN_ITEM_WIDTH = 80
        const val MAX_ROWS = 2
    }
}

@SuppressLint("ViewConstructor")
class MarketRowsSectionCell(
    context: Context,
    private val onSeeAll: (MarketSection) -> Unit,
    private val onTokenTap: (MarketToken) -> Unit
) : WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    private var marketSection: MarketSection? = null
    private val headerView = MarketSectionHeaderView(context) {
        marketSection?.let(onSeeAll)
    }.apply {
        translationY = 5f.dp
    }
    private val rowsView = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
    }
    private val container = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(headerView, LinearLayout.LayoutParams(MATCH_PARENT, 38.dp))
        addView(rowsView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    init {
        setPadding(0, 0, 0, SECTION_BOTTOM_SPACING.dp)
        addView(container, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints { allEdges(container) }
        updateTheme()
    }

    fun configure(section: MarketSection, bottomSpacing: Int = SECTION_BOTTOM_SPACING) {
        setPadding(0, 0, 0, bottomSpacing.dp)
        marketSection = section
        headerView.configure(section.title, section.showsSeeAll)
        rowsView.removeAllViews()
        val visibleTokens = section.visibleTokens
        visibleTokens.forEachIndexed { index, token ->
            val isLastInSection = index == visibleTokens.lastIndex
            rowsView.addView(
                MarketTokenRowView(context, onTap = onTokenTap).apply {
                    configure(token, isLastInSection)
                },
                LinearLayout.LayoutParams(
                    MATCH_PARENT,
                    if (isLastInSection) 70.dp else 64.dp
                )
            )
            if (index < visibleTokens.lastIndex) {
                rowsView.addView(
                    View(context).apply { setBackgroundColor(WColor.Separator.color) },
                    LinearLayout.LayoutParams(MATCH_PARENT, 1).apply {
                        marginStart = 72.dp
                    }
                )
            }
        }
        updateTheme()
    }

    override fun updateTheme() {
        container.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        headerView.updateTheme()
        for (index in 0 until rowsView.childCount) {
            when (val child = rowsView.getChildAt(index)) {
                is MarketTokenRowView -> child.updateTheme()
                else -> child.setBackgroundColor(WColor.Separator.color)
            }
        }
    }
}

@SuppressLint("ViewConstructor")
class MarketTokenListCell(context: Context, onTokenTap: (MarketToken) -> Unit) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, 64.dp)),
    WThemedView {
    private val rowView = MarketTokenRowView(
        context,
        onTap = onTokenTap
    )

    init {
        addView(rowView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setConstraints { allEdges(rowView) }
        updateTheme()
    }

    fun configure(token: MarketToken) {
        rowView.configure(token)
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color)
        rowView.updateTheme()
    }
}
