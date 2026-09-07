package org.mytonwallet.app_air.uibrowser.viewControllers.search

import android.content.Context
import android.content.Intent
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.net.toUri
import androidx.core.view.setPadding
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.net.URLEncoder
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.nft.NftVC
import org.mytonwallet.app_air.uiassets.viewControllers.token.TokenVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.cells.TokenCell
import org.mytonwallet.app_air.uibrowser.search.AppSearchEntry
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVM
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.GapCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchAppItemCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchBestMatchCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchChatHintCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchCollectibleCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchDappCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchHistoryCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchItemCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchMatchedCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchRecentChatCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchSectionCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchSelectorHeaderCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchWalletCell
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.moshi.IDapp
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class SearchVC(
    context: Context,
    private val enhancedSearchEnabled: Boolean,
    internal val usesGlobalSearchOverlay: Boolean = false,
    private val onDestroyed: (() -> Unit)? = null
) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "Search"

    override val isSwipeBackAllowed = false

    companion object {
        val RECENT_SEARCH_TITLE_CELL = WCell.Type(1)
        val SEARCH_TITLE_CELL = WCell.Type(2)
        val SEARCH_SEARCHED_CELL = WCell.Type(3)
        val SEARCH_HISTORY_CELL = WCell.Type(4)
        val SEARCH_DAPP_CELL = WCell.Type(5)
        val SEARCH_MATCH_CELL = WCell.Type(6)
        val GAP_CELL = WCell.Type(7)
        val SEARCH_WALLET_CELL = WCell.Type(8)
        val SEARCH_SECTION_CELL = WCell.Type(9)
        val SEARCH_COLLECTIBLE_CELL = WCell.Type(10)
        val SEARCH_TOKEN_CELL = WCell.Type(11)
        val SEARCH_AGENT_CELL = WCell.Type(12)
        val SEARCH_GOOGLE_CELL = WCell.Type(13)
        val SEARCH_BEST_TOKEN_CELL = WCell.Type(14)
        val SEARCH_BEST_WALLET_CELL = WCell.Type(15)
        val SEARCH_SELECTOR_TITLE_CELL = WCell.Type(16)
        val SEARCH_CHAT_HINT_CELL = WCell.Type(17)
        val SEARCH_RECENT_CHAT_CELL = WCell.Type(18)
        val SEARCH_BEST_DAPP_CELL = WCell.Type(19)
        val SEARCH_BEST_NFT_CELL = WCell.Type(20)
        val SEARCH_APP_ITEM_CELL = WCell.Type(21)
        val SEARCH_BEST_APP_ITEM_CELL = WCell.Type(22)
        val SEARCH_BEST_AGENT_CELL = WCell.Type(23)

        const val SECTION_CHATS = 0

        const val SECTION_BEST_MATCH = 1
        const val SECTION_RECENT_QUERIES = 2
        const val SECTION_TOKENS = 3
        const val SECTION_COLLECTIBLES = 4
        const val SECTION_MY_WALLETS = 5
        const val SECTION_ACTIONS = 6
        const val SECTION_SETTINGS = 7
        const val SECTION_DAPPS = 8
        const val SECTION_SITES = 9
        const val SECTION_SUGGESTIONS = 10
        const val SECTION_AGENT = 11
        const val SECTION_GOOGLE = 12

        const val CLEAR_ALL_BUTTON_TAG = "clearAll"
    }

    override var title: String?
        get() = LocaleController.getString("Search")
        set(_) {
        }

    override val shouldDisplayTopBar = true
    override val shouldDisplayBottomBar: Boolean
        get() {
            return window?.isWideLayout == true
        }

    private val searchDataSource: SearchDataSource =
        if (enhancedSearchEnabled) {
            EnhancedSearchDataSource(this)
        } else {
            LegacySearchDataSource(this)
        }

    internal val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference<WRecyclerViewAdapter.WRecyclerViewDataSource>(searchDataSource),
            arrayOf(
                RECENT_SEARCH_TITLE_CELL,
                SEARCH_TITLE_CELL,
                SEARCH_SEARCHED_CELL,
                SEARCH_HISTORY_CELL,
                SEARCH_DAPP_CELL,
                SEARCH_MATCH_CELL,
                SEARCH_WALLET_CELL,
                SEARCH_SECTION_CELL,
                SEARCH_COLLECTIBLE_CELL,
                SEARCH_TOKEN_CELL,
                SEARCH_AGENT_CELL,
                SEARCH_GOOGLE_CELL,
                SEARCH_BEST_TOKEN_CELL,
                SEARCH_BEST_WALLET_CELL,
                SEARCH_BEST_DAPP_CELL,
                SEARCH_BEST_NFT_CELL,
                SEARCH_APP_ITEM_CELL,
                SEARCH_BEST_APP_ITEM_CELL,
                SEARCH_BEST_AGENT_CELL,
                SEARCH_SELECTOR_TITLE_CELL,
                SEARCH_CHAT_HINT_CELL,
                SEARCH_RECENT_CHAT_CELL,
                GAP_CELL
            )
        )

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        rv.layoutManager = LinearLayoutManager(context, RecyclerView.VERTICAL, false)
        rv.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (recyclerView.computeVerticalScrollOffset() == 0) updateBlurViews(recyclerView)
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0) return
                updateBlurViews(recyclerView)
            }
        })
        rv.clipToPadding = false
        rv
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)

        if (usesGlobalSearchOverlay) {
            navigationBar?.addLeadingView(
                WImageButton(context).apply {
                    setPadding(8.dp)
                    setImageDrawable(context.getDrawableCompat(R.drawable.ic_nav_back))
                    updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
                    setOnClickListener {
                        navigationController?.tabBarController?.clearSearchFocus()
                    }
                },
                ConstraintLayout.LayoutParams(40.dp, 40.dp)
            )
        }

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(recyclerView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        recyclerView.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            (navigationController?.getSystemBars()?.top ?: 0) + WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            if (usesGlobalSearchOverlay) {
                // The overlay stack sits outside the tab container, so its own bottomInset would
                // miss the keyboard and the floating search field. Ask the host for the same
                // reserved height the tab stacks get.
                navigationController?.tabBarController?.getBottomNavigationHeight()
                    ?: navigationController?.getSystemBars()?.bottom
                    ?: 0
            } else {
                ((navigationController?.bottomInset ?: 0) - 16.dp).coerceAtLeast(0)
            }
        )
    }

    var keepKeyboardOpenOnDismiss = false
    override val shouldHideKeyboardOnDisappear: Boolean
        get() = !keepKeyboardOpenOnDismiss

    override fun onDestroy() {
        pendingBestMatchRequest = null
        super.onDestroy()
        if (enhancedSearchEnabled) {
            navigationController?.tabBarController?.clearSearchFocus()
        }
        onDestroyed?.invoke()
    }

    internal var searchResult: ExploreVM.SearchResult? = null
    internal var searchQuery = ""

    private data class PendingBestMatchRequest(val query: String, val onResolved: (Boolean) -> Unit)

    private var pendingBestMatchRequest: PendingBestMatchRequest? = null

    fun updateSearchQuery(query: String) {
        if (query != searchQuery) pendingBestMatchRequest = null
        applyStateChange {
            searchQuery = query
        }
    }

    fun updateSearchResult(searchResult: ExploreVM.SearchResult?) {
        applyStateChange {
            this.searchResult = searchResult
        }
        resolvePendingBestMatch()
    }

    private fun applyStateChange(mutate: () -> Unit) {
        val previousSectionItemCounts = sectionItemCounts()
        val previousCellTypes = cellTypes(previousSectionItemCounts)
        mutate()
        searchDataSource.onSearchStateChanged()
        val currentSectionItemCounts = sectionItemCounts()
        // updateVisibleCells() rebinds through the adapter's cached section layout, which only
        // reloadData() rebuilds, so it is safe only while that layout is unchanged.
        val layoutUnchanged = previousSectionItemCounts.contentEquals(currentSectionItemCounts) &&
            previousCellTypes.contentEquals(cellTypes(currentSectionItemCounts))
        if (layoutUnchanged) {
            rvAdapter.updateVisibleCells()
        } else {
            rvAdapter.reloadData()
        }
    }

    private fun sectionItemCounts(): IntArray = searchDataSource.sectionItemCounts(recyclerView)

    /**
     * Cell types tagged with the section they belong to. Two sections can use the same cell type
     * (both selector headers, for example), so an untagged sequence can compare equal while rows
     * actually moved between sections, and the in-place update path would then rebind a holder of
     * the wrong type.
     */
    private fun cellTypes(sectionItemCounts: IntArray): IntArray = buildList {
        sectionItemCounts.forEachIndexed { section, itemCount ->
            repeat(itemCount) { row ->
                add(section)
                add(
                    searchDataSource.recyclerViewCellType(
                        recyclerView,
                        org.mytonwallet.app_air.walletcontext.utils.IndexPath(section, row)
                    ).value
                )
            }
        }
    }.toIntArray()

    fun openBestMatch(onResolved: (Boolean) -> Unit) {
        pendingBestMatchRequest = null
        resolveBestMatch(PendingBestMatchRequest(searchQuery, onResolved))
    }

    private fun resolvePendingBestMatch() {
        pendingBestMatchRequest?.let(::resolveBestMatch)
    }

    private fun resolveBestMatch(request: PendingBestMatchRequest) {
        if (request.query != searchQuery) {
            pendingBestMatchRequest = null
            return
        }
        when (searchDataSource.openBestMatch()) {
            SearchDataSource.BestMatchResult.OPENED -> {
                pendingBestMatchRequest = null
                request.onResolved(true)
            }

            SearchDataSource.BestMatchResult.NOT_FOUND -> {
                pendingBestMatchRequest = null
                request.onResolved(false)
            }

            SearchDataSource.BestMatchResult.PENDING -> {
                pendingBestMatchRequest = request
            }
        }
    }

    internal fun openAppEntry(entry: AppSearchEntry) {
        if (!entry.isAvailable()) return
        WalletContextManager.delegate?.get()
            ?.handleDeeplink(entry.deeplink, DeeplinkOpenSource.INTERNAL_UI)
    }

    internal fun openDapp(app: IDapp) {
        val url = app.url
        val webUrl = url?.takeIf {
            it.startsWith("http://") || it.startsWith("https://")
        }
        if (webUrl == null || app !is MExploreSite || app.isExternal || app.isTelegram) {
            val intent = Intent(Intent.ACTION_VIEW)
            intent.setData(url?.toUri())
            try {
                window!!.startActivity(intent)
            } catch (_: Exception) {
            }
            return
        }
        openInAppBrowser(
            InAppBrowserConfig(
                url = webUrl,
                title = app.name,
                thumbnail = app.iconUrl,
                injectDappConnect = true,
                saveInVisitedHistory = true
            )
        )
    }

    internal fun openOwnWallet(match: ExploreVM.MyWalletMatch) {
        val accountId = match.account.accountId
        if (accountId == org.mytonwallet.app_air.walletcore.stores.AccountStore.activeAccountId) {
            navigationController?.tabBarController?.switchToFirstTab()
            navigationController?.popToRoot(false)
            return
        }
        WalletCore.activateAccount(
            accountId,
            notifySDK = true,
            willPopTemporaryPushedWallets = true
        ) { res, err ->
            if (res == null || err != null) return@activateAccount
            WalletCore.notifyEvent(
                WalletEvent.AccountChangedInApp(persistedAccountsModified = false)
            )
            navigationController?.tabBarController?.switchToFirstTab()
            navigationController?.popToRoot(false)
        }
    }

    internal fun openWalletInfo(match: ExploreVM.WalletInfoMatch) {
        navigationController?.popToRoot(false)
        WalletContextManager.delegate?.get()?.openASingleWallet(
            match.network,
            mapOf(match.chain.name to match.inputAddressOrDomain),
            null
        )
    }

    internal fun openCollectible(match: ExploreVM.CollectibleMatch) {
        val accountId = AccountStore.activeAccountId ?: return
        when (match) {
            is ExploreVM.CollectibleMatch.Nft -> {
                val visibleNfts = NftStore.nftData
                    ?.takeIf { it.accountId == accountId }
                    ?.cachedNfts
                    ?.filterNot { NftStore.shouldHide(accountId, it) }
                    ?.takeIf { nfts -> nfts.any { it.address == match.nft.address } }
                    ?: listOf(match.nft)
                navigationController?.push(
                    NftVC(context, accountId, match.nft, visibleNfts)
                )
            }

            is ExploreVM.CollectibleMatch.Collection -> {
                navigationController?.push(
                    AssetsVC(
                        context,
                        accountId,
                        AssetsVC.ViewMode.COMPLETE,
                        collectionMode = AssetsVC.CollectionMode.SingleCollection(
                            match.collection
                        ),
                        isShowingSingleCollection = true
                    )
                )
            }
        }
    }

    internal fun openToken(tokenBalance: MTokenBalance) {
        val account = AccountStore.activeAccount ?: return
        val token = TokenStore.getToken(tokenBalance.token) ?: return
        searchResult?.takeIf { it.keyword.isEmpty() }?.let { result ->
            updateSearchResult(
                result.copy(
                    recentTokens = (
                        listOf(tokenBalance) +
                            result.recentTokens.orEmpty()
                                .filterNot { it.token == tokenBalance.token }
                        ).take(ExploreHistoryStore.RECENT_TOKENS_LIMIT)
                )
            )
        }
        val targetNavigationController =
            navigationController?.tabBarController?.mainNavigationController
                ?: navigationController
        targetNavigationController?.push(TokenVC(context, account, token))
    }

    internal fun openAgent(prompt: String) {
        val navigationController = navigationController ?: return
        if (navigationController.tabBarController?.switchToAgent(prompt) == true) return
        navigationController.push(AgentVC(context, initialPrompt = prompt))
    }

    private fun openRecentChat(messageId: String) {
        val navigationController = navigationController ?: return
        if (navigationController.tabBarController?.switchToAgent(
                pinnedMessageId = messageId
            ) == true
        ) {
            return
        }
        navigationController.push(AgentVC(context, initialPinnedMessageId = messageId))
    }

    private fun searchInGoogle(keyword: String) {
        val url = InAppBrowserVC.GOOGLE_SEARCH_URL + URLEncoder.encode(keyword, "UTF-8")
        openInAppBrowser(
            InAppBrowserConfig(
                url = url,
                injectDappConnect = true,
                saveInVisitedHistory = false
            )
        )
        ExploreHistoryStore.saveSearchHistory(keyword)
    }

    internal fun openInAppBrowser(config: InAppBrowserConfig) {
        val inAppBrowserVC = InAppBrowserVC(
            context,
            navigationController?.tabBarController,
            config
        )
        val nav = WNavigationController(window!!)
        nav.setRoot(inAppBrowserVC)
        window!!.present(nav)
    }

    internal fun createCell(cellType: WCell.Type): WCell = if (enhancedSearchEnabled) {
        createEnhancedCell(cellType)
    } else {
        createLegacyCell(cellType)
    }

    private fun createEnhancedCell(cellType: WCell.Type): WCell = when (cellType) {
        SEARCH_MATCH_CELL -> SearchBestMatchCell(context, SearchHistoryCell(context))

        SEARCH_SECTION_CELL -> SearchSectionCell(context)

        SEARCH_CHAT_HINT_CELL ->
            SearchChatHintCell(context, onTap = { hint -> openAgent(hint.prompt) })

        SEARCH_RECENT_CHAT_CELL ->
            SearchRecentChatCell(context, onTap = { hint -> openRecentChat(hint.id) })

        SEARCH_COLLECTIBLE_CELL -> SearchCollectibleCell(context, onTap = { match ->
            openCollectible(match)
        })

        SEARCH_TOKEN_CELL -> TokenCell(context, TokensVC.Mode.HOME, compact = true).apply {
            onTap = { tokenBalance -> openToken(tokenBalance) }
        }

        SEARCH_AGENT_CELL -> SearchItemCell(
            context,
            iconRes = org.mytonwallet.app_air.icons.R.drawable.ic_agent_filled,
            iconColor = WColor.PrimaryText,
            onTap = { prompt -> openAgent(prompt) }
        )

        SEARCH_GOOGLE_CELL -> SearchItemCell(
            context,
            iconColor = WColor.PrimaryText,
            onTap = { keyword -> searchInGoogle(keyword) }
        )

        SEARCH_BEST_TOKEN_CELL -> SearchBestMatchCell(
            context,
            TokenCell(context, TokensVC.Mode.HOME, compact = true).apply {
                onTap = { tokenBalance -> openToken(tokenBalance) }
            }
        )

        SEARCH_BEST_WALLET_CELL -> SearchBestMatchCell(
            context,
            SearchWalletCell(
                context,
                onTapOwnWallet = { match -> openOwnWallet(match) },
                onTapWalletInfo = { match -> openWalletInfo(match) }
            )
        )

        SEARCH_BEST_DAPP_CELL -> SearchBestMatchCell(
            context,
            SearchDappCell(context, onTap = ::openDapp)
        )

        SEARCH_BEST_NFT_CELL -> SearchBestMatchCell(
            context,
            SearchCollectibleCell(context, onTap = { match -> openCollectible(match) })
        )

        SEARCH_APP_ITEM_CELL -> SearchAppItemCell(context, onTap = ::openAppEntry)

        SEARCH_BEST_APP_ITEM_CELL -> SearchBestMatchCell(
            context,
            SearchAppItemCell(context, onTap = ::openAppEntry)
        )

        SEARCH_BEST_AGENT_CELL -> SearchBestMatchCell(
            context,
            SearchItemCell(
                context,
                iconRes = R.drawable.ic_agent_filled,
                iconColor = WColor.PrimaryText,
                onTap = { prompt -> openAgent(prompt) }
            )
        )

        SEARCH_SELECTOR_TITLE_CELL -> SearchSelectorHeaderCell(context)

        else -> createSharedCell(cellType)
    }

    private fun createLegacyCell(cellType: WCell.Type): WCell = when (cellType) {
        SEARCH_MATCH_CELL -> SearchMatchedCell(context, onTap = { site ->
            openInAppBrowser(
                InAppBrowserConfig(
                    url = site.url,
                    injectDappConnect = true,
                    saveInVisitedHistory = true
                )
            )
        })

        else -> createSharedCell(cellType)
    }

    private fun createSharedCell(cellType: WCell.Type): WCell = when (cellType) {
        GAP_CELL -> GapCell(context)

        SEARCH_WALLET_CELL -> SearchWalletCell(
            context,
            onTapOwnWallet = { match -> openOwnWallet(match) },
            onTapWalletInfo = { match -> openWalletInfo(match) }
        )

        RECENT_SEARCH_TITLE_CELL -> {
            HeaderCell(context).apply {
                titleLabel.setStyle(14f, WFont.Medium)
                val clearAllButton = object : WLabel(context) {
                    private val ripple = WRippleDrawable.create(20f.dp)

                    init {
                        background = ripple
                    }

                    override fun updateTheme() {
                        super.updateTheme()
                        ripple.rippleColor = WColor.TintRipple.color
                    }
                }.apply {
                    text = LocaleController.getString("Clear All")
                    setStyle(14f, WFont.Regular)
                    setTextColor(WColor.Tint)
                    setPadding(12.dp, 4.dp, 12.dp, 4.dp)
                    setOnClickListener {
                        if (enhancedSearchEnabled) {
                            ExploreHistoryStore.clearSearchHistory()
                            searchResult?.let { result ->
                                updateSearchResult(result.copy(recentSearches = emptyList()))
                            }
                        } else {
                            ExploreHistoryStore.clearAccountHistory()
                            navigationController?.pop()
                        }
                    }
                    tag = CLEAR_ALL_BUTTON_TAG
                    updateTheme()
                }
                addView(clearAllButton)
                setConstraints {
                    toEnd(clearAllButton, 8f)
                    centerYToCenterY(clearAllButton, titleLabel)
                }
            }
        }

        SEARCH_TITLE_CELL -> HeaderCell(context)

        SEARCH_SEARCHED_CELL -> SearchItemCell(context, onTap = { history ->
            if (WalletContextManager.delegate?.get()?.handleDeeplink(history) == true) {
                return@SearchItemCell
            }
            val (isValidUrl, uri) = InAppBrowserVC.convertToUri(history)
            openInAppBrowser(
                InAppBrowserConfig(
                    url = uri.toString(),
                    injectDappConnect = true,
                    saveInVisitedHistory = isValidUrl
                )
            )
            if (!isValidUrl) ExploreHistoryStore.saveSearchHistory(history)
        })

        SEARCH_DAPP_CELL -> SearchDappCell(context, onTap = ::openDapp)

        SEARCH_HISTORY_CELL -> SearchHistoryCell(context)

        else -> throw IllegalStateException("Unexpected search cell type: $cellType")
    }
}
