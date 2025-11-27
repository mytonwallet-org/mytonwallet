package org.mytonwallet.uihome.home.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.title
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uicomponents.base.ISortableController
import org.mytonwallet.app_air.uicomponents.base.ISortableView
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
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class HomeAssetsCell(
    context: Context,
    private val window: WWindow,
    private val navigationController: WNavigationController,
    private val heightChanged: () -> Unit,
    private val onAssetsShown: () -> Unit,
    // Allows home screen to know we are in editing mode, and get the end decision
    private val onReorderingRequested: () -> Unit,
    private val onForceEndReorderingRequested: () -> Unit,
) : WCell(context), WThemedView, ISortableController {

    private val tokensVC: TokensVC by lazy {
        val vc = TokensVC(
            context, TokensVC.Mode.HOME,
            onHeightChanged = {
                updateHeight()
            },
            onAssetsShown = onAssetsShown
        ) {
            updateHeight()
        }
        vc
    }

    private val collectiblesVC: AssetsVC by lazy {
        val vc = AssetsVC(context, AssetsVC.Mode.THUMB, injectedWindow = window, onHeightChanged = {
            updateHeight()
        }, onScroll = {
            updateHeight()
        }, onReorderingRequested = {
            onReorderingRequested()
        }, isShowingSingleCollection = false)
        vc
    }

    private val segmentedController: WSegmentedController by lazy {
        val segmentedController = WSegmentedController(
            navigationController,
            segmentItems,
            isFullScreen = false,
            applySideGutters = false,
            navHeight = 56.dp,
            onOffsetChange = { _, _ ->
                updateHeight()
            },
            onItemsReordered = null,
            onReorderingStarted = {
                onReorderingRequested()
            },
            onForceEndReorderingRequested = {
                onForceEndReorderingRequested()
            }
        ).apply {
            setDragAllowed(true)
        }
        segmentedController
    }

    override fun setupViews() {
        super.setupViews()

        addView(segmentedController, LayoutParams(MATCH_PARENT, 0))
        setConstraints {
            toBottom(segmentedController)
            toTopPx(
                segmentedController,
                (if (ThemeManager.uiMode.hasRoundedCorners) 0 else ViewConstants.GAP.dp)
            )
        }

        updateHeight()
        updateTheme()
    }

    override fun updateTheme() {
        segmentedController.updateTheme()
        segmentedController.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp,
            true
        )
    }

    fun updateSegmentItemsTheme() {
        segmentedController.updateTheme()
        segmentedController.items.forEach {
            it.viewController.updateTheme()
        }
    }

    fun configure() {
        segmentedController.updateProtectedView()
        updateTheme()
        updateCollectiblesClick()
    }

    fun reloadTabs(resetSelection: Boolean) {
        val oldSegmentItems = segmentedController.items
        val newSegmentItems = segmentItems
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
    }

    val segmentItems: MutableList<WSegmentedControllerItem>
        get() {
            val hiddenNFTsExist =
                NftStore.nftData?.cachedNfts?.firstOrNull { it.isHidden == true } != null ||
                    NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
            val showCollectionsMenu = !NftStore.getCollections().isEmpty() || hiddenNFTsExist
            val homeNftCollections =
                WGlobalStorage.getHomeNftCollections(AccountStore.activeAccountId ?: "")
            val items = mutableListOf<WSegmentedControllerItem>()
            if (!homeNftCollections.contains(AssetsTabVC.TAB_COINS))
                items.add(
                    WSegmentedControllerItem(
                        tokensVC,
                        identifier = AssetsTabVC.identifierForVC(tokensVC)
                    )
                )
            if (!homeNftCollections.contains(AssetsTabVC.TAB_COLLECTIBLES))
                items.add(
                    WSegmentedControllerItem(
                        collectiblesVC,
                        identifier = AssetsTabVC.TAB_COLLECTIBLES,
                        onMenuPressed = if (showCollectionsMenu) {
                            { v ->
                                CollectionsMenuHelpers.presentCollectionsMenuOn(
                                    v,
                                    navigationController,
                                    onReorderTapped = {
                                        onReorderingRequested()
                                    }
                                )
                            }
                        } else {
                            null
                        }
                    )
                )

            if (homeNftCollections.isNotEmpty()) {
                val collections = NftStore.getCollections()
                items.addAll(homeNftCollections.mapNotNull { homeNftCollection ->
                    when (homeNftCollection) {
                        AssetsTabVC.TAB_COINS -> {
                            WSegmentedControllerItem(
                                tokensVC,
                                AssetsTabVC.identifierForVC(tokensVC)
                            )
                        }

                        AssetsTabVC.TAB_COLLECTIBLES -> {
                            WSegmentedControllerItem(
                                collectiblesVC,
                                identifier = AssetsTabVC.TAB_COLLECTIBLES,
                                onMenuPressed = if (showCollectionsMenu) { v ->
                                    CollectionsMenuHelpers.presentCollectionsMenuOn(
                                        v,
                                        navigationController,
                                        onReorderTapped = {
                                            onReorderingRequested()
                                        }
                                    )
                                } else null)
                        }

                        else -> {
                            val collectionMode =
                                if (homeNftCollection == NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION) {
                                    AssetsVC.CollectionMode.TelegramGifts
                                } else {
                                    collections.find { it.address == homeNftCollection }
                                        ?.let { AssetsVC.CollectionMode.SingleCollection(collection = it) }
                                }
                            if (collectionMode != null) {
                                val vc = AssetsVC(
                                    context,
                                    AssetsVC.Mode.THUMB,
                                    injectedWindow = window,
                                    collectionMode = collectionMode,
                                    onHeightChanged = {
                                        updateHeight()
                                    }, onScroll = {
                                        updateHeight()
                                    }, onReorderingRequested = {
                                        onReorderingRequested()
                                    }, isShowingSingleCollection = false
                                )
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
                                                onReorderingRequested()
                                            },
                                            onRemoveTapped = {
                                                window.topViewController?.showAlert(
                                                    LocaleController.getString("Remove Tab"),
                                                    LocaleController.getStringWithKeyValues(
                                                        "Are you sure you want to unpin %tab%?",
                                                        listOf(
                                                            Pair("%tab%", collectionMode.title)
                                                        )
                                                    ),
                                                    LocaleController.getString("Yes"),
                                                    buttonPressed = {
                                                        remove(collectionMode)
                                                        val homeNftCollections =
                                                            WGlobalStorage.getHomeNftCollections(
                                                                AccountStore.activeAccountId!!
                                                            )
                                                        homeNftCollections.remove(collectionMode.collectionAddress)
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
            val hiddenNFTsExist =
                NftStore.nftData?.cachedNfts?.firstOrNull { it.isHidden == true } != null ||
                    NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
            val showCollectionsMenu = !NftStore.getCollections().isEmpty() || hiddenNFTsExist
            segmentedController.updateOnMenuPressed(
                identifier = AssetsTabVC.TAB_COLLECTIBLES,
                onMenuPressed = if (showCollectionsMenu) {
                    { v ->
                        CollectionsMenuHelpers.presentCollectionsMenuOn(
                            v,
                            navigationController,
                            onReorderTapped = {
                                onReorderingRequested()
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

    private fun updateHeight() {
        layoutParams.apply {
            val items = segmentedController.items
            val offset = segmentedController.currentOffset
            val currentIndex = offset.toInt()

            if (currentIndex > items.size - 1) {
                height = 0
                return@apply
            }

            val firstHeight = getViewHeight(items[currentIndex].viewController)
            val secondHeight =
                if (offset > currentIndex) getViewHeight(items[currentIndex + 1].viewController) else 0

            height = if (firstHeight > 0) {
                val interpolatedHeight =
                    firstHeight + (offset - currentIndex) * (secondHeight - firstHeight)
                val cornerGap =
                    if (ThemeManager.uiMode.hasRoundedCorners) 0 else ViewConstants.GAP.dp
                (56.dp + interpolatedHeight).roundToInt() + cornerGap
            } else
                0
        }

        heightChanged()
        requestLayout()
    }

    fun scrollToFirst() {
        segmentedController.scrollToFirst()
    }

    fun onDestroy() {
        segmentedController.onDestroy()
    }

    val isDraggingCollectible: Boolean
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
                ) +
                    56.dp +
                    if (ThemeManager.uiMode.hasRoundedCorners) 0 else ViewConstants.GAP.dp
            animateHeight(nextHeight)
        }
        val removedItem = segmentedController.removeItem(itemToRemoveIndex, onCompletion = {
            if (isInDragMode) {
                (segmentedController.currentItem as? AssetsVC)?.startSorting()
            }
        })
        (removedItem?.viewController as? AssetsVC)?.reloadList()
    }

    private fun saveOrderedItems() {
        val items = segmentedController.items
        val orderedCollections = items.mapNotNull {
            AssetsTabVC.identifierForVC(it.viewController)
        }
        WGlobalStorage.setHomeNftCollections(
            AccountStore.activeAccountId!!,
            orderedCollections
        )
    }

    val isInDragMode: Boolean
        get() {
            return segmentedController.isInDragMode
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
