package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SwitchCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.LastItemPaddingDecoration
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells.ChainDisplayCell
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells.ChainDisplayDescriptionCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MChainDisplayConfiguration
import org.mytonwallet.app_air.walletcore.models.MChainDisplayMode
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class ChainDisplaySettingsVC(context: Context) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver {
    @Suppress("PropertyName")
    override val TAG = "ChainDisplaySettings"

    companion object {
        private const val SECTION_SORTING = 0
        private const val SECTION_SORTING_DESCRIPTION = 1
        private const val SECTION_CHAINS = 2
        private const val SECTION_CHAINS_DESCRIPTION = 3

        private val SORTING_CELL = WCell.Type(1)
        private val DESCRIPTION_CELL = WCell.Type(2)
        private val CHAIN_CELL = WCell.Type(3)
        private const val DRAG_ELEVATION = 8f
    }

    override val shouldDisplayBottomBar = true

    private var configuration: MChainDisplayConfiguration =
        AccountStore.assetsAndActivityData.chainDisplayConfiguration
            ?: MChainDisplayConfiguration()
    private var chains = mutableListOf<MBlockchain>()
    private var visibleChains = emptySet<String>()
    private var didReorder = false

    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(SORTING_CELL, DESCRIPTION_CELL, CHAIN_CELL)
    ).apply {
        setHasStableIds(true)
    }

    private val chainSectionBackgroundDecoration = object : RecyclerView.ItemDecoration() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val bounds = RectF()

        override fun onDraw(canvas: Canvas, parent: RecyclerView, state: RecyclerView.State) {
            super.onDraw(canvas, parent, state)
            if (chains.isEmpty()) return

            val firstChainPosition = rvAdapter.indexPathToPosition(IndexPath(SECTION_CHAINS, 0))
            val lastChainPosition = firstChainPosition + chains.lastIndex
            val anchor = (0 until parent.childCount)
                .map { parent.getChildAt(it) }
                .firstOrNull {
                    parent.getChildAdapterPosition(it) in firstChainPosition..lastChainPosition
                } ?: return
            val anchorPosition = parent.getChildAdapterPosition(anchor)
            val rowHeight = anchor.height.toFloat()
            val top = anchor.top - (anchorPosition - firstChainPosition) * rowHeight

            bounds.set(
                anchor.left.toFloat(),
                top,
                anchor.right.toFloat(),
                top + chains.size * rowHeight
            )
            paint.color = WColor.Background.color
            val radius = ViewConstants.BLOCK_RADIUS.dp
            canvas.drawRoundRect(bounds, radius, radius, paint)
        }
    }

    private val itemTouchHelper = ItemTouchHelper(object : ItemTouchHelper.SimpleCallback(
        ItemTouchHelper.UP or ItemTouchHelper.DOWN,
        0
    ) {
        override fun getMovementFlags(
            recyclerView: RecyclerView,
            viewHolder: RecyclerView.ViewHolder
        ): Int {
            val position = viewHolder.bindingAdapterPosition
            if (position == RecyclerView.NO_POSITION ||
                configuration.displayMode != MChainDisplayMode.MANUAL ||
                rvAdapter.positionToIndexPath(position).section != SECTION_CHAINS
            ) {
                return makeMovementFlags(0, 0)
            }
            return makeMovementFlags(ItemTouchHelper.UP or ItemTouchHelper.DOWN, 0)
        }

        override fun onMove(
            recyclerView: RecyclerView,
            viewHolder: RecyclerView.ViewHolder,
            target: RecyclerView.ViewHolder
        ): Boolean {
            val fromPosition = viewHolder.bindingAdapterPosition
            val toPosition = target.bindingAdapterPosition
            if (fromPosition == RecyclerView.NO_POSITION ||
                toPosition == RecyclerView.NO_POSITION
            ) {
                return false
            }
            val from = rvAdapter.positionToIndexPath(fromPosition)
            val to = rvAdapter.positionToIndexPath(toPosition)
            if (from.section != SECTION_CHAINS || to.section != SECTION_CHAINS) return false

            val movedChain = chains.removeAt(from.row)
            chains.add(to.row, movedChain)
            rvAdapter.notifyItemMoved(fromPosition, toPosition)
            didReorder = true
            return true
        }

        override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) = Unit

        override fun isLongPressDragEnabled(): Boolean = false

        override fun onSelectedChanged(viewHolder: RecyclerView.ViewHolder?, actionState: Int) {
            super.onSelectedChanged(viewHolder, actionState)
            if (actionState == ItemTouchHelper.ACTION_STATE_DRAG) {
                viewHolder?.itemView?.apply {
                    elevation = DRAG_ELEVATION.dp
                    alpha = 0.8f
                }
            }
        }

        override fun clearView(recyclerView: RecyclerView, viewHolder: RecyclerView.ViewHolder) {
            super.clearView(recyclerView, viewHolder)
            viewHolder.itemView.apply {
                elevation = 0f
                alpha = 1f
            }
            if (didReorder) {
                didReorder = false
                persistManualOrder()
            }
        }
    })

    private val recyclerView: WRecyclerView by lazy {
        WRecyclerView(this).apply {
            adapter = rvAdapter
            setLayoutManager(LinearLayoutManagerAccurateOffset(context))
            addItemDecoration(chainSectionBackgroundDecoration)
            addItemDecoration(
                LastItemPaddingDecoration(navigationController?.bottomInset ?: 0)
            )
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    super.onScrolled(recyclerView, dx, dy)
                    if (dx != 0 || dy != 0) updateBlurViews(recyclerView)
                }

                override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                    super.onScrollStateChanged(recyclerView, newState)
                    if (newState != RecyclerView.SCROLL_STATE_IDLE) updateBlurViews(recyclerView)
                }
            })
        }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Blockchains"))
        setupNavBar(true)

        normalizeManualOrderForPresentation()
        rebuildChains()

        view.addView(recyclerView, LayoutParams(MATCH_PARENT, 0))
        recyclerView.clipToPadding = false
        view.setConstraints {
            toTop(recyclerView)
            toCenterX(recyclerView)
            toBottom(recyclerView)
        }
        itemTouchHelper.attachToRecyclerView(recyclerView)

        updateTheme()
        WalletCore.registerObserver(this)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.updateVisibleCells { cell ->
            (cell as? org.mytonwallet.app_air.uicomponents.widgets.WThemedView)?.updateTheme()
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            navigationBar?.calculatedMinHeight ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0
        )
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    override fun onDestroy() {
        super.onDestroy()
        itemTouchHelper.attachToRecyclerView(null)
        WalletCore.unregisterObserver(this)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 4

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int =
        if (section == SECTION_CHAINS) chains.size else 1

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        when (indexPath.section) {
            SECTION_SORTING -> SORTING_CELL
            SECTION_SORTING_DESCRIPTION, SECTION_CHAINS_DESCRIPTION -> DESCRIPTION_CELL
            else -> CHAIN_CELL
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            SORTING_CELL -> SwitchCell(
                context,
                title = LocaleController.getString("Sort by Value"),
                isChecked = configuration.displayMode == MChainDisplayMode.VALUE,
                isFirst = true,
                isLast = true,
                onChange = { isChecked ->
                    setDisplayMode(
                        if (isChecked) MChainDisplayMode.VALUE else MChainDisplayMode.MANUAL
                    )
                }
            ).apply {
                layoutParams = RecyclerView.LayoutParams(MATCH_PARENT, 56.dp)
            }

            DESCRIPTION_CELL -> ChainDisplayDescriptionCell(context)

            else -> ChainDisplayCell(
                context,
                onVisibilityChanged = ::setChainVisible,
                onReorderStarted = { cell ->
                    val holder = recyclerView.findContainingViewHolder(cell)
                    if (holder != null && configuration.displayMode == MChainDisplayMode.MANUAL) {
                        itemTouchHelper.startDrag(holder)
                    }
                },
                onMoveRequested = ::moveChain
            )
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (indexPath.section) {
            SECTION_SORTING -> {
                val cell = cellHolder.cell as SwitchCell
                val isChecked = configuration.displayMode == MChainDisplayMode.VALUE
                if (cell.isChecked != isChecked) cell.isChecked = isChecked
            }

            SECTION_SORTING_DESCRIPTION -> {
                (cellHolder.cell as ChainDisplayDescriptionCell).configure(
                    LocaleController.getString(
                        "Automatically sort and hide chains based on your portfolio."
                    )
                )
            }

            SECTION_CHAINS -> {
                val chain = chains[indexPath.row]
                val usesAutomaticAppearance =
                    configuration.displayMode == MChainDisplayMode.VALUE
                val isVisible = visibleChains.contains(chain.name)
                (cellHolder.cell as ChainDisplayCell).configure(
                    chain = chain,
                    isVisible = isVisible,
                    isSwitchEnabled = !usesAutomaticAppearance &&
                        (!isVisible || visibleChains.size > 1),
                    showsReorderControl = !usesAutomaticAppearance,
                    usesAutomaticAppearance = usesAutomaticAppearance,
                    isFirst = indexPath.row == 0,
                    isLast = indexPath.row == chains.size - 1
                )
            }

            SECTION_CHAINS_DESCRIPTION -> {
                (cellHolder.cell as ChainDisplayDescriptionCell).configure(
                    LocaleController.getString(
                        "Hidden chains will still be available to receive and send tokens, but won’t appear in the main list."
                    )
                )
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String =
        when (indexPath.section) {
            SECTION_SORTING -> "sorting"
            SECTION_SORTING_DESCRIPTION -> "sorting-description"
            SECTION_CHAINS -> "chain-${chains[indexPath.row].name}"
            else -> "chains-description"
        }

    private fun setDisplayMode(displayMode: MChainDisplayMode) {
        if (configuration.displayMode == displayMode) return

        val data = AccountStore.assetsAndActivityData
        data.saveChainDisplayMode(displayMode)
        AccountStore.updateAssetsAndActivityData(data, notify = true, saveToStorage = true)
    }

    private fun setChainVisible(chain: MBlockchain, isVisible: Boolean) {
        if (configuration.displayMode != MChainDisplayMode.MANUAL) {
            rvAdapter.reloadData()
            return
        }
        if (!isVisible && visibleChains.size <= 1) {
            rvAdapter.reloadData()
            return
        }

        val data = AccountStore.assetsAndActivityData
        data.saveChainVisible(chain.name, isVisible)
        AccountStore.updateAssetsAndActivityData(data, notify = true, saveToStorage = true)
    }

    private fun persistManualOrder() {
        if (configuration.displayMode != MChainDisplayMode.MANUAL) return
        val manualOrder = chains.map { it.name }
        val data = AccountStore.assetsAndActivityData
        data.saveChainOrder(manualOrder)
        AccountStore.updateAssetsAndActivityData(data, notify = true, saveToStorage = true)
    }

    private fun moveChain(chain: MBlockchain, offset: Int): Boolean {
        if (configuration.displayMode != MChainDisplayMode.MANUAL) return false
        val from = chains.indexOfFirst { it == chain }
        val to = from + offset
        if (from < 0 || to !in chains.indices) return false

        val fromPosition = rvAdapter.indexPathToPosition(IndexPath(SECTION_CHAINS, from))
        val toPosition = rvAdapter.indexPathToPosition(IndexPath(SECTION_CHAINS, to))
        chains.add(to, chains.removeAt(from))
        rvAdapter.notifyItemMoved(fromPosition, toPosition)
        persistManualOrder()
        return true
    }

    private fun normalizeManualOrderForPresentation() {
        if (configuration.displayMode != MChainDisplayMode.MANUAL ||
            configuration.manualOrder.isEmpty()
        ) {
            return
        }
        val accountChainOrder =
            AccountStore.activeAccount?.defaultChains()?.map { it.key }.orEmpty()
        val normalizedOrder = configuration.normalizedManualOrder(accountChainOrder)
        if (normalizedOrder == configuration.manualOrder) return

        val data = AccountStore.assetsAndActivityData
        data.saveChainOrder(normalizedOrder)
        AccountStore.updateAssetsAndActivityData(data, notify = true, saveToStorage = true)
    }

    private fun rebuildChains() {
        val snapshot = AccountStore.activeAccount?.chainDisplaySnapshot()
        chains = snapshot?.orderedChains?.mapNotNull { entry ->
            MBlockchain.valueOfOrNull(entry.key)
        }?.toMutableList() ?: mutableListOf()
        visibleChains = snapshot?.visibleChains?.map { it.key }?.toSet().orEmpty()
    }

    private fun reloadConfiguration() {
        configuration = AccountStore.assetsAndActivityData.chainDisplayConfiguration
            ?: MChainDisplayConfiguration()
        rebuildChains()
        rvAdapter.reloadData()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.AssetsAndActivityDataUpdated -> reloadConfiguration()

            WalletEvent.BalanceChanged,
            WalletEvent.BaseCurrencyChanged,
            WalletEvent.StakingDataUpdated,
            WalletEvent.TokensChanged -> {
                if (configuration.displayMode == MChainDisplayMode.VALUE ||
                    configuration.manualOrder.isEmpty()
                ) {
                    rebuildChains()
                    rvAdapter.reloadData()
                }
            }

            else -> Unit
        }
    }
}
