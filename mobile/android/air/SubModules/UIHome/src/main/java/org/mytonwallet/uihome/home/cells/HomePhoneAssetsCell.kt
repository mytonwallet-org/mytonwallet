package org.mytonwallet.uihome.home.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.title
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uicomponents.base.ISortableController
import org.mytonwallet.app_air.uicomponents.base.ISortableView
import org.mytonwallet.app_air.uicomponents.base.WActionBar.TitleAnimationMode
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.animateHeight
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItemVC
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.updateThemeForChildren
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MCollectionTab
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class HomePhoneAssetsCell(
    context: Context,
    private val pool: HomeAssetsVCPool,
    private val window: WWindow,
    private val navigationController: WNavigationController,
    private var showingAccountId: String,
    private val heightChanged: () -> Unit,
    private val onAssetsShown: () -> Unit,
    // Allows home screen to know we are in editing mode, and get the end decision
    private val onReorderingRequested: (reordering: Boolean) -> Unit,
    private val onForceEndReorderingRequested: () -> Unit,
    private val onSelectionRequested: (selectedCount: Int, shouldShowTransferActions: Boolean) -> Unit,
    private val onSelectionChanged: (
        selectedCount: Int,
        animationMode: TitleAnimationMode?,
        isInSelectionMode: Boolean,
        shouldShowTransferActions: Boolean
    ) -> Unit,
    private val onDetailsOpened: () -> Unit,
) : WCell(context), WThemedView, ISortableController, IHomeAssetsCell, IHomeAssetsHost {

    override var areAssetsShown = false
    private var selectionAssetsVC: AssetsVC? = null
    override var onScrollToVisibleRequested: (() -> Unit)? = null

    private val tokensVC: TokensVC get() = pool.tokensVC
    private val collectiblesVC: AssetsVC get() = pool.collectiblesVC

    // IHomeAssetsHost ///////////////////////////////////////////////////////////////////////////////
    override fun onVcHeightChanged() = updateHeight()

    override fun onVcScroll(vc: WViewController) = updateHeight()

    override fun onVcAssetsShown(vc: TokensVC) {
        if (segmentedController.currentItem === vc) {
            areAssetsShown = true
            onAssetsShown()
        }
    }

    override fun onVcNftsShown(vc: AssetsVC) {
        if (segmentedController.currentItem === vc) {
            areAssetsShown = true
            onAssetsShown()
        }
    }

    override fun requestReordering(reordering: Boolean) = onReorderingRequested.invoke(reordering)

    // Make this cell the active host: point the pool at us and re-bind the mutable per-VC callbacks.
    override fun attachHost(pool: HomeAssetsVCPool) {
        pool.host = this
        tokensVC.onScrollToVisibleRequested = { onScrollToVisibleRequested?.invoke() }
        segmentedController.items.forEach { item ->
            (item.viewController as? AssetsVC)?.let { vc ->
                bindPooledAssetsVC(vc)
                vc.segmentedController = segmentedController
            }
        }
    }

    private fun bindPooledAssetsVC(vc: AssetsVC) {
        vc.onShowAllTapped = { handleShowAllTapped(vc) }
        bindSelection(vc)
    }

    private val segmentedController: WSegmentedController by lazy {
        val segmentedController = WSegmentedController(
            navigationController,
            generateSegmentItems(),
            isFullScreen = false,
            applySideGutters = false,
            navHeight = 56.dp,
            onOffsetChange = { _, _ ->
                updateHeight()
            },
            onItemsReordered = null,
            onReorderingStarted = {
                onReorderingRequested(true)
            },
            onForceEndReorderingRequested = {
                onForceEndReorderingRequested()
            },
            ownsItems = false,
        ).apply {
            setDragAllowed(true)
        }
        segmentedController
    }

    override fun setupViews() {
        super.setupViews()

        attachHost(pool)
        segmentedController.items.forEach {
            (it.viewController as? AssetsVC)?.onLayoutModeChanged()
        }
        addView(segmentedController, LayoutParams(MATCH_PARENT, 0))
        setConstraints {
            toBottom(segmentedController)
            toTop(segmentedController)
        }

        updateHeight()
    }

    private var _isDarkThemeApplied: Boolean? = null
    private var _lastBigRadius: Float? = null
    override fun updateTheme() {
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        val radiusChanged = _lastBigRadius != ViewConstants.BLOCK_RADIUS
        _isDarkThemeApplied = ThemeManager.isDark
        _lastBigRadius = ViewConstants.BLOCK_RADIUS
        if (segmentedController.isTinted || darkModeChanged)
            segmentedController.updateTheme()
        if (darkModeChanged || radiusChanged)
            segmentedController.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp,
                true
            )
        segmentedController.items.forEach {
            it.viewController.updateTheme()
            updateThemeForChildren(it.viewController.view, onlyTintedViews = !darkModeChanged)
        }
    }

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

    override fun updateSegmentItemsTheme() {
        segmentedController.updateTheme()
        segmentedController.items.forEach {
            it.viewController.updateTheme()
        }
    }

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
        showingAccountId = accountId
        pool.onAccountChanged(accountId)
        segmentedController.updateProtectedView()
        val itemsChanged = reloadTabs(true)
        tokensVC.configure(showingAccountId)
        if (itemsChanged) {
            collectiblesVC.configure(showingAccountId)
        } else {
            segmentedController.items.forEach {
                (it.viewController as? AssetsVC)?.configure(showingAccountId)
            }
        }
    }

    // Returns true if the items are changed
    override fun reloadTabs(resetSelection: Boolean): Boolean {
        val oldSegmentItems = segmentedController.items
        val newSegmentItems = generateSegmentItems()
        if (selectionAssetsVC != null && newSegmentItems.none { it.viewController === selectionAssetsVC }) {
            closeSelectionMode()
        }
        val itemsChanged =
            newSegmentItems.size != segmentedController.items.size ||
                newSegmentItems.zip(oldSegmentItems).any { (new, old) ->
                    if (old.viewController is TokensVC && new.viewController !is TokensVC)
                        return@any true
                    if (old.viewController is AssetsVC) {
                        if (new.viewController !is AssetsVC)
                            return@any true
                        if ((old.viewController as AssetsVC).collectionMode != (new.viewController as AssetsVC).collectionMode)
                            return@any true
                    }
                    return@any false
                }
        if (itemsChanged) {
            val prevActiveIndex = segmentedController.currentOffset.toInt()
            segmentedController.updateItems(newSegmentItems)
            segmentedController.setActiveIndex(min(newSegmentItems.size - 1, prevActiveIndex))
        } else {
            updateCollectiblesClick()
        }
        if (resetSelection)
            segmentedController.setActiveIndex(0)
        return itemsChanged
    }

    fun generateSegmentItems(): MutableList<WSegmentedControllerItem> {
        val items = mutableListOf<WSegmentedControllerItem>()
        val isActiveAccount = NftStore.nftData?.accountId == showingAccountId
        val hasBlacklistNft =
            if (isActiveAccount) NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
            else
                WGlobalStorage.getBlacklistedNftAddresses(showingAccountId).isNotEmpty()
        val nftCollections = NftStore.getCollections(showingAccountId)

        val hiddenNFTsExist =
            NftStore.getHasHiddenNft(showingAccountId) || hasBlacklistNft
        val showCollectionsMenu = !nftCollections.isEmpty() || hiddenNFTsExist
        val homeNftCollections =
            WGlobalStorage.getHomeNftCollections(showingAccountId)
        if (!homeNftCollections.any { it.address == AssetsTabVC.TAB_COINS })
            items.add(
                WSegmentedControllerItem(
                    tokensVC,
                    identifier = AssetsTabVC.identifierForVC(tokensVC),
                    onMenuPressed = { v ->
                        tokensVC.presentHomeAssetsMenu(
                            v,
                            onReorderTapped = { onReorderingRequested(true) }
                        )
                    }
                )
            )
        if (!homeNftCollections.any { it.address == AssetsTabVC.TAB_COLLECTIBLES })
            items.add(
                WSegmentedControllerItem(
                    collectiblesVC,
                    identifier = AssetsTabVC.TAB_COLLECTIBLES,
                    onMenuPressed = if (showCollectionsMenu) {
                        { v ->
                            CollectionsMenuHelpers.presentCollectionsMenuOn(
                                showingAccountId,
                                v,
                                navigationController,
                                onReorderTapped = {
                                    onReorderingRequested(true)
                                },
                                onSelectTapped = {
                                    openSelectionMode(collectiblesVC)
                                }
                            )
                        }
                    } else {
                        null
                    }
                )
            )

        if (homeNftCollections.isNotEmpty()) {
            items.addAll(homeNftCollections.mapNotNull { homeNftCollection ->
                when (homeNftCollection.address) {
                    AssetsTabVC.TAB_COINS -> {
                        WSegmentedControllerItem(
                            tokensVC,
                            AssetsTabVC.identifierForVC(tokensVC),
                            onMenuPressed = { v ->
                                tokensVC.presentHomeAssetsMenu(
                                    v,
                                    onReorderTapped = { onReorderingRequested(true) }
                                )
                            }
                        )
                    }

                    AssetsTabVC.TAB_COLLECTIBLES -> {
                        WSegmentedControllerItem(
                            collectiblesVC,
                            identifier = AssetsTabVC.TAB_COLLECTIBLES,
                            onMenuPressed = if (showCollectionsMenu) { v ->
                                CollectionsMenuHelpers.presentCollectionsMenuOn(
                                    showingAccountId,
                                    v,
                                    navigationController,
                                    onReorderTapped = {
                                        onReorderingRequested(true)
                                    },
                                    onSelectTapped = {
                                        openSelectionMode(collectiblesVC)
                                    }
                                )
                            } else null)
                    }

                    else -> {
                        val collectionMode =
                            if (homeNftCollection.address == NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION) {
                                AssetsVC.CollectionMode.TelegramGifts
                            } else {
                                nftCollections.find { it.address == homeNftCollection.address }
                                    ?.let {
                                        AssetsVC.CollectionMode.SingleCollection(
                                            collection = it
                                        )
                                    }
                            }
                        if (collectionMode != null) {
                            // Pinned VC comes from the shared pool (survives layout switches); its
                            // callbacks are (re)bound in attachHost().
                            val vc = pool.pinnedVC(collectionMode)
                            bindPooledAssetsVC(vc)
                            WSegmentedControllerItem(
                                viewController = vc,
                                identifier = AssetsTabVC.identifierForVC(vc),
                                onRemovePressed = {
                                    remove(collectionMode)
                                },
                                onMenuPressed = { v ->
                                    CollectionsMenuHelpers.presentPinnedCollectionMenuOn(
                                        v,
                                        collectionMode,
                                        onReorderTapped = {
                                            onReorderingRequested(true)
                                        },
                                        onSelectTapped = {
                                            openSelectionMode(vc)
                                        },
                                        onRemoveTapped = {
                                            window.topViewController?.showAlert(
                                                LocaleController.getString("Remove Tab"),
                                                LocaleController.getStringWithKeyValues(
                                                    "Are you sure you want to unpin %tab%?",
                                                    listOf(
                                                        Pair(
                                                            "%tab%",
                                                            collectionMode.title
                                                        )
                                                    )
                                                ),
                                                LocaleController.getString("Yes"),
                                                buttonPressed = {
                                                    remove(collectionMode)
                                                    val homeNftCollections =
                                                        WGlobalStorage.getHomeNftCollections(
                                                            AccountStore.activeAccountId!!
                                                        )
                                                    homeNftCollections.removeAll { it.address == collectionMode.collectionAddress }
                                                    WGlobalStorage.setHomeNftCollections(
                                                        AccountStore.activeAccountId!!,
                                                        homeNftCollections
                                                    )
                                                    //WalletCore.notifyEvent(WalletEvent.HomeNftCollectionsUpdated)
                                                },
                                                secondaryButton = LocaleController.getString(
                                                    "Cancel"
                                                ),
                                                primaryIsDanger = true
                                            )
                                        }
                                    )
                                }
                            )
                        } else {
                            null
                        }
                    }
                }
            })
        }
        return items
    }

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    fun updateCollectiblesClick() {
        backgroundExecutor.execute {
            val isActiveAccount = NftStore.nftData?.accountId == showingAccountId
            val hasBlacklistNft =
                if (isActiveAccount) NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
                else
                    WGlobalStorage.getBlacklistedNftAddresses(showingAccountId).isNotEmpty()
            val hiddenNFTsExist = NftStore.getHasHiddenNft(showingAccountId) || hasBlacklistNft
            val showCollectionsMenu = !NftStore.getCollections().isEmpty() || hiddenNFTsExist
            segmentedController.updateOnMenuPressed(
                identifier = AssetsTabVC.TAB_COLLECTIBLES,
                onMenuPressed = if (showCollectionsMenu) {
                    { v ->
                        CollectionsMenuHelpers.presentCollectionsMenuOn(
                            showingAccountId,
                            v,
                            navigationController,
                            onReorderTapped = {
                                onReorderingRequested(true)
                            },
                            onSelectTapped = {
                                openSelectionMode(collectiblesVC)
                            }
                        )
                    }
                } else {
                    null
                }
            )
        }
    }

    fun getViewHeight(vc: WViewController): Int = when (vc) {
        is TokensVC -> vc.calculatedHeight
        is AssetsVC -> vc.currentHeight ?: 0
        else -> 0
    }

    override fun setAnimations(paused: Boolean) {
        segmentedController.items.forEach { item ->
            (item.viewController as? WSegmentedControllerItemVC)?.apply {
                if (paused) onPartiallyVisible() else onFullyVisible()
            }
        }
    }

    private fun updateHeight() {
        val prevHeight = layoutParams.height
        val newHeight: Int
        val items = segmentedController.items
        val offset = segmentedController.currentOffset
        val currentIndex = offset.toInt()

        if (currentIndex > items.size - 1) {
            newHeight = 0
        } else {
            val firstHeight = getViewHeight(items[currentIndex].viewController)
            val secondHeight =
                if (offset > currentIndex) getViewHeight(items[currentIndex + 1].viewController) else 0
            val secondEffective = if (secondHeight > 0) secondHeight else firstHeight

            newHeight = if (firstHeight > 0) {
                val interpolatedHeight =
                    firstHeight + (offset - currentIndex) * (secondEffective - firstHeight)
                (53.dp + interpolatedHeight).roundToInt()
            } else
                0
        }

        if (newHeight != prevHeight) {
            updateLayoutParams {
                height = newHeight
            }
            heightChanged()
        }
    }

    override fun scrollToFirst() {
        segmentedController.scrollToFirst()
    }

    override fun onDestroy() {
        if (pool.host === this) pool.host = null
        segmentedController.onDestroy()
    }

    override val isDraggingCollectible: Boolean
        get() {
            return (segmentedController.currentItem as? AssetsVC)?.isDragging == true
        }

    fun remove(collectionMode: AssetsVC.CollectionMode) {
        val currentItems = segmentedController.items
        val itemToRemoveIndex = currentItems.indexOfFirst { item ->
            when (val vc = item.viewController) {
                is AssetsVC -> vc.collectionMode?.matches(collectionMode) ?: false
                else -> false
            }
        }
        if (itemToRemoveIndex < 0)
            return
        if (itemToRemoveIndex == segmentedController.currentOffset.toInt()) {
            val nextHeight =
                getViewHeight(
                    segmentedController.items[max(
                        0,
                        itemToRemoveIndex - 1
                    )].viewController
                ) + 56.dp
            animateHeight(nextHeight)
        }
        val removedItem = segmentedController.removeItem(itemToRemoveIndex, onCompletion = {
            if (isInDragMode) {
                (segmentedController.currentItem as? AssetsVC)?.startSorting()
            }
            pool.evictPinned(collectionMode)
        })
        (removedItem?.viewController as? AssetsVC)?.reloadList()
    }

    private fun saveOrderedItems() {
        val items = segmentedController.items
        val orderedCollections = items.mapNotNull { item ->
            when (val vc = item.viewController) {
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
        WGlobalStorage.setHomeNftCollections(
            AccountStore.activeAccountId!!,
            orderedCollections
        )
    }

    override val isInDragMode: Boolean
        get() {
            return segmentedController.isInDragMode
        }

    override val isInSelectionMode: Boolean
        get() = selectionAssetsVC != null

    private fun handleShowAllTapped(assetsVC: AssetsVC) {
        if (selectionAssetsVC === assetsVC) {
            onDetailsOpened()
        }
    }

    private fun openSelectionMode(
        assetsVC: AssetsVC,
        nftAddressToSelect: String? = null
    ) {
        if (selectionAssetsVC !== assetsVC) {
            val previousAssetsVC = selectionAssetsVC
            selectionAssetsVC = null
            previousAssetsVC?.closeSelectionMode()
        }
        val selectedIndex = segmentedController.items.indexOfFirst { item ->
            item.viewController === assetsVC
        }
        if (selectedIndex >= 0 && segmentedController.currentIndex != selectedIndex) {
            segmentedController.setActiveIndex(selectedIndex)
        }
        selectionAssetsVC = assetsVC
        assetsVC.openSelectionMode(nftAddressToSelect)
        segmentedController.lockTab()
        onSelectionRequested(
            assetsVC.selectedCount(),
            assetsVC.shouldShowSelectionTransferActions()
        )
    }

    override fun closeSelectionMode() {
        val assetsVC = selectionAssetsVC ?: return
        selectionAssetsVC = null
        assetsVC.closeSelectionMode()
        segmentedController.unlockTab()
    }

    override fun hideSelectedAssets() {
        selectionAssetsVC?.hideSelectedAssets()
    }

    override fun selectAllVisibleAssets() {
        selectionAssetsVC?.selectAllVisibleAssets()
    }

    override fun sendSelectedNfts(): Boolean {
        return selectionAssetsVC?.sendSelectedNfts() ?: false
    }

    override fun burnSelectedNfts(): Boolean {
        return selectionAssetsVC?.burnSelectedNfts() ?: false
    }

    private fun finalizeSort(save: Boolean) {
        if (!segmentedController.isInDragMode)
            return
        var animateHeaderSegmentedControl: Boolean
        if (save) {
            saveOrderedItems()
            animateHeaderSegmentedControl = true
        } else {
            segmentedController.preeditItems?.let { originalItems ->
                val currentItems = segmentedController.items
                val itemsChanged = originalItems.size != currentItems.size ||
                    originalItems.zip(currentItems).any { (original, current) ->
                        original.identifier != current.identifier
                    }
                animateHeaderSegmentedControl = !itemsChanged
                segmentedController.updateItems(
                    originalItems,
                    fadeAnimation = itemsChanged,
                    keepSelection = true,
                    onUpdated = {
                        if (itemsChanged)
                            segmentedController.endSortingClearSegmentedControl(animated = false)
                    }
                )
            } ?: run {
                animateHeaderSegmentedControl = true
            }
        }
        segmentedController.exitDragMode()
        if (animateHeaderSegmentedControl)
            segmentedController.endSortingClearSegmentedControl(animated = true)
        (segmentedController.currentItem as? ISortableView)?.endSorting()
        (segmentedController.currentItem as? AssetsVC)?.apply {
            if (save)
                saveList()
            else
                reloadList()
        }
    }

    override fun startSorting() {
        segmentedController.startSorting()
        (segmentedController.currentItem as? ISortableView)?.startSorting()
    }

    override fun endSorting(save: Boolean) {
        finalizeSort(save)
    }
}
