@file:Suppress("ktlint:standard:backing-property-naming")

package org.mytonwallet.app_air.uicomponents.base

import android.annotation.SuppressLint
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListUpdateCallback
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.RecyclerView.NO_POSITION
import java.lang.ref.WeakReference
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.WEquatable

/*
    WRecyclerViewAdapter is used to map WRecyclerViewDataSource to RecyclerView.Adapter class.
        And WRecyclerViewDataSource is similar to UITableViewDataSource in iOS applications.
 */
class WRecyclerViewAdapter(
    private val datasource: WeakReference<WRecyclerViewDataSource>,
    registeredCellTypes: Array<WCell.Type>
) : RecyclerView.Adapter<WCell.Holder>() {

    companion object {
        private const val DEFAULT_MAX_SCRAP = 5
    }

    // Registered types, to be used later in datasource function calls
    private var registeredCellTypesHashmap = HashMap<Int, WCell.Type>()

    private var rvAnimator: RecyclerView.ItemAnimator? = null

    init {
        for (cellType in registeredCellTypes) {
            registeredCellTypesHashmap[cellType.value] = cellType
        }
        // TODO:: Use stable ids to increase performance
        // setHasStableIds(true)
    }

    // DataSource that provides recycler-view data
    interface WRecyclerViewDataSource {
        fun recyclerViewNumberOfSections(rv: RecyclerView): Int
        fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int
        fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type
        fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell
        fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? = null

        fun recyclerViewConfigureCell(
            rv: RecyclerView,
            cellHolder: WCell.Holder,
            indexPath: IndexPath
        )
    }

    private var recyclerView: RecyclerView? = null

    private var _cachedNumberOfSections: Int? = null
    private var _cachedSectionItemCount = HashMap<Int, Int>()
    private var _cachedTotalCount: Int? = null

    // Set recycler view on attach to one of them
    override fun onAttachedToRecyclerView(recyclerView: RecyclerView) {
        super.onAttachedToRecyclerView(recyclerView)
        this.recyclerView = recyclerView
    }

    @SuppressLint("NotifyDataSetChanged")
    fun reloadData() {
        if (rvAnimator == null) rvAnimator = recyclerView?.itemAnimator // Store initial state

        _cachedNumberOfSections = null
        _cachedSectionItemCount = HashMap()
        _cachedTotalCount = null

        recyclerView?.itemAnimator = rvAnimator // Restore initial state
        notifyDataSetChanged()
    }

    fun reloadRange(start: Int, count: Int) {
        if (rvAnimator == null) rvAnimator = recyclerView?.itemAnimator // Store initial state

        _cachedNumberOfSections = null
        _cachedSectionItemCount = HashMap()
        _cachedTotalCount = null

        recyclerView?.itemAnimator = rvAnimator // Restore initial state
        notifyItemRangeChanged(start, count)
    }

    class OffsetUpdateCallback(
        private val adapter: WRecyclerViewAdapter,
        private val section: Int
    ) : ListUpdateCallback {
        val itemsAbove = adapter.indexPathToPosition(IndexPath(section, 0))

        override fun onInserted(position: Int, count: Int) {
            adapter.apply {
                _cachedTotalCount = _cachedTotalCount?.plus(count)
                _cachedSectionItemCount[section]?.let {
                    _cachedSectionItemCount[section] = it + count
                }
                notifyItemRangeInserted(position + itemsAbove, count)
            }
        }

        override fun onRemoved(position: Int, count: Int) {
            adapter.apply {
                _cachedTotalCount = _cachedTotalCount?.minus(count)
                _cachedSectionItemCount[section]?.let {
                    _cachedSectionItemCount[section] = it - count
                }
                notifyItemRangeRemoved(position + itemsAbove, count)
            }
        }

        override fun onMoved(fromPosition: Int, toPosition: Int) {
            adapter.notifyItemMoved(fromPosition + itemsAbove, toPosition + itemsAbove)
        }

        override fun onChanged(position: Int, count: Int, payload: Any?) {
            adapter.notifyItemRangeChanged(position + itemsAbove, count, payload)
        }
    }

    fun applyChanges(
        oldList: List<WEquatable<*>>,
        newList: List<WEquatable<*>>,
        section: Int,
        forceReloadFirstAndLast: Boolean
    ) {
        val diffCallback = object : DiffUtil.Callback() {

            override fun getOldListSize(): Int = oldList.size
            override fun getNewListSize(): Int = newList.size

            override fun areItemsTheSame(oldPos: Int, newPos: Int): Boolean =
                oldList[oldPos].isSame(newList[newPos])

            override fun areContentsTheSame(oldPos: Int, newPos: Int): Boolean {
                if (forceReloadFirstAndLast && (oldPos == 0 || oldPos == oldList.size - 1)) {
                    return false
                }
                return !oldList[oldPos].isChanged(newList[newPos])
            }
        }

        val diffResult = DiffUtil.calculateDiff(diffCallback, false)
        diffResult.dispatchUpdatesTo(OffsetUpdateCallback(this, section))
    }

    fun invalidateCellType(cellType: WCell.Type) {
        val recyclerView = recyclerView ?: return
        for (i in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(i)
            val viewHolder = recyclerView.getChildViewHolder(child)
            if (viewHolder.itemViewType == cellType.value) viewHolder.setIsRecyclable(false)
        }
        val pool = recyclerView.recycledViewPool
        pool.setMaxRecycledViews(cellType.value, 0)
        pool.setMaxRecycledViews(cellType.value, DEFAULT_MAX_SCRAP)
    }

    fun updateVisibleCells(customOperator: ((cell: WCell) -> Unit)? = null) {
        val recyclerView = recyclerView ?: return
        for (i in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(i)
            val viewHolder = recyclerView.getChildViewHolder(child)
            customOperator?.let {
                customOperator((viewHolder as WCell.Holder).cell)
            } ?: run {
                val position = recyclerView.getChildAdapterPosition(child)
                if (position != NO_POSITION) {
                    datasource.get()?.recyclerViewConfigureCell(
                        recyclerView,
                        viewHolder as WCell.Holder,
                        positionToIndexPath(position)
                    )
                }
            }
        }
    }

    fun updateTheme() {
        reloadData()
    }

    // Function to map position into index path
    private fun cachedNumberOfSections(): Int? {
        _cachedNumberOfSections?.let { return it }
        val rv = recyclerView ?: return null
        return datasource.get()?.recyclerViewNumberOfSections(rv)?.also {
            _cachedNumberOfSections = it
        }
    }

    private fun cachedSectionItemCount(section: Int): Int =
        _cachedSectionItemCount.getOrPut(section) {
            val rv = recyclerView ?: return@getOrPut 0
            datasource.get()?.recyclerViewNumberOfItems(rv, section) ?: 0
        }

    fun positionToIndexPath(position: Int): IndexPath {
        val sections = cachedNumberOfSections() ?: return IndexPath(0, position)
        var section = 0
        var offset = 0
        for (i in 0..sections) {
            val itemCount = cachedSectionItemCount(i)
            if (position < offset + itemCount) {
                break
            } else {
                offset += itemCount
                section += 1
            }
        }
        return IndexPath(section, position - offset)
    }

    fun indexPathToPosition(indexPath: IndexPath): Int {
        var position = 0
        for (section in 0 until indexPath.section) {
            position += cachedSectionItemCount(section)
        }
        position += indexPath.row
        return position
    }

    private var idNum = 1L
    private val idMap = HashMap<String, Long>()
    override fun getItemId(position: Int): Long {
        val ds = datasource.get() ?: return RecyclerView.NO_ID
        val rv = recyclerView ?: return RecyclerView.NO_ID
        val stringId =
            ds.recyclerViewCellItemId(rv, positionToIndexPath(position))
                ?: return RecyclerView.NO_ID
        idMap[stringId]?.let {
            return it
        }
        idNum += 1
        idMap[stringId] = idNum
        return idNum
    }

    override fun getItemViewType(position: Int): Int {
        val ds = datasource.get() ?: return 0
        val rv = recyclerView ?: return 0
        return ds.recyclerViewCellType(rv, positionToIndexPath(position)).value
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): WCell.Holder {
        val ds = datasource.get()
        val rv = recyclerView
        val cellType = registeredCellTypesHashmap[viewType]
        if (ds == null || rv == null || cellType == null) {
            return WCell.Holder(WCell(parent.context))
        }
        return WCell.Holder(ds.recyclerViewCellView(rv, cellType))
    }

    override fun getItemCount(): Int {
        // Check if cached total count, because we do NOT expect it be calculated every time.
        _cachedTotalCount?.let { return it }
        // Not cached, so count the items for all sections
        val ds = datasource.get() ?: return 0
        val rv = recyclerView ?: return 0
        if (_cachedNumberOfSections == null) {
            _cachedNumberOfSections = ds.recyclerViewNumberOfSections(rv)
        }
        val sections = _cachedNumberOfSections ?: return 0
        var totalCount = 0
        for (i in 0..<sections) {
            totalCount +=
                _cachedSectionItemCount.getOrPut(i) { ds.recyclerViewNumberOfItems(rv, i) }
        }
        _cachedTotalCount = totalCount
        return totalCount
    }

    override fun onBindViewHolder(holder: WCell.Holder, position: Int) {
        val ds = datasource.get() ?: return
        val rv = recyclerView ?: return
        ds.recyclerViewConfigureCell(rv, holder, positionToIndexPath(position))
    }
}
