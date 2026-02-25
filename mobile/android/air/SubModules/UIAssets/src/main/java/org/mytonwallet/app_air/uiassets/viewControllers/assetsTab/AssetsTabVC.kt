package org.mytonwallet.app_air.uiassets.viewControllers.assetsTab

import android.annotation.SuppressLint
import android.content.Context
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.title
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.util.concurrent.Executors

@SuppressLint("ViewConstructor")
class AssetsTabVC(
    context: Context,
    val showingAccountId: String,
    defaultSelectedIdentifier: String?
) :
    WViewController(context),
    WalletCore.EventObserver {
    override val TAG = "AssetsTab"

    companion object {
        const val TAB_COINS = "app:coins"
        const val TAB_COLLECTIBLES = "app:collectibles"
        fun identifierForVC(viewController: WViewController): String? {
            return when (viewController) {
                is TokensVC -> {
                    TAB_COINS
                }

                is AssetsVC -> {
                    viewController.identifier
                }

                else ->
                    TAB_COLLECTIBLES
            }
        }
    }

    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = true
    override val isSwipeBackAllowed = false

    private val tokensVC: TokensVC by lazy {
        TokensVC(context, showingAccountId, TokensVC.Mode.ALL, onScroll = { recyclerView ->
            segmentedController.updateBlurViews(recyclerView)
            updateBlurViews(recyclerView)
        })
    }

    private val collectiblesVC: AssetsVC by lazy {
        AssetsVC(
            context,
            showingAccountId,
            AssetsVC.Mode.COMPLETE,
            injectedWindow = window,
            isShowingSingleCollection = false,
            onScroll = { recyclerView ->
                segmentedController.updateBlurViews(recyclerView)
                updateBlurViews(recyclerView)
            }
        )
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
            if (!homeNftCollections.any { it.chain == MBlockchain.ton.name && it.address == TAB_COINS })
                items.add(
                    WSegmentedControllerItem(
                        tokensVC,
                        identifier = identifierForVC(tokensVC)
                    )
                )
            if (!homeNftCollections.any { it.chain == MBlockchain.ton.name && it.address == TAB_COLLECTIBLES })
                items.add(
                    WSegmentedControllerItem(
                        collectiblesVC,
                        identifier = TAB_COLLECTIBLES,
                        onMenuPressed = if (showCollectionsMenu) {
                            { v ->
                                CollectionsMenuHelpers.presentCollectionsMenuOn(
                                    showingAccountId,
                                    v,
                                    navigationController!!,
                                    null
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
                    when (homeNftCollection.address) {
                        TAB_COINS -> {
                            WSegmentedControllerItem(tokensVC, identifierForVC(tokensVC))
                        }

                        TAB_COLLECTIBLES -> {
                            WSegmentedControllerItem(
                                collectiblesVC,
                                identifier = TAB_COLLECTIBLES,
                                onMenuPressed = if (showCollectionsMenu) { v ->
                                    CollectionsMenuHelpers.presentCollectionsMenuOn(
                                        showingAccountId,
                                        v,
                                        navigationController!!,
                                        null
                                    )
                                } else null)
                        }

                        else -> {
                            val collectionMode =
                                if (homeNftCollection.address == NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION) {
                                    AssetsVC.CollectionMode.TelegramGifts
                                } else {
                                    collections.find {
                                        it.address == homeNftCollection.address &&
                                            it.chain == homeNftCollection.chain
                                    }
                                        ?.let { AssetsVC.CollectionMode.SingleCollection(collection = it) }
                                }
                            if (collectionMode != null) {
                                val vc = AssetsVC(
                                    context,
                                    showingAccountId,
                                    AssetsVC.Mode.COMPLETE,
                                    injectedWindow = window,
                                    collectionMode = collectionMode,
                                    isShowingSingleCollection = false,
                                    onScroll = { recyclerView ->
                                        segmentedController.updateBlurViews(recyclerView)
                                        updateBlurViews(recyclerView)
                                    }
                                )
                                WSegmentedControllerItem(
                                    viewController = vc,
                                    identifier = identifierForVC(vc),
                                    onMenuPressed = { v ->
                                        CollectionsMenuHelpers.presentPinnedCollectionMenuOn(
                                            v,
                                            collectionMode,
                                            onRemoveTapped = {
                                                showAlert(
                                                    LocaleController.getString("Remove Tab"),
                                                    LocaleController.getStringWithKeyValues(
                                                        "Are you sure you want to unpin %tab%?",
                                                        listOf(
                                                            Pair("%tab%", collectionMode.title)
                                                        )
                                                    ),
                                                    LocaleController.getString("Yes"),
                                                    buttonPressed = {
                                                        val homeNftCollections =
                                                            WGlobalStorage.getHomeNftCollections(
                                                                AccountStore.activeAccountId!!
                                                            )
                                                        val collectionChain =
                                                            when (collectionMode) {
                                                                is AssetsVC.CollectionMode.SingleCollection ->
                                                                    collectionMode.collection.chain

                                                                is AssetsVC.CollectionMode.TelegramGifts ->
                                                                    MBlockchain.ton.name
                                                            }
                                                        homeNftCollections.removeAll {
                                                            it.address == collectionMode.collectionAddress &&
                                                                it.chain == collectionChain
                                                        }
                                                        WGlobalStorage.setHomeNftCollections(
                                                            AccountStore.activeAccountId!!,
                                                            homeNftCollections
                                                        )
                                                        WalletCore.notifyEvent(WalletEvent.HomeNftCollectionsUpdated)
                                                    },
                                                    secondaryButton = LocaleController.getString(
                                                        "Cancel"
                                                    ),
                                                    primaryIsDanger = true
                                                )
                                            }, onReorderTapped = null
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

    private val segmentedController: WSegmentedController by lazy {
        val items = segmentItems
        val defaultSelectedIndex = items.indexOfFirst {
            it.identifier == defaultSelectedIdentifier
        }
        val sc = WSegmentedController(
            navigationController!!,
            segmentItems,
            defaultSelectedIndex.coerceAtLeast(0),
            onOffsetChange = { _, _ ->
                bottomReversedCornerView?.resumeBlurring()
            }
        )
        sc
    }

    override fun setupViews() {
        super.setupViews()

        segmentedController.addCloseButton()
        view.addView(segmentedController)

        view.setConstraints {
            allEdges(segmentedController)
        }

        WalletCore.registerObserver(this)
        updateCollectiblesClick()
        updateTheme()
    }

    fun updateCollectiblesClick() {
        backgroundExecutor.execute {
            val hiddenNFTsExist =
                NftStore.nftData?.cachedNfts?.firstOrNull { it.isHidden == true } != null ||
                    NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
            val showCollectionsMenu = !NftStore.getCollections().isEmpty() || hiddenNFTsExist
            segmentedController.updateOnMenuPressed(
                identifier = TAB_COLLECTIBLES,
                onMenuPressed = if (showCollectionsMenu) {
                    { v ->
                        CollectionsMenuHelpers.presentCollectionsMenuOn(
                            showingAccountId,
                            v,
                            navigationController!!,
                            onReorderTapped = null
                        )
                    }
                } else {
                    null
                }
            )
        }
    }

    override fun updateTheme() {
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun scrollToTop() {
        super.scrollToTop()
        segmentedController.scrollToTop()
    }

    override fun onDestroy() {
        super.onDestroy()
        segmentedController.onDestroy()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.HomeNftCollectionsUpdated -> {
                segmentedController.updateItems(segmentItems, keepSelection = true)
            }

            else -> {}
        }
    }

}
