package org.mytonwallet.app_air.uicomponents.base

import android.annotation.SuppressLint
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.RecyclerView.NO_POSITION
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.helpers.WDefaultItemAnimator
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.walletcontext.utils.EquatableChange
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
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

    fun reloadDataWithAnimation(positionStart: Int, itemCount: Int) {
        if (rvAnimator == null) rvAnimator = recyclerView?.itemAnimator // Store initial state

        _cachedNumberOfSections = null
        _cachedSectionItemCount = HashMap()
        _cachedTotalCount = null

        recyclerView?.itemAnimator = WDefaultItemAnimator()
            .apply {
                revealDelayDuration = 20L
                changeDuration = AnimationConstants.SUPER_QUICK_ANIMATION
                addDuration = AnimationConstants.SUPER_QUICK_ANIMATION
                moveDuration = AnimationConstants.SUPER_QUICK_ANIMATION
                removeDuration = AnimationConstants.SUPER_QUICK_ANIMATION
            }
        notifyItemRangeInserted(positionStart, itemCount)
    }

    fun applyChanges(changes: List<EquatableChange<IndexPath>>) {
        changes.forEach { change ->
            when (change) {
                is EquatableChange.Insert -> {
                    val position = indexPathToPosition(change.item)
                    if (_cachedTotalCount != null)
                        _cachedTotalCount = _cachedTotalCount!! + 1
                    if (_cachedSectionItemCount.containsKey(change.item.section))
                        _cachedSectionItemCount[change.item.section] =
                            _cachedSectionItemCount[change.item.section]!! + 1
                    notifyItemInserted(position)
                }

                is EquatableChange.Delete -> {
                    val position = indexPathToPosition(change.item)
                    if (_cachedTotalCount != null)
                        _cachedTotalCount = _cachedTotalCount!! - 1
                    if (_cachedSectionItemCount.containsKey(change.item.section))
                        _cachedSectionItemCount[change.item.section] =
                            _cachedSectionItemCount[change.item.section]!! - 1
                    notifyItemRemoved(position)
                }

                is EquatableChange.Update -> {
                    val position = indexPathToPosition(change.item)
                    notifyItemChanged(position)
                }
            }
        }
    }

    fun updateVisibleCells() {
        val recyclerView = recyclerView ?: return
        for (i in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(i)
            val position = recyclerView.getChildAdapterPosition(child)
            if (position != NO_POSITION) {
                val viewHolder = recyclerView.getChildViewHolder(child)
                datasource.get()?.recyclerViewConfigureCell(
                    recyclerView,
                    viewHolder as WCell.Holder,
                    positionToIndexPath(position)
                )
            }
        }
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
