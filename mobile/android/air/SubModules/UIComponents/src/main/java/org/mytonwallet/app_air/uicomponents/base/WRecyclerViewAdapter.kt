package org.mytonwallet.app_air.uicomponents.base

import android.annotation.SuppressLint
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListUpdateCallback
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.RecyclerView.NO_POSITION
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.WEquatable
import java.lang.ref.WeakReference

/*
    WRecyclerViewAdapter is used to map WRecyclerViewDataSource to RecyclerView.Adapter class.
        And WRecyclerViewDataSource is similar to UITableViewDataSource in iOS applications.
 */
class WRecyclerViewAdapter(
    private val datasource: WeakReference<WRecyclerViewDataSource>,
    registeredCellTypes: Array<WCell.Type>
) :
    RecyclerView.Adapter<WCell.Holder>() {

    // Registered types, to be used later in datasource function calls
    private var registeredCellTypesHashmap = HashMap<Int, WCell.Type>()

    private var rvAnimator: RecyclerView.ItemAnimator? = null

    init {
        for (cellType in registeredCellTypes) {
            registeredCellTypesHashmap[cellType.value] = cellType
        }
        // TODO:: Use stable ids to increase performance
        //setHasStableIds(true)
    }

    // DataSource that provides recycler-view data
    interface WRecyclerViewDataSource {
        fun recyclerViewNumberOfSections(rv: RecyclerView): Int
        fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int
        fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type
        fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell
        fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
            return null
        }

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
                if (_cachedTotalCount != null)
                    _cachedTotalCount = _cachedTotalCount!! + count
                if (_cachedSectionItemCount.containsKey(section))
                    _cachedSectionItemCount[section] =
                        _cachedSectionItemCount[section]!! + count
                notifyItemRangeInserted(position + itemsAbove, count)
            }
        }

        override fun onRemoved(position: Int, count: Int) {
            adapter.apply {
                if (_cachedTotalCount != null)
                    _cachedTotalCount = _cachedTotalCount!! - count
                if (_cachedSectionItemCount.containsKey(section))
                    _cachedSectionItemCount[section] =
                        _cachedSectionItemCount[section]!! - count
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

            override fun areItemsTheSame(oldPos: Int, newPos: Int): Boolean {
                return oldList[oldPos].isSame(newList[newPos])
            }

            override fun areContentsTheSame(oldPos: Int, newPos: Int): Boolean {
                if (forceReloadFirstAndLast && (oldPos == 0 || oldPos == oldList.size - 1))
                    return false
                return !oldList[oldPos].isChanged(newList[newPos])
            }
        }

        val diffResult = DiffUtil.calculateDiff(diffCallback, false)
        diffResult.dispatchUpdatesTo(OffsetUpdateCallback(this, section))
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
    fun positionToIndexPath(position: Int): IndexPath {
        if (_cachedNumberOfSections == null)
            _cachedNumberOfSections = datasource.get()?.recyclerViewNumberOfSections(recyclerView!!)
        var section = 0
        var offset = 0
        for (i in 0.._cachedNumberOfSections!!) {
            if (!_cachedSectionItemCount.containsKey(i)) {
                _cachedSectionItemCount[i] =
                    datasource.get()?.recyclerViewNumberOfItems(recyclerView!!, i) ?: 0
            }
            if (position < offset + _cachedSectionItemCount[i]!!) {
                break
            } else {
                offset += _cachedSectionItemCount[i]!!
                section += 1
            }
        }
        return IndexPath(section, position - offset)
    }

    fun indexPathToPosition(indexPath: IndexPath): Int {
        if (_cachedNumberOfSections == null)
            _cachedNumberOfSections = datasource.get()?.recyclerViewNumberOfSections(recyclerView!!)
        var position = 0
        for (section in 0 until indexPath.section) {
            if (!_cachedSectionItemCount.containsKey(section)) {
                _cachedSectionItemCount[section] =
                    datasource.get()?.recyclerViewNumberOfItems(recyclerView!!, section) ?: 0
            }
            position += _cachedSectionItemCount[section]!!
        }
        position += indexPath.row
        return position
    }

    private var idNum = 1L
    private val idMap = HashMap<String, Long>()
    override fun getItemId(position: Int): Long {
        val stringId =
            datasource.get()?.recyclerViewCellItemId(recyclerView!!, positionToIndexPath(position))
                ?: return RecyclerView.NO_ID
        idMap[stringId]?.let {
            return it
        }
        idNum += 1
        idMap[stringId] = idNum
        return idNum
    }

    override fun getItemViewType(position: Int): Int {
        return datasource.get()
            ?.recyclerViewCellType(recyclerView!!, positionToIndexPath(position))?.value ?: 0
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): WCell.Holder {
        return WCell.Holder(
            datasource.get()!!.recyclerViewCellView(
                recyclerView!!,
                registeredCellTypesHashmap[viewType]!!
            )
        )
    }

    override fun getItemCount(): Int {
        // Check if cached total count, because we do NOT expect it be calculated every time.
        if (_cachedTotalCount != null)
            return _cachedTotalCount!!
        // Not cached, so count the items for all sections
        if (_cachedNumberOfSections == null)
            _cachedNumberOfSections = datasource.get()?.recyclerViewNumberOfSections(recyclerView!!)
        var totalCount = 0
        for (i in 0..<_cachedNumberOfSections!!) {
            if (!_cachedSectionItemCount.containsKey(i)) {
                _cachedSectionItemCount[i] =
                    datasource.get()?.recyclerViewNumberOfItems(recyclerView!!, i) ?: 0
            }
            totalCount += _cachedSectionItemCount[i]!!
        }
        _cachedTotalCount = totalCount
        return totalCount
    }

    override fun onBindViewHolder(holder: WCell.Holder, position: Int) {
        datasource.get()?.recyclerViewConfigureCell(
            recyclerView!!,
            holder,
            positionToIndexPath(position)
        )
    }

}
