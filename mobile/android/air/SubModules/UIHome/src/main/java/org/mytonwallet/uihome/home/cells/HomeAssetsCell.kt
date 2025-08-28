package org.mytonwallet.uihome.home.cells

import WNavigationController
import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.util.concurrent.Executors
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class HomeAssetsCell(
    context: Context,
    private val window: WWindow,
    private val navigationController: WNavigationController,
    private val heightChanged: () -> Unit
) : WCell(context), WThemedView {

    private val tokensVC: TokensVC by lazy {
        val vc = TokensVC(
            context, TokensVC.Mode.HOME,
            onHeightChanged = {
                updateHeight()
            }
        ) {
            updateHeight()
        }
        vc
    }

    private val collectiblesVC: AssetsVC by lazy {
        val vc = AssetsVC(context, AssetsVC.Mode.THUMB, injectedWindow = window, onHeightChanged = {
            updateHeight()
        }) {
            updateHeight()
        }
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
            onItemsReordered = {
                val items = segmentedController.items
                val orderedCollections = items.mapNotNull {
                    when (it.viewController) {
                        is TokensVC -> {
                            return@mapNotNull AssetsTabVC.TAB_COINS
                        }

                        is AssetsVC -> {
                            val collectionMode = (it.viewController as AssetsVC).collectionMode
                            return@mapNotNull when (collectionMode) {
                                is AssetsVC.CollectionMode.SingleCollection -> {
                                    collectionMode.collection.address
                                }

                                AssetsVC.CollectionMode.TelegramGifts -> {
                                    NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
                                }

                                null -> AssetsTabVC.TAB_COLLECTIBLES
                            }
                        }

                        else ->
                            null
                    }
                }
                WGlobalStorage.setHomeNftCollections(
                    AccountStore.activeAccountId!!,
                    orderedCollections
                )
            }
        ).apply {
            setDragEnabled(true)
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

    val segmentItems: Array<WSegmentedControllerItem>
        get() {
            val hiddenNFTsExist =
                NftStore.nftData?.cachedNfts?.firstOrNull { it.isHidden == true } != null ||
                    NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
            val showCollectionsMenu = !NftStore.getCollections().isEmpty() || hiddenNFTsExist
            val homeNftCollections =
                WGlobalStorage.getHomeNftCollections(AccountStore.activeAccountId ?: "")
            val items = mutableListOf<WSegmentedControllerItem>()
            if (!homeNftCollections.contains(AssetsTabVC.TAB_COINS))
                items.add(WSegmentedControllerItem(tokensVC))
            if (!homeNftCollections.contains(AssetsTabVC.TAB_COLLECTIBLES))
                items.add(
                    WSegmentedControllerItem(
                        collectiblesVC,
                        identifier = AssetsTabVC.ASSETS_IDENTIFIER,
                        onClick = if (showCollectionsMenu) {
                            { v ->
                                CollectionsMenuHelpers.presentCollectionsMenuOn(
                                    v,
                                    navigationController
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
                            WSegmentedControllerItem(tokensVC)
                        }

                        AssetsTabVC.TAB_COLLECTIBLES -> {
                            WSegmentedControllerItem(
                                collectiblesVC,
                                identifier = AssetsTabVC.ASSETS_IDENTIFIER,
                                onClick = if (showCollectionsMenu) { v ->
                                    CollectionsMenuHelpers.presentCollectionsMenuOn(
                                        v,
                                        navigationController
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
                                    }) {
                                    updateHeight()
                                }
                                WSegmentedControllerItem(
                                    viewController = vc,
                                    onClick = { v ->
                                        CollectionsMenuHelpers.presentPinnedCollectionMenuOn(
                                            v,
                                            collectionMode
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
            return items.toTypedArray()
        }

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    fun updateCollectiblesClick() {
        backgroundExecutor.execute {
            val hiddenNFTsExist =
                NftStore.nftData?.cachedNfts?.firstOrNull { it.isHidden == true } != null ||
                    NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
            val showCollectionsMenu = !NftStore.getCollections().isEmpty() || hiddenNFTsExist
            segmentedController.updateOnClick(
                identifier = AssetsTabVC.ASSETS_IDENTIFIER,
                onClick = if (showCollectionsMenu) {
                    { v ->
                        CollectionsMenuHelpers.presentCollectionsMenuOn(
                            v,
                            navigationController
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
}
