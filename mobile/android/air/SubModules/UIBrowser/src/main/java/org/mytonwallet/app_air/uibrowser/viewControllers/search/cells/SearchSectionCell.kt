package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.SpringSnapHelper
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class SearchSectionCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    companion object {
        private const val ROWS_PER_COLUMN = 3
        private const val COLUMN_WIDTH_OFFSET = 32
    }

    private var sectionItemCount = 0
    private var rowHeight = 0
    private var rowSpacing = 0
    private var cellType: WCell.Type? = null
    private var maximumItemWidths: List<Int>? = null
    private var horizontalEndSpacing = 0
    private var contentIdentity: Any? = null
    private var bottomRadius = ViewConstants.BLOCK_RADIUS.dp
    private var createCell: (() -> WCell)? = null
    private var configureCell: ((WCell, Int, Boolean) -> Unit)? = null
    private val springSnap = SpringSnapHelper(snapToStart = true)

    private val sectionAdapter = object : RecyclerView.Adapter<ColumnHolder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ColumnHolder =
            ColumnHolder(
                LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = RecyclerView.LayoutParams(columnWidth(0), WRAP_CONTENT)
                }
            )

        override fun onBindViewHolder(holder: ColumnHolder, position: Int) {
            val columnWidth = columnWidth(position)
            if (holder.column.layoutParams.width != columnWidth) {
                holder.column.layoutParams = holder.column.layoutParams.apply {
                    width = columnWidth
                }
            }

            val firstItemIndex = position * ROWS_PER_COLUMN
            val lastItemIndex = minOf(firstItemIndex + ROWS_PER_COLUMN, sectionItemCount)
            val itemCount = lastItemIndex - firstItemIndex
            if (holder.cellType !== cellType) {
                holder.column.removeAllViews()
                holder.cellType = cellType
            }
            while (holder.column.childCount > itemCount) {
                holder.column.removeViewAt(holder.column.childCount - 1)
            }
            while (holder.column.childCount < itemCount) {
                val cell = createCell?.invoke() ?: break
                val childIndex = holder.column.childCount
                holder.column.addView(
                    cell,
                    LinearLayout.LayoutParams(MATCH_PARENT, rowHeight).apply {
                        topMargin = if (childIndex == 0) 0 else rowSpacing
                    }
                )
            }
            for (itemIndex in firstItemIndex until lastItemIndex) {
                val childIndex = itemIndex - firstItemIndex
                val cell = holder.column.getChildAt(childIndex) as? WCell
                    ?: continue
                val expectedTopMargin = if (childIndex == 0) 0 else rowSpacing
                val layoutParams = cell.layoutParams as LinearLayout.LayoutParams
                if (layoutParams.height != rowHeight ||
                    layoutParams.topMargin != expectedTopMargin
                ) {
                    cell.layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, rowHeight).apply {
                        topMargin = expectedTopMargin
                    }
                }
                configureCell?.invoke(
                    cell,
                    itemIndex,
                    itemIndex == lastItemIndex - 1
                )
            }
        }

        override fun getItemCount(): Int =
            (sectionItemCount + ROWS_PER_COLUMN - 1) / ROWS_PER_COLUMN
    }

    private val recyclerView = WRecyclerView(context).apply {
        layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
        adapter = sectionAdapter
        isHorizontalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        addItemDecoration(
            object : RecyclerView.ItemDecoration() {
                override fun getItemOffsets(
                    outRect: Rect,
                    view: View,
                    parent: RecyclerView,
                    state: RecyclerView.State
                ) {
                    outRect.set(0, 0, 0, 0)
                    val position = parent.getChildAdapterPosition(view)
                    if (position != sectionAdapter.itemCount - 1) return

                    if (parent.layoutDirection == View.LAYOUT_DIRECTION_RTL) {
                        outRect.left = horizontalEndSpacing
                    } else {
                        outRect.right = horizontalEndSpacing
                    }
                }
            }
        )
    }

    override fun setupViews() {
        super.setupViews()
        addView(recyclerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setConstraints { allEdges(recyclerView) }
        springSnap.attachTo(recyclerView)
        updateTheme()
    }

    @SuppressLint("NotifyDataSetChanged")
    fun configure(
        itemCount: Int,
        rowHeight: Int,
        cellType: WCell.Type,
        contentIdentity: Any?,
        maximumItemWidths: List<Int>? = null,
        rowSpacing: Int = 0,
        verticalPadding: Int = 0,
        horizontalEndSpacing: Int = 0,
        bottomRadius: Float = ViewConstants.BLOCK_RADIUS.dp,
        createCell: () -> WCell,
        configureCell: (WCell, Int, Boolean) -> Unit
    ) {
        val contentChanged = this.sectionItemCount != itemCount ||
            this.cellType !== cellType ||
            this.contentIdentity != contentIdentity
        this.sectionItemCount = itemCount
        this.rowHeight = rowHeight
        this.rowSpacing = rowSpacing
        this.cellType = cellType
        this.contentIdentity = contentIdentity
        this.maximumItemWidths = maximumItemWidths
        if (this.horizontalEndSpacing != horizontalEndSpacing) {
            this.horizontalEndSpacing = horizontalEndSpacing
            recyclerView.invalidateItemDecorations()
        }
        if (this.bottomRadius != bottomRadius) {
            this.bottomRadius = bottomRadius
            updateTheme()
        }
        this.createCell = createCell
        this.configureCell = configureCell

        val visibleRowCount = minOf(itemCount, ROWS_PER_COLUMN)
        val height = visibleRowCount * rowHeight +
            (visibleRowCount - 1).coerceAtLeast(0) * rowSpacing +
            verticalPadding * 2
        if (recyclerView.paddingTop != verticalPadding ||
            recyclerView.paddingBottom != verticalPadding ||
            recyclerView.paddingStart != 0 ||
            recyclerView.paddingEnd != 0
        ) {
            recyclerView.setPadding(0, verticalPadding, 0, verticalPadding)
        }
        if (layoutParams.height != height) {
            layoutParams = layoutParams.apply {
                this.height = height
            }
        }
        sectionAdapter.notifyDataSetChanged()
        if (contentChanged) {
            springSnap.cancel()
            recyclerView.scrollToPosition(0)
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        springSnap.cancel()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            bottomRadius
        )
    }

    @SuppressLint("NotifyDataSetChanged")
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw) sectionAdapter.notifyDataSetChanged()
    }

    private fun columnWidth(position: Int): Int {
        val availableWidth = recyclerView.width.takeIf { it > 0 } ?: measuredWidth
        val defaultColumnWidth = if (sectionItemCount > ROWS_PER_COLUMN) {
            (availableWidth - COLUMN_WIDTH_OFFSET.dp).coerceAtLeast(1)
        } else {
            availableWidth.coerceAtLeast(1)
        }
        return minOf(defaultColumnWidth, maximumItemWidth(position) ?: Int.MAX_VALUE)
    }

    private fun maximumItemWidth(position: Int): Int? {
        val widths = maximumItemWidths ?: return null
        val firstItemIndex = position * ROWS_PER_COLUMN
        val lastItemIndex = minOf(firstItemIndex + ROWS_PER_COLUMN, widths.size)
        if (firstItemIndex >= lastItemIndex) return null

        var maximumWidth = widths[firstItemIndex]
        for (itemIndex in firstItemIndex + 1 until lastItemIndex) {
            maximumWidth = maxOf(maximumWidth, widths[itemIndex])
        }
        return maximumWidth
    }

    private class ColumnHolder(val column: LinearLayout) : RecyclerView.ViewHolder(column) {
        var cellType: WCell.Type? = null
    }
}
