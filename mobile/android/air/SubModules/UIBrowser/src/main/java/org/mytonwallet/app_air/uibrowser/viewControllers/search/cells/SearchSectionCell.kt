package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.graphics.drawable.BitmapDrawable
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.drawToBitmap
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.SpringSnapHelper
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

@SuppressLint("ViewConstructor")
class SearchSectionCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    companion object {
        private const val ROWS_PER_COLUMN = 3
        private const val COLUMN_WIDTH_OFFSET = 32
        private const val CONTENT_SWITCH_MS = 250L
    }

    private var sectionItemCount = 0

    private var rowMajorColumnCount: Int? = null
    private var fitsColumnsToWidth = false
    private var verticalPadding = 0
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
    private var contentSwitch: ValueAnimator? = null

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
            val itemIndices = columnItemIndices(position)
            val itemCount = itemIndices.count()
            val columnHeight = contentHeight(itemCount)
            if (holder.column.layoutParams.width != columnWidth ||
                holder.column.layoutParams.height != columnHeight
            ) {
                holder.column.layoutParams = holder.column.layoutParams.apply {
                    width = columnWidth
                    height = columnHeight
                }
            }

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
            itemIndices.forEachIndexed { childIndex, itemIndex ->
                val cell = holder.column.getChildAt(childIndex) as? WCell
                    ?: return@forEachIndexed
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
                    itemIndex == itemIndices.last
                )
            }
        }

        override fun getItemCount(): Int = rowMajorColumnCount
            ?: ((sectionItemCount + ROWS_PER_COLUMN - 1) / ROWS_PER_COLUMN)
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
        fitColumnsToWidth: Int? = null,
        bottomRadius: Float = ViewConstants.BLOCK_RADIUS.dp,
        animated: Boolean = false,
        createCell: () -> WCell,
        configureCell: (WCell, Int, Boolean) -> Unit
    ) {
        val contentChanged = this.sectionItemCount != itemCount ||
            this.cellType !== cellType ||
            this.contentIdentity != contentIdentity
        finishContentSwitch()
        val startHeight = height
        val isSwitching = animated && contentChanged && isAttachedToWindow &&
            recyclerView.isLaidOut && recyclerView.width > 0 && recyclerView.height > 0 &&
            WGlobalStorage.getAreAnimationsActive()
        if (isSwitching) fadeOutContent()
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

        this.fitsColumnsToWidth = fitColumnsToWidth != null
        this.verticalPadding = verticalPadding
        if (recyclerView.paddingTop != verticalPadding ||
            recyclerView.paddingBottom != verticalPadding ||
            recyclerView.paddingStart != 0 ||
            recyclerView.paddingEnd != 0
        ) {
            recyclerView.setPadding(0, verticalPadding, 0, verticalPadding)
        }
        updateColumnLayout(fitColumnsToWidth)
        sectionAdapter.notifyDataSetChanged()
        if (contentChanged) {
            springSnap.cancel()
            recyclerView.scrollToPosition(0)
        }
        if (isSwitching) switchHeight(startHeight)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        springSnap.cancel()
        finishContentSwitch()
    }

    private fun fadeOutContent() {
        val snapshot = BitmapDrawable(resources, recyclerView.drawToBitmap()).apply {
            setBounds(recyclerView.left, recyclerView.top, recyclerView.right, recyclerView.bottom)
        }
        overlay.add(snapshot)
        recyclerView.alpha = 0f
        contentSwitch = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = CONTENT_SWITCH_MS
            interpolator = WInterpolator.easeInOut
            doOnEnd {
                overlay.remove(snapshot)
                recyclerView.alpha = 1f
            }
            addUpdateListener {
                val fraction = it.animatedValue as Float
                recyclerView.alpha = fraction
                snapshot.alpha = ((1f - fraction) * 255).roundToInt()
            }
        }
    }

    private fun switchHeight(startHeight: Int) {
        val animator = contentSwitch ?: return
        val targetHeight = layoutParams.height
        if (startHeight > 0 && targetHeight > 0 && startHeight != targetHeight) {
            layoutParams = layoutParams.apply { height = startHeight }
            animator.addUpdateListener {
                val fraction = it.animatedFraction
                layoutParams = layoutParams.apply {
                    height = (startHeight + (targetHeight - startHeight) * fraction).roundToInt()
                }
            }
            animator.doOnEnd {
                layoutParams = layoutParams.apply { height = targetHeight }
            }
        }
        animator.start()
    }

    private fun finishContentSwitch() {
        contentSwitch?.end()
        contentSwitch = null
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
        if (w == oldw) return
        // The section's own width follows its columns, so fit against the list's width.
        val list = parent as? View
        val availableWidth =
            (list?.width ?: 0) - (list?.paddingLeft ?: 0) - (list?.paddingRight ?: 0)
        if (fitsColumnsToWidth && availableWidth > 0 &&
            fittingColumnCount(availableWidth) != rowMajorColumnCount
        ) {
            post {
                updateColumnLayout(availableWidth)
                sectionAdapter.notifyDataSetChanged()
            }
        } else {
            sectionAdapter.notifyDataSetChanged()
        }
    }

    private fun updateColumnLayout(availableWidth: Int?) {
        rowMajorColumnCount = availableWidth?.let { fittingColumnCount(it) }
        val visibleRowCount = rowMajorColumnCount
            ?.let { (sectionItemCount + it - 1) / it }
            ?: minOf(sectionItemCount, ROWS_PER_COLUMN)
        val height = contentHeight(visibleRowCount) + verticalPadding * 2
        if (layoutParams.height != height) {
            layoutParams = layoutParams.apply {
                this.height = height
            }
        }
    }

    // The columns retain their full content height while their viewport animates between section sizes.
    private fun contentHeight(rowCount: Int): Int =
        rowCount * rowHeight + (rowCount - 1).coerceAtLeast(0) * rowSpacing

    private fun columnWidth(position: Int): Int {
        val availableWidth = recyclerView.width.takeIf { it > 0 } ?: measuredWidth
        val defaultColumnWidth = if (rowMajorColumnCount == null &&
            sectionItemCount > ROWS_PER_COLUMN
        ) {
            (availableWidth - COLUMN_WIDTH_OFFSET.dp).coerceAtLeast(1)
        } else {
            availableWidth.coerceAtLeast(1)
        }
        return minOf(defaultColumnWidth, maximumItemWidth(position) ?: Int.MAX_VALUE)
    }

    private fun maximumItemWidth(position: Int): Int? {
        val widths = maximumItemWidths ?: return null
        var maximumWidth: Int? = null
        for (itemIndex in columnItemIndices(position)) {
            val width = widths.getOrNull(itemIndex) ?: continue
            maximumWidth = maxOf(maximumWidth ?: width, width)
        }
        return maximumWidth
    }

    private fun columnItemIndices(position: Int): IntProgression {
        rowMajorColumnCount?.let { columns ->
            return position until sectionItemCount step columns
        }
        val firstItemIndex = position * ROWS_PER_COLUMN
        return firstItemIndex until minOf(firstItemIndex + ROWS_PER_COLUMN, sectionItemCount)
    }

    // Most row-major columns that fit without scrolling.
    private fun fittingColumnCount(availableWidth: Int): Int? {
        val widths = maximumItemWidths ?: return null
        if (widths.isEmpty()) return null
        for (columns in widths.size downTo 1) {
            if ((widths.size + columns - 1) / columns > ROWS_PER_COLUMN) break
            var totalWidth = horizontalEndSpacing
            for (column in 0 until columns) {
                var columnWidth = 0
                for (itemIndex in column until widths.size step columns) {
                    columnWidth = maxOf(columnWidth, widths[itemIndex])
                }
                totalWidth += columnWidth
            }
            if (totalWidth <= availableWidth) return columns
        }
        return null
    }

    private class ColumnHolder(val column: LinearLayout) : RecyclerView.ViewHolder(column) {
        var cellType: WCell.Type? = null
    }
}
