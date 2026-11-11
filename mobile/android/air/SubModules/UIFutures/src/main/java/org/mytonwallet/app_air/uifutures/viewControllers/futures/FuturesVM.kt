package org.mytonwallet.app_air.uifutures.viewControllers.futures

import java.lang.ref.WeakReference
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.forActivityCard
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.FuturesOnboarding
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.FuturesStoryMediaCache
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFill
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsMarketSection
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOnboarding
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsSnapshot
import org.mytonwallet.app_air.walletcore.moshi.PERPS_LAYOUT_ROWS
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

class FuturesVM(delegate: Delegate) : WalletCore.EventObserver {
    interface Delegate {
        fun futuresUpdated()
    }

    private val delegate = WeakReference(delegate)
    private var observingWalletCore = false

    var snapshot: MApiPerpsSnapshot? = null
        private set

    var positions: List<MApiPerpsNativePosition> = emptyList()
        private set

    var activities: List<MApiPerpsFill> = emptyList()
        private set

    var isLoading = false
        private set

    /** Why positions could not be loaded. */
    var positionsStatus: String? = null
        private set

    var isPositionsStatusRetryable = false
        private set

    /** Not refreshed since this account was shown. */
    var isStale = false
        private set

    var isLoadingActivities = false
        private set

    private var shownAccountId: String? = null
    private var hasFreshSnapshot = false

    /** More activities than the card shows; it ends with Show All. */
    var hasMoreActivities = false
        private set

    /** Default-book markets, the most traded first. */
    var markets: List<MApiPerpsListedAsset> = emptyList()
        private set

    var showsOnboarding = false
        private set

    private var prefetchedOnboarding: MApiPerpsOnboarding? = null

    /** Backend Futures sections, or all [markets] in one group when the backend has none. */
    var marketGroups: List<MApiPerpsMarketSection> = emptyList()
        private set

    fun start() {
        if (observingWalletCore) return
        observingWalletCore = true
        WalletCore.registerObserver(this)
        rebuild()
        refresh()
    }

    fun stop() {
        if (!observingWalletCore) return
        observingWalletCore = false
        WalletCore.unregisterObserver(this)
        isShown = false
    }

    /** While shown, markets follow the SDK's catalogue refreshes. */
    var isShown = false
        set(value) {
            field = value
            if (value) PerpsStore.watch(this) else PerpsStore.unwatch(this)
        }

    fun refresh() {
        if (!observingWalletCore) return
        PerpsStore.refresh()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.PerpsUpdated, is WalletEvent.AccountChanged -> rebuild()
            WalletEvent.PerpsAssetsUpdated -> if (isShown) PerpsStore.loadSnapshot(force = true)
            WalletEvent.SideGuttersChanged -> delegate.get()?.futuresUpdated()
            else -> {}
        }
    }

    private fun rebuild() {
        val accountId = AccountStore.activeAccountId
        isLoading = PerpsStore.isLoadingPositions(accountId)
        val (fills, hasMoreFills) =
            PerpsStore.fillsFor(accountId).orEmpty().forActivityCard(VISIBLE_ACTIVITIES)
        hasMoreActivities = hasMoreFills || PerpsStore.hasMoreFills(accountId)
        snapshot = PerpsStore.snapshotFor(accountId)
        val account = AccountStore.activeAccount
        val unsupportedKey = when {
            account == null || PerpsStore.perpsAddress(account) != null -> null
            account.isMainnet -> "PerpsRequiresMultichainWallet"
            else -> "PerpsUnsupportedAccount"
        }
        val errorKey = PerpsStore.snapshotError(accountId)?.takeIf { snapshot == null }
        positionsStatus = (unsupportedKey ?: errorKey)?.let(LocaleController::getString)
        isPositionsStatusRetryable = unsupportedKey == null && errorKey != null
        if (accountId != shownAccountId) {
            shownAccountId = accountId
            hasFreshSnapshot = false
        }
        val isSnapshotStale = PerpsStore.isSnapshotStale(accountId)
        if (snapshot != null && !isSnapshotStale) hasFreshSnapshot = true
        isStale = isSnapshotStale && !hasFreshSnapshot
        showsOnboarding = unsupportedKey == null && accountId != null &&
            PerpsStore.onboarding?.stories?.isNotEmpty() == true &&
            PerpsStore.isNewToFutures(accountId) &&
            FuturesOnboarding.BANNER_ID !in WGlobalStorage.getDismissedHomeBannerIds(accountId)
        if (showsOnboarding) PerpsStore.onboarding?.let(::prefetchOnboarding)
        positions = snapshot?.openPositions.orEmpty()
        activities = fills
        isLoadingActivities = fills.isEmpty() && PerpsStore.isLoadingFills(accountId)
        markets = PerpsStore.assetsById.values
            .filter { it.dex.isEmpty() && it.isDelisted != true }
            .sortedByDescending { it.volume24h }
        val groups = PerpsStore.marketSections?.mapNotNull { section ->
            val sectionMarkets = section.assets
                .filter { it.isDelisted != true }
                .takeIf { it.isNotEmpty() }
                ?: return@mapNotNull null
            section.copy(assets = sectionMarkets)
        } ?: listOf(
            MApiPerpsMarketSection(
                id = ALL_MARKETS_GROUP_ID,
                title = LocaleController.getString("Futures Market"),
                layout = PERPS_LAYOUT_ROWS,
                mobileLimit = VISIBLE_MARKETS,
                assets = markets
            )
        ).filter { it.assets.isNotEmpty() }
        marketGroups = groups
        delegate.get()?.futuresUpdated()
    }

    fun dismissOnboarding() {
        val accountId = AccountStore.activeAccountId ?: return
        WGlobalStorage.dismissHomeBanner(accountId, FuturesOnboarding.BANNER_ID)
        rebuild()
    }

    private fun prefetchOnboarding(onboarding: MApiPerpsOnboarding) {
        if (prefetchedOnboarding == onboarding) return
        prefetchedOnboarding = onboarding
        FuturesStoryMediaCache.prefetch(
            ApplicationContextHolder.applicationContext,
            onboarding.stories
        ) { isComplete ->
            if (!isComplete && prefetchedOnboarding === onboarding) prefetchedOnboarding = null
        }
    }

    companion object {
        const val ALL_MARKETS_GROUP_ID = "app:allMarkets"

        private const val VISIBLE_ACTIVITIES = 5
        private const val VISIBLE_MARKETS = 10
    }
}
