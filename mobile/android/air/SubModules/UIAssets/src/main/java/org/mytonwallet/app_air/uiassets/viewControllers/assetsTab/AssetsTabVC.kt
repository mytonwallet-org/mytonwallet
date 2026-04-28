package org.mytonwallet.app_air.uiassets.viewControllers.assetsTab

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import androidx.core.view.isGone
import me.vkryl.android.animatorx.BoolAnimator
import org.mytonwallet.app_air.uiassets.models.ExpiringDomainsData
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.title
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uiassets.viewControllers.views.WDomainExpirationBannerView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WActionBar.TitleAnimationMode
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
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
import kotlin.math.abs
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class AssetsTabVC(
    context: Context,
    val showingAccountId: String,
    private val defaultSelectedIdentifier: String?,
    private var initialSelectionSnapshot: AssetsVC.SelectionSnapshot? = null
) :
    WViewController(context),
    WalletCore.EventObserver {
    override val TAG = "AssetsTab"

    companion object {
        const val TAB_COINS = "app:coins"
        const val TAB_COLLECTIBLES = "app:collectibles"
        private const val BANNER_ALPHA_VISIBLE_RANGE = 0.5f
        private const val BANNER_COLLAPSE_TRANSLATION_DP = 18
        private const val BANNER_COLLAPSE_MIN_SCALE = 0.8f
        private const val BANNER_EXPANDED_TOP_OFFSET_DP = 8
        private const val EXPANDED_BANNER_TOP_MARGIN_DP = 8
        private const val EXPANDED_BANNER_BOTTOM_MARGIN_DP = 3

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
    private var selectionAssetsVC: AssetsVC? = null
    private var reorderingAssetsVC: AssetsVC? = null
    private var collectiblesExpiringDomainsData: ExpiringDomainsData? = null
    private var isShowingCollectiblesExpiringDomainsBanner = false
    private val expiringDomainsBannerView: WDomainExpirationBannerView by lazy {
        WDomainExpirationBannerView(context).apply {
            isGone = true
        }
    }
    private val expiringDomainsBannerContainerView: WView by lazy {
        WView(context).apply {
            clipChildren = false
            clipToPadding = false
            addView(
                expiringDomainsBannerView,
                ViewGroup.LayoutParams(0, WDomainExpirationBannerView.HEIGHT_DP.dp)
            )
            setConstraints {
                toTop(expiringDomainsBannerView, EXPANDED_BANNER_TOP_MARGIN_DP.toFloat())
                toCenterX(
                    expiringDomainsBannerView,
                    ViewConstants.HORIZONTAL_PADDINGS.toFloat()
                )
            }
        }
    }
    private val expiringDomainsBannerExpandedHeight: Int by lazy {
        (WDomainExpirationBannerView.HEIGHT_DP +
            EXPANDED_BANNER_TOP_MARGIN_DP +
            EXPANDED_BANNER_BOTTOM_MARGIN_DP).dp
    }

    private val collectiblesExpiringDomainsBannerAnimator = BoolAnimator(
        duration = AnimationConstants.VERY_QUICK_ANIMATION,
        interpolator = CubicBezierInterpolator.EASE_BOTH,
        onAnimationsFinished = { finalState, _ ->
            if (finalState == BoolAnimator.State.FALSE) {
                isShowingCollectiblesExpiringDomainsBanner = false
                if (collectiblesExpiringDomainsData == null) {
                    expiringDomainsBannerView.onTap = null
                    expiringDomainsBannerView.onClose = null
                }
            }
            applyCollectiblesExpiringDomainsBanner()
        }
    ) { _, _, _, _ ->
        applyCollectiblesExpiringDomainsBanner()
    }

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
        val vc = AssetsVC(
            context,
            showingAccountId,
            AssetsVC.ViewMode.COMPLETE,
            injectedWindow = window,
            isShowingSingleCollection = false,
            onReorderingRequested = {
                openReordering(collectiblesVC)
            },
            onScroll = { recyclerView ->
                segmentedController.updateBlurViews(recyclerView)
                updateBlurViews(recyclerView)
            }
        )
        vc.completeModeExpiringDomainsBannerHeight = expiringDomainsBannerExpandedHeight
        bindSelection(vc)
    }

    private fun bindSelection(vc: AssetsVC) = vc.apply {
        onSelectionRequested = { nftAddressToSelect ->
            openSelectionMode(vc, nftAddressToSelect)
        }
        if (vc.identifier == TAB_COLLECTIBLES) {
            onExpiringDomainsDataChanged = { expiringDomainsData ->
                collectiblesExpiringDomainsData = expiringDomainsData
                if (expiringDomainsData != null) {
                    configureCollectiblesExpiringDomainsBanner(expiringDomainsData)
                }
                val shouldShow = collectiblesExpiringDomainsData != null
                if (shouldShow != isShowingCollectiblesExpiringDomainsBanner) {
                    if (shouldShow) {
                        isShowingCollectiblesExpiringDomainsBanner = true
                    }
                    collectiblesExpiringDomainsBannerAnimator.changeValue(
                        shouldShow,
                        animated = true
                    )
                }
                applyCollectiblesExpiringDomainsBanner()
            }
        }
        onSelectionChanged = { selectedCount, animationMode, isInSelectionMode ->
            if (selectionAssetsVC === vc && isInSelectionMode) {
                configureSelectionActionBar(vc)
                updateSelectionActionBarTitle(selectedCount, animationMode)
                segmentedController?.showActionBar()
            }
        }
    }

    private fun updateSelectionActionBarTitle(
        selectedCount: Int,
        animationMode: TitleAnimationMode? = null
    ) {
        val title = if (selectedCount == 0) {
            LocaleController.getString("\$nft_select")
        } else {
            selectedCount.toString()
        }
        if (animationMode != null) {
            segmentedController.actionBarView.setTitle(title, true, animationMode)
        } else {
            segmentedController.actionBarView.setTitle(title, false)
        }
    }

    private fun configureSelectionActionBar(assetsVC: AssetsVC) {
        CollectionsMenuHelpers.configureSelectionActionBar(
            actionBar = segmentedController.actionBarView,
            shouldShowTransferActions = assetsVC.shouldShowSelectionTransferActions(),
            onCloseTapped = { closeSelectionMode() },
            onHideTapped = {
                assetsVC.hideSelectedAssets();
                closeSelectionMode()
            },
            onSelectAllTapped = { assetsVC.selectAllVisibleAssets() },
            onSendTapped = { if (assetsVC.sendSelectedNfts()) closeSelectionMode() },
            onBurnTapped = { if (assetsVC.burnSelectedNfts()) closeSelectionMode() }
        )
    }

    private fun openSelectionMode(
        assetsVC: AssetsVC,
        nftAddressToSelect: String? = null
    ) {
        if (reorderingAssetsVC != null) {
            return
        }
        if (selectionAssetsVC !== assetsVC) {
            selectionAssetsVC?.closeSelectionMode()
        }
        val index = segmentedController.items.indexOfFirst { it.viewController === assetsVC }
        if (index >= 0 && segmentedController.currentIndex != index) {
            segmentedController.setActiveIndex(index)
        }
        selectionAssetsVC = assetsVC
        assetsVC.onAutoClose = { closeSelectionMode() }
        configureSelectionActionBar(assetsVC)
        updateSelectionActionBarTitle(assetsVC.selectedCount())
        assetsVC.openSelectionMode(nftAddressToSelect)
        segmentedController.showActionBar()
    }

    private fun closeSelectionMode() {
        val assetsVC = selectionAssetsVC ?: run {
            segmentedController.hideActionBar()
            return
        }
        selectionAssetsVC = null
        assetsVC.onAutoClose = null
        assetsVC.closeSelectionMode()
        segmentedController.hideActionBar()
    }

    private fun configureReorderActionBar() {
        CollectionsMenuHelpers.configureReorderActionBar(
            actionBar = segmentedController.actionBarView,
            onSaveTapped = { endReordering(save = true) },
            onCancelTapped = { endReordering(save = false) }
        )
    }

    private fun openReordering(assetsVC: AssetsVC) {
        if (reorderingAssetsVC != null) {
            return
        }
        closeSelectionMode()
        val index = segmentedController.items.indexOfFirst { it.viewController === assetsVC }
        if (index >= 0 && segmentedController.currentIndex != index) {
            segmentedController.setActiveIndex(index)
        }
        reorderingAssetsVC = assetsVC
        configureReorderActionBar()
        assetsVC.startSorting()
        segmentedController.showActionBar()
    }

    private fun endReordering(save: Boolean) {
        val assetsVC = reorderingAssetsVC ?: run {
            segmentedController.hideActionBar()
            return
        }
        reorderingAssetsVC = null
        if (save) {
            assetsVC.saveList()
        } else {
            assetsVC.reloadList()
        }
        assetsVC.endSorting()
        segmentedController.hideActionBar()
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
                                    onReorderTapped = {
                                        openReordering(collectiblesVC)
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
                val collections = NftStore.getCollections()
                items.addAll(homeNftCollections.mapNotNull { homeNftCollection ->
                    when (homeNftCollection.address) {
                        TAB_COINS -> {
                            WSegmentedControllerItem(
                                tokensVC,
                                identifierForVC(tokensVC),
                            )
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
                                        onReorderTapped = {
                                            openReordering(collectiblesVC)
                                        },
                                        onSelectTapped = {
                                            openSelectionMode(collectiblesVC)
                                        }
                                    )
                                } else null
                            )
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
                                lateinit var vc: AssetsVC
                                vc = AssetsVC(
                                    context,
                                    showingAccountId,
                                    AssetsVC.ViewMode.COMPLETE,
                                    injectedWindow = window,
                                    collectionMode = collectionMode,
                                    isShowingSingleCollection = false,
                                    onReorderingRequested = {
                                        openReordering(vc)
                                    },
                                    onScroll = { recyclerView ->
                                        segmentedController.updateBlurViews(recyclerView)
                                        updateBlurViews(recyclerView)
                                    }
                                )
                                bindSelection(vc)
                                WSegmentedControllerItem(
                                    viewController = vc,
                                    identifier = identifierForVC(vc),
                                    onMenuPressed = { v ->
                                        CollectionsMenuHelpers.presentPinnedCollectionMenuOn(
                                            v,
                                            collectionMode,
                                            onReorderTapped = {
                                                openReordering(vc)
                                            },
                                            onSelectTapped = {
                                                openSelectionMode(vc)
                                            },
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

                                                                is AssetsVC.CollectionMode.ReadOnly ->
                                                                    return@showAlert
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
                applyCollectiblesExpiringDomainsBanner()
            },
            onSelectedIndexChanged = {
                applyCollectiblesExpiringDomainsBanner()
            },
        )
        sc
    }

    private fun collectiblesTabProgress(currentOffset: Float = segmentedController.currentOffset): Float {
        val collectiblesIndex =
            segmentedController.items.indexOfFirst { it.identifier == TAB_COLLECTIBLES }
        if (collectiblesIndex < 0) {
            return 0f
        }
        return (1f - abs(currentOffset - collectiblesIndex)).coerceIn(0f, 1f)
    }

    private fun bannerAlphaProgress(progress: Float): Float {
        val threshold = 1f - BANNER_ALPHA_VISIBLE_RANGE
        return ((progress - threshold) / BANNER_ALPHA_VISIBLE_RANGE).coerceIn(0f, 1f)
    }

    private fun configureCollectiblesExpiringDomainsBanner(expiringDomainsData: ExpiringDomainsData) {
        expiringDomainsBannerView.configure(
            iconNfts = expiringDomainsData.domainNfts,
            count = expiringDomainsData.count,
            minDays = expiringDomainsData.minDays
        )
        expiringDomainsBannerView.onTap = { collectiblesVC.openRenewForExpiringDomains() }
        expiringDomainsBannerView.onClose = { collectiblesVC.dismissExpiringDomainsBanner() }
    }

    private fun hideCollectiblesExpiringDomainsBanner() {
        expiringDomainsBannerView.alpha = 0f
        expiringDomainsBannerView.isGone = true
        segmentedController.setUnderTabsHeight(0)
    }

    private fun updateCollectiblesExpiringDomainsBannerViewProperties() {
        val tabProgress = collectiblesTabProgress()
        val showProgress = collectiblesExpiringDomainsBannerAnimator.floatValue
        val alphaProgress = bannerAlphaProgress(tabProgress)
        val showAlphaProgress = bannerAlphaProgress(showProgress)
        val combinedProgress = showProgress * tabProgress
        val displayProgress = showAlphaProgress * alphaProgress
        if (combinedProgress <= 0f) {
            hideCollectiblesExpiringDomainsBanner()
            return
        }

        expiringDomainsBannerView.alpha = displayProgress
        val collapseProgress = 1f - displayProgress
        expiringDomainsBannerView.translationY =
            -BANNER_EXPANDED_TOP_OFFSET_DP.dp -
                BANNER_COLLAPSE_TRANSLATION_DP.dp * collapseProgress
        val scale = BANNER_COLLAPSE_MIN_SCALE + (1f - BANNER_COLLAPSE_MIN_SCALE) * displayProgress
        expiringDomainsBannerView.scaleX = scale
        expiringDomainsBannerView.scaleY = scale
        expiringDomainsBannerView.isGone = displayProgress <= 0f
        segmentedController.setUnderTabsHeight(
            (expiringDomainsBannerExpandedHeight * combinedProgress).roundToInt()
        )
    }

    private fun applyCollectiblesExpiringDomainsBanner() {
        updateCollectiblesExpiringDomainsBannerViewProperties()
    }

    override fun setupViews() {
        super.setupViews()

        segmentedController.addCloseButton()
        segmentedController.setUnderTabsView(expiringDomainsBannerContainerView)
        view.addView(segmentedController)

        view.setConstraints {
            allEdges(segmentedController)
        }

        WalletCore.registerObserver(this)
        updateCollectiblesClick()
        updateTheme()
        applyInitialSelectionSnapshot()
        applyCollectiblesExpiringDomainsBanner()
    }

    private fun applyInitialSelectionSnapshot() {
        val selectionSnapshot = initialSelectionSnapshot ?: return
        val targetAssetsVC = segmentedController.items.firstOrNull {
            it.identifier == defaultSelectedIdentifier
        }?.viewController as? AssetsVC ?: return
        val index = segmentedController.items.indexOfFirst { it.viewController === targetAssetsVC }
        if (index >= 0 && segmentedController.currentIndex != index) {
            segmentedController.setActiveIndex(index)
        }
        targetAssetsVC.onAutoClose = { closeSelectionMode() }
        selectionAssetsVC = targetAssetsVC
        configureSelectionActionBar(targetAssetsVC)
        targetAssetsVC.restoreSelectionSnapshot(selectionSnapshot)
        initialSelectionSnapshot = null
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
                            onReorderTapped = {
                                openReordering(collectiblesVC)
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

    override fun updateTheme() {
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        if (!expiringDomainsBannerView.isGone) {
            expiringDomainsBannerView.updateTheme()
        }
    }

    override fun scrollToTop() {
        super.scrollToTop()
        segmentedController.scrollToTop()
    }

    override fun onBackPressed(): Boolean {
        if (selectionAssetsVC != null) {
            closeSelectionMode()
            return false
        }
        return super.onBackPressed()
    }

    override fun onDestroy() {
        super.onDestroy()
        backgroundExecutor.shutdown()
        collectiblesExpiringDomainsData = null
        segmentedController.onDestroy()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.HomeNftCollectionsUpdated -> {
                segmentedController.updateItems(segmentItems, keepSelection = true)
                applyCollectiblesExpiringDomainsBanner()
            }

            else -> {}
        }
    }

}
