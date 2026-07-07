package org.mytonwallet.uihome.home.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.ISortableView
import org.mytonwallet.app_air.uicomponents.base.WActionBar.TitleAnimationMode
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MCollectionTab
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.uiassets.viewControllers.assets.title
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import java.lang.ref.WeakReference

/**
 * Wide-screen (tablet) counterpart of [HomePhoneAssetsCell].
 *
 * Instead of a [org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController]
 * that pages between tabs, this renders all tabs side by side in a horizontal RecyclerView, each
 * column being a [TokensVC] or [AssetsVC] (the same view controllers used as phone segments).
 *
 * Supports: per-column header (title + menu), per-column vertical scroll, tap-through, column
 * drag-reorder (long-press a header in edit mode) with per-column NFT reorder, pinned-collection
 * removal, and NFT selection mode — mirroring [HomePhoneAssetsCell] via [IHomeAssetsCell].
 */
@SuppressLint("ViewConstructor")
class HomeTabletAssetsCell(
    context: Context,
    private val pool: HomeAssetsVCPool,
    private val navigationController: WNavigationController,
    private var showingAccountId: String,
    private val heightChanged: () -> Unit,
    private val onAssetsShown: () -> Unit,
    private val onReorderingRequested: (reordering: Boolean) -> Unit,
    private val onSelectionRequested: (selectedCount: Int, shouldShowTransferActions: Boolean) -> Unit,
    private val onSelectionChanged: (
        selectedCount: Int,
        animationMode: TitleAnimationMode?,
        isInSelectionMode: Boolean,
        shouldShowTransferActions: Boolean
    ) -> Unit,
    private val onDetailsOpened: () -> Unit,
    private val onHorizontalScroll: () -> Unit,
) : WCell(context), WThemedView, WRecyclerViewAdapter.WRecyclerViewDataSource, IHomeAssetsCell,
    IHomeAssetsHost {

    companion object {
        val COLUMN_CELL = Type(1)
        const val COLUMN_WIDTH_DP = 360
        const val COLUMN_GUTTER_DP = 12
        const val TITLE_HEIGHT_DP = 24
        const val TITLE_CONTENT_GAP_DP = 6
        const val HEADER_HEIGHT_DP = TITLE_HEIGHT_DP + TITLE_CONTENT_GAP_DP
        const val TITLE_PADDING_DP = 8f
    }

    override var areAssetsShown = false
    override var onScrollToVisibleRequested: (() -> Unit)? = null

    // A column descriptor: the hosted view controller plus its header chrome.
    class Column(
        val viewController: WViewController,
        val identifier: String?,
        val title: String,
        val onMenuPressed: ((v: View) -> Unit)?,
    )

    private var columns: List<Column> = emptyList()

    private var pendingScrollOffset = 0

    private val tokensVC: TokensVC get() = pool.tokensVC
    private val collectiblesVC: AssetsVC get() = pool.collectiblesVC

    // IHomeAssetsHost ///////////////////////////////////////////////////////////////////////////////
    override fun onVcHeightChanged() = invalidateHeights()

    // Tablet shows all columns at once; per-column scroll doesn't drive cell height.
    override fun onVcScroll(vc: WViewController) {}

    override fun onVcAssetsShown(vc: TokensVC) {
        areAssetsShown = true
        onAssetsShown()
    }

    override fun onVcNftsShown(vc: AssetsVC) {
        areAssetsShown = true
        onAssetsShown()
    }

    override fun requestReordering(reordering: Boolean) = onReorderingRequested.invoke(reordering)

    // Make this cell the active host: point the pool at us and re-bind the mutable per-VC callbacks.
    override fun attachHost(pool: HomeAssetsVCPool) {
        pool.host = this
        tokensVC.onScrollToVisibleRequested = { onScrollToVisibleRequested?.invoke() }
        bindPooledAssetsVC(pool.collectiblesVC)
        columns.forEach { (it.viewController as? AssetsVC)?.let { vc -> bindPooledAssetsVC(vc) } }
    }

    // Re-point an AssetsVC's mutable callbacks at this (tablet/column) host. No segmented controller
    // here, so clear any stale back-reference left over from the phone host.
    private fun bindPooledAssetsVC(vc: AssetsVC) {
        vc.segmentedController = null
        vc.navigationController = navigationController
        vc.onShowAllTapped = { handleShowAllTapped(vc) }
        bindSelection(vc)
    }

    private val rvAdapter: WRecyclerViewAdapter by lazy {
        WRecyclerViewAdapter(WeakReference(this), arrayOf(COLUMN_CELL)).apply {
            setHasStableIds(true)
        }
    }

    override val horizontalScrollOffset: Int
        get() = recyclerView.computeHorizontalScrollOffset()

    private val recyclerView: WRecyclerView by lazy {
        WRecyclerView(context).apply {
            clipChildren = false
            clipToPadding = false
            setLayoutManager(
                object : LinearLayoutManager(context, HORIZONTAL, false) {
                    override fun requestChildRectangleOnScreen(
                        parent: RecyclerView,
                        child: View,
                        rect: android.graphics.Rect,
                        immediate: Boolean,
                        focusedChildVisible: Boolean
                    ): Boolean = false
                }
            )
            adapter = rvAdapter
            setItemAnimator(null)
            overScrollMode = OVER_SCROLL_NEVER
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                    if (rv.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                        pendingScrollOffset = rv.computeHorizontalScrollOffset()
                    }
                    if (dx != 0) onHorizontalScroll()
                }
            })
            addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                val target = pendingScrollOffset
                if (target > 0 && computeHorizontalScrollOffset() != target) {
                    (layoutManager as? LinearLayoutManager)
                        ?.scrollToPositionWithOffset(0, -target)
                }
            }
            addItemDecoration(object : RecyclerView.ItemDecoration() {
                override fun getItemOffsets(
                    outRect: android.graphics.Rect,
                    view: View,
                    parent: RecyclerView,
                    state: RecyclerView.State
                ) {
                    val position = parent.getChildAdapterPosition(view)
                    outRect.left = if (position == 0) 0 else COLUMN_GUTTER_DP.dp
                }
            })
        }
    }

    // Long-press a column header in edit mode to drag-reorder columns horizontally.
    private val itemTouchHelper by lazy {
        ItemTouchHelper(object : ItemTouchHelper.Callback() {
            override fun isLongPressDragEnabled() = false // started manually from the header
            override fun isItemViewSwipeEnabled() = false

            override fun getMovementFlags(
                rv: RecyclerView,
                holder: RecyclerView.ViewHolder
            ): Int {
                if (!dragMode) return 0
                return makeMovementFlags(ItemTouchHelper.START or ItemTouchHelper.END, 0)
            }

            override fun onMove(
                rv: RecyclerView,
                holder: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean {
                moveColumn(holder.bindingAdapterPosition, target.bindingAdapterPosition)
                return true
            }

            override fun onSwiped(holder: RecyclerView.ViewHolder, direction: Int) {}
        })
    }

    override fun setupViews() {
        super.setupViews()
        clipChildren = false
        clipToPadding = false
        addView(recyclerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setConstraints {
            allEdges(recyclerView)
        }
        itemTouchHelper.attachToRecyclerView(recyclerView)
        columns = generateColumns()
        attachHost(pool)
        columns.forEach { (it.viewController as? AssetsVC)?.onLayoutModeChanged() }
        updateTheme()
        invalidateHeights()
    }

    // CONFIGURE ///////////////////////////////////////////////////////////////////////////////////
    override fun configure(accountId: String?) {
        updateTheme()
        attachHost(pool)
        val accountId = accountId ?: return
        if (selectionAssetsVC != null && showingAccountId != accountId) {
            closeSelectionMode()
        }
        if (showingAccountId == accountId && areAssetsShown) {
            onAssetsShown()
            return
        }
        areAssetsShown = false
        pendingScrollOffset = 0
        recyclerView.scrollToPosition(0)
        showingAccountId = accountId
        pool.onAccountChanged(accountId)
        val itemsChanged = reloadTabs(true)
        tokensVC.configure(showingAccountId)
        if (itemsChanged) {
            collectiblesVC.configure(showingAccountId)
        } else {
            columns.forEach { (it.viewController as? AssetsVC)?.configure(showingAccountId) }
        }
        invalidateHeights()
    }

    // Returns true if the columns changed
    override fun reloadTabs(resetSelection: Boolean): Boolean {
        val old = columns
        val new = generateColumns()
        if (selectionAssetsVC != null && new.none { it.viewController === selectionAssetsVC }) {
            closeSelectionMode()
        }
        val changed = old.size != new.size ||
            old.zip(new).any { (o, n) -> o.identifier != n.identifier }
        if (changed) {
            columns = new
            rvAdapter.reloadData()
        }
        return changed
    }

    private fun generateColumns(): List<Column> {
        val items = mutableListOf<Column>()
        val isActiveAccount = NftStore.nftData?.accountId == showingAccountId
        val hasBlacklistNft =
            if (isActiveAccount) NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
            else WGlobalStorage.getBlacklistedNftAddresses(showingAccountId).isNotEmpty()
        val nftCollections = NftStore.getCollections(showingAccountId)
        val hiddenNFTsExist = NftStore.getHasHiddenNft(showingAccountId) || hasBlacklistNft
        val showCollectionsMenu = !nftCollections.isEmpty() || hiddenNFTsExist
        val homeNftCollections = WGlobalStorage.getHomeNftCollections(showingAccountId)

        fun tokensColumn() = Column(
            tokensVC,
            AssetsTabVC.identifierForVC(tokensVC),
            tokensVC.title ?: "",
            onMenuPressed = { v ->
                tokensVC.presentHomeAssetsMenu(v, onReorderTapped = { onReorderingRequested(true) })
            }
        )

        fun collectiblesColumn() = Column(
            collectiblesVC,
            AssetsTabVC.TAB_COLLECTIBLES,
            collectiblesVC.collectionMode.title,
            onMenuPressed = if (showCollectionsMenu) {
                { v ->
                    CollectionsMenuHelpers.presentCollectionsMenuOn(
                        showingAccountId,
                        v,
                        navigationController,
                        onReorderTapped = { onReorderingRequested(true) },
                        onSelectTapped = { openSelectionMode(collectiblesVC) }
                    )
                }
            } else null
        )

        if (!homeNftCollections.any { it.address == AssetsTabVC.TAB_COINS })
            items.add(tokensColumn())
        if (!homeNftCollections.any { it.address == AssetsTabVC.TAB_COLLECTIBLES })
            items.add(collectiblesColumn())

        if (homeNftCollections.isNotEmpty()) {
            homeNftCollections.forEach { homeNftCollection ->
                when (homeNftCollection.address) {
                    AssetsTabVC.TAB_COINS -> items.add(tokensColumn())
                    AssetsTabVC.TAB_COLLECTIBLES -> items.add(collectiblesColumn())
                    else -> {
                        val collectionMode =
                            if (homeNftCollection.address == NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION) {
                                AssetsVC.CollectionMode.TelegramGifts
                            } else {
                                nftCollections.find { it.address == homeNftCollection.address }
                                    ?.let { AssetsVC.CollectionMode.SingleCollection(collection = it) }
                            }
                        if (collectionMode != null) {
                            // Pinned VC comes from the shared pool (survives layout switches); its
                            // callbacks are (re)bound in attachHost().
                            val vc = pool.pinnedVC(collectionMode)
                            bindPooledAssetsVC(vc)
                            items.add(
                                Column(
                                    vc,
                                    AssetsTabVC.identifierForVC(vc),
                                    collectionMode.title,
                                    onMenuPressed = { v ->
                                        CollectionsMenuHelpers.presentPinnedCollectionMenuOn(
                                            v,
                                            collectionMode,
                                            onReorderTapped = { onReorderingRequested(true) },
                                            onSelectTapped = { openSelectionMode(vc) },
                                            onRemoveTapped = { mode -> remove(mode) }
                                        )
                                    },
                                )
                            )
                        }
                    }
                }
            }
        }
        return items
    }

    // HEIGHT //////////////////////////////////////////////////////////////////////////////////////
    private fun columnContentHeight(vc: WViewController): Int = when (vc) {
        is TokensVC -> vc.calculatedHeight
        is AssetsVC -> vc.currentHeight ?: 0
        else -> 0
    }

    private fun invalidateHeights() {
        val maxContent = columns.maxOfOrNull { columnContentHeight(it.viewController) } ?: 0
        val newHeight = if (maxContent > 0) HEADER_HEIGHT_DP.dp + maxContent else 0
        if (newHeight != layoutParams?.height) {
            updateLayoutParams { height = newHeight }
            heightChanged()
        }
        // Let each visible column fill the cell height so the tallest one drives the rest.
        for (i in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(i) as? ColumnCell ?: continue
            if (child.layoutParams.height != MATCH_PARENT)
                child.updateLayoutParams { height = MATCH_PARENT }
        }
    }

    // THEME ///////////////////////////////////////////////////////////////////////////////////////
    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        _isDarkThemeApplied = ThemeManager.isDark
        columns.forEach { it.viewController.updateTheme() }
        for (i in 0 until recyclerView.childCount) {
            (recyclerView.getChildAt(i) as? ColumnCell)?.updateTheme()
        }
    }

    override fun updateSegmentItemsTheme() {
        columns.forEach { it.viewController.updateTheme() }
    }

    // LIFECYCLE / PUBLIC SURFACE (mirrors HomePhoneAssetsCell) /////////////////////////////////////
    override fun scrollToFirst() {
        recyclerView.smoothScrollToPosition(0)
    }

    override fun setAnimations(paused: Boolean) {
        columns.forEach {
            val vc = it.viewController
            if (paused) {
                (vc as? TokensVC)?.onPartiallyVisible()
                (vc as? AssetsVC)?.onPartiallyVisible()
            } else {
                (vc as? TokensVC)?.onFullyVisible()
                (vc as? AssetsVC)?.onFullyVisible()
            }
        }
    }

    // Detach only: unmount the hosted column views; does NOT destroy the pooled VCs (the pool owns
    // their teardown).
    override fun onDestroy() {
        if (pool.host === this) pool.host = null
        for (i in 0 until recyclerView.childCount) {
            (recyclerView.getChildAt(i) as? ColumnCell)?.detachContent()
        }
        columns.forEach { (it.viewController.view.parent as? ViewGroup)?.removeView(it.viewController.view) }
    }

    override val isDraggingCollectible: Boolean
        get() = recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE ||
            columns.any { (it.viewController as? AssetsVC)?.isDragging == true }

    // EDIT / DRAG-REORDER (Phase 2) ///////////////////////////////////////////////////////////////
    private var dragMode = false

    // Column order captured when entering edit mode, to restore it if the user cancels.
    private var preEditColumns: List<Column>? = null

    override val isInDragMode: Boolean get() = dragMode

    // In edit mode, reorder the whole columns (tabs) by long-pressing their header, and reorder the
    // NFTs inside each collectibles column at the same time.
    override fun startSorting() {
        if (dragMode) return
        dragMode = true
        preEditColumns = columns.toList()
        columns.forEach { (it.viewController as? ISortableView)?.startSorting() }
        for (i in 0 until recyclerView.childCount) {
            (recyclerView.getChildAt(i) as? ColumnCell)?.setEditing(true)
        }
    }

    override fun endSorting(save: Boolean) {
        if (!dragMode) return
        dragMode = false
        if (save) {
            saveOrderedColumns()
            columns.forEach { (it.viewController as? AssetsVC)?.saveList() }
        } else {
            preEditColumns?.let { original ->
                val changed = original.size != columns.size ||
                    original.zip(columns).any { (o, n) -> o.identifier != n.identifier }
                if (changed) {
                    columns = original
                    rvAdapter.reloadData()
                }
            }
            columns.forEach { (it.viewController as? AssetsVC)?.reloadList() }
        }
        preEditColumns = null
        columns.forEach { (it.viewController as? ISortableView)?.endSorting() }
        for (i in 0 until recyclerView.childCount) {
            (recyclerView.getChildAt(i) as? ColumnCell)?.setEditing(false)
        }
    }

    private fun saveOrderedColumns() {
        val orderedCollections = columns.mapNotNull { column ->
            when (val vc = column.viewController) {
                is TokensVC -> MCollectionTab(MBlockchain.ton.name, AssetsTabVC.TAB_COINS)
                is AssetsVC -> when (val mode = vc.collectionMode) {
                    is AssetsVC.CollectionMode.SingleCollection ->
                        MCollectionTab(mode.collection.chain, mode.collection.address)

                    AssetsVC.CollectionMode.TelegramGifts ->
                        MCollectionTab(
                            MBlockchain.ton.name,
                            NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
                        )

                    is AssetsVC.CollectionMode.ReadOnly, null -> MCollectionTab(
                        MBlockchain.ton.name,
                        AssetsTabVC.TAB_COLLECTIBLES
                    )
                }

                else -> null
            }
        }
        AccountStore.activeAccountId?.let {
            WGlobalStorage.setHomeNftCollections(it, orderedCollections)
        }
    }

    // Move a column within the list during a drag gesture.
    private fun moveColumn(from: Int, to: Int) {
        if (from == to) return
        val list = columns.toMutableList()
        val moved = list.removeAt(from)
        list.add(to, moved)
        columns = list
        rvAdapter.notifyItemMoved(from, to)
    }

    // Remove a pinned-collection column (from its menu).
    private fun remove(collectionMode: AssetsVC.CollectionMode) {
        val index = columns.indexOfFirst { col ->
            (col.viewController as? AssetsVC)?.collectionMode?.matches(collectionMode) == true
        }
        if (index < 0) return
        val removed = columns[index]
        columns = columns.toMutableList().also { it.removeAt(index) }
        rvAdapter.reloadData()
        (removed.viewController as? AssetsVC)?.reloadList()
        AccountStore.activeAccountId?.let { accountId ->
            val homeNftCollections = WGlobalStorage.getHomeNftCollections(accountId)
            homeNftCollections.removeAll { it.address == collectionMode.collectionAddress }
            WGlobalStorage.setHomeNftCollections(accountId, homeNftCollections)
        }
        // Unpinned for good — drop the pooled VC so it isn't kept alive across switches.
        pool.evictPinned(collectionMode)
        invalidateHeights()
    }

    // SELECTION MODE (Phase 3) ////////////////////////////////////////////////////////////////////
    private var selectionAssetsVC: AssetsVC? = null
    override val isInSelectionMode: Boolean get() = selectionAssetsVC != null

    private fun bindSelection(vc: AssetsVC): AssetsVC = vc.apply {
        onSelectionRequested = { nftAddressToSelect ->
            openSelectionMode(vc, nftAddressToSelect)
        }
        onSelectionChanged = { selectedCount, animationMode, isInSelectionMode ->
            if (selectionAssetsVC === vc) {
                onSelectionChanged(
                    selectedCount,
                    animationMode,
                    isInSelectionMode,
                    vc.shouldShowSelectionTransferActions()
                )
            }
        }
    }

    private fun openSelectionMode(assetsVC: AssetsVC, nftAddressToSelect: String? = null) {
        if (selectionAssetsVC !== assetsVC) {
            selectionAssetsVC?.closeSelectionMode()
        }
        selectionAssetsVC = assetsVC
        assetsVC.openSelectionMode(nftAddressToSelect)
        onSelectionRequested(
            assetsVC.selectedCount(),
            assetsVC.shouldShowSelectionTransferActions()
        )
    }

    private fun handleShowAllTapped(assetsVC: AssetsVC) {
        if (selectionAssetsVC === assetsVC) {
            onDetailsOpened()
        }
    }

    override fun closeSelectionMode() {
        val vc = selectionAssetsVC ?: return
        selectionAssetsVC = null
        vc.closeSelectionMode()
    }

    override fun hideSelectedAssets() {
        selectionAssetsVC?.hideSelectedAssets()
    }

    override fun selectAllVisibleAssets() {
        selectionAssetsVC?.selectAllVisibleAssets()
    }

    override fun sendSelectedNfts(): Boolean = selectionAssetsVC?.sendSelectedNfts() ?: false

    override fun burnSelectedNfts(): Boolean = selectionAssetsVC?.burnSelectedNfts() ?: false

    // RECYCLER VIEW ///////////////////////////////////////////////////////////////////////////////
    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = columns.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): Type =
        COLUMN_CELL

    override fun recyclerViewCellView(rv: RecyclerView, cellType: Type): WCell =
        ColumnCell(context)

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: Holder,
        indexPath: IndexPath
    ) {
        val column = columns.getOrNull(indexPath.row) ?: return
        (cellHolder.cell as ColumnCell).configure(column)
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String =
        columns.getOrNull(indexPath.row)?.identifier ?: "${indexPath.row}"

    // COLUMN CELL /////////////////////////////////////////////////////////////////////////////////
    @SuppressLint("ViewConstructor")
    private inner class ColumnCell(context: Context) : WCell(context), WThemedView {
        private val titleLabel = WLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setSingleLine()
            gravity = android.view.Gravity.CENTER_VERTICAL
            setPaddingDp(TITLE_PADDING_DP, 0f, TITLE_PADDING_DP, 0f)
        }
        private val headerView = WView(context).apply {
            addView(titleLabel, LayoutParams(WRAP_CONTENT, TITLE_HEIGHT_DP.dp))
            setConstraints {
                toTop(titleLabel)
                toStart(titleLabel, 16f - TITLE_PADDING_DP)
            }
        }
        private val contentContainer = WFrameLayout(context)

        init {
            layoutParams = LayoutParams(COLUMN_WIDTH_DP.dp, MATCH_PARENT)
            clipChildren = false
            clipToPadding = false
            addView(headerView, LayoutParams(MATCH_PARENT, HEADER_HEIGHT_DP.dp))
            addView(contentContainer, LayoutParams(MATCH_PARENT, 0))
            setConstraints {
                toTop(headerView)
                toCenterX(headerView)
                topToBottom(contentContainer, headerView)
                toBottom(contentContainer)
                toCenterX(contentContainer)
            }
            // In edit mode, long-pressing the header picks the column up for drag-reorder.
            headerView.setOnLongClickListener {
                if (!dragMode) return@setOnLongClickListener false
                recyclerView.findContainingViewHolder(this)?.let { holder ->
                    itemTouchHelper.startDrag(holder)
                }
                true
            }
        }

        private var boundColumn: Column? = null

        fun detachContent() {
            contentContainer.removeAllViews()
            boundColumn = null
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            updateTheme()
        }

        fun setEditing(editing: Boolean) {
            headerView.isLongClickable = editing
            // Disable the title tap-to-menu while editing so long-press-to-drag isn't ambiguous.
            titleLabel.isClickable = !editing && boundColumn?.onMenuPressed != null
            if (editing) startShake() else stopShake()
        }

        // Shake the column header in edit mode to signal it's reorderable (mirrors the phone tab pills).
        private var shakeAnimator: android.animation.ObjectAnimator? = null
        private fun startShake() {
            if (shakeAnimator?.isRunning == true) return
            shakeAnimator = android.animation.ObjectAnimator.ofFloat(
                headerView, "rotation", 0f, -0.6f, 0.6f, -0.6f, 0.6f, 0f
            ).apply {
                duration = AnimationConstants.SLOW_ANIMATION
                repeatCount = android.animation.ObjectAnimator.INFINITE
                interpolator = android.view.animation.LinearInterpolator()
                start()
            }
        }

        private fun stopShake() {
            shakeAnimator?.cancel()
            shakeAnimator = null
            headerView.rotation = 0f
        }

        fun configure(column: Column) {
            boundColumn = column
            applyTitle(column.title, hasMenu = column.onMenuPressed != null)
            titleLabel.isClickable = !dragMode && column.onMenuPressed != null
            titleLabel.setOnClickListener(
                if (column.onMenuPressed != null) {
                    { v -> column.onMenuPressed.invoke(v) }
                } else null
            )
            setEditing(dragMode)
            if (column.onMenuPressed != null)
                titleLabel.addRippleEffect(WColor.BackgroundRipple.color, 12f.dp)
            else
                titleLabel.background = null
            updateLayoutParams { width = COLUMN_WIDTH_DP.dp }
            val vcView = column.viewController.view
            if (vcView.parent !== contentContainer) {
                (vcView.parent as? ViewGroup)?.removeView(vcView)
                contentContainer.removeAllViews()
                contentContainer.addView(
                    vcView,
                    FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                )
            }
            (column.viewController as? TokensVC)?.onFullyVisible()
            (column.viewController as? AssetsVC)?.onFullyVisible()
            if (dragMode)
                (column.viewController as? ISortableView)?.startSorting()
        }

        private fun applyTitle(title: String, hasMenu: Boolean) {
            if (!hasMenu) {
                titleLabel.text = title
                return
            }
            val icon = context.requireDrawableCompat(
                org.mytonwallet.app_air.uicomponents.R.drawable.ic_expand
            ).apply {
                setTint(WColor.SecondaryText.color)
                setBounds(0, 0, 14.dp, 14.dp)
            }
            titleLabel.text = SpannableStringBuilder("$title​").apply {
                setSpan(
                    VerticalImageSpan(icon, startPadding = 0.dp, endPadding = 0),
                    length - 1,
                    length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        }

        override fun updateTheme() {
            contentContainer.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp,
                true
            )
            titleLabel.setTextColor(WColor.PrimaryText.color)
            boundColumn?.let { applyTitle(it.title, hasMenu = it.onMenuPressed != null) }
        }
    }
}
