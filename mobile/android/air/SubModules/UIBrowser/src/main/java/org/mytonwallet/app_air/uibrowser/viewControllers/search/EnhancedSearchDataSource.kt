package org.mytonwallet.app_air.uibrowser.viewControllers.search

import androidx.core.net.toUri
import androidx.core.view.isGone
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.cells.TokenCell
import org.mytonwallet.app_air.uibrowser.search.AppSearchEntry
import org.mytonwallet.app_air.uibrowser.search.SearchRelevanceBand
import org.mytonwallet.app_air.uibrowser.search.SearchResultRanker
import org.mytonwallet.app_air.uibrowser.search.SearchTarget
import org.mytonwallet.app_air.uibrowser.search.UniversalSearchHit
import org.mytonwallet.app_air.uibrowser.search.UniversalSearchQuery
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVM
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.CLEAR_ALL_BUTTON_TAG
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.GAP_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.RECENT_SEARCH_TITLE_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_AGENT_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_APP_ITEM_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_BEST_AGENT_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_BEST_APP_ITEM_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_BEST_DAPP_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_BEST_NFT_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_BEST_TOKEN_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_BEST_WALLET_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_CHAT_HINT_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_COLLECTIBLE_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_DAPP_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_GOOGLE_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_HISTORY_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_MATCH_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_RECENT_CHAT_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_SEARCHED_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_SECTION_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_SELECTOR_TITLE_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_TITLE_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_TOKEN_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SEARCH_WALLET_CELL
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_ACTIONS
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_AGENT
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_BEST_MATCH
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_CHATS
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_COLLECTIBLES
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_DAPPS
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_GOOGLE
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_MY_WALLETS
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_RECENT_QUERIES
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_SETTINGS
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_SITES
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_SUGGESTIONS
import org.mytonwallet.app_air.uibrowser.viewControllers.search.SearchVC.Companion.SECTION_TOKENS
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchAppItemCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchBestMatchCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchChatHintCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchCollectibleCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchDappCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchHistoryCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchItemCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchRecentChatCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchSectionCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchSelectorHeaderCell
import org.mytonwallet.app_air.uibrowser.viewControllers.search.cells.SearchWalletCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkParser
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.moshi.IDapp
import org.mytonwallet.app_air.walletcore.stores.AccountStore

internal class EnhancedSearchDataSource(searchVC: SearchVC) : SearchDataSource(searchVC) {
    private var emptyTokenMode = SearchSelectorHeaderCell.Mode.RECENT
    private var emptyDappMode = SearchSelectorHeaderCell.Mode.RECENT

    private var isSearchQueryDeeplink = false

    /** The single promoted row; every "regular" list below excludes whatever it holds. */
    private var bestMatchTarget: SearchTarget? = null
    private var regularWalletMatches: List<ExploreVM.MyWalletMatch> = emptyList()
    private var regularTokenMatches: List<MTokenBalance> = emptyList()
    private var regularSiteMatches: List<MExploreHistory.VisitedSite> = emptyList()
    private var regularDappMatches: List<IDapp> = emptyList()
    private var regularCollectibleMatches: List<ExploreVM.CollectibleMatch> = emptyList()
    private var regularActionMatches: List<AppSearchEntry> = emptyList()
    private var regularSettingMatches: List<AppSearchEntry> = emptyList()

    /** The result the rows currently on screen were built from. */
    private var displayedResult: ExploreVM.SearchResult? = null

    /**
     * Ranking normalizes every candidate's fields, and onSearchStateChanged runs again for state
     * that does not produce a new result (query keystrokes ahead of it), so the hits are reused
     * while the result instance is unchanged.
     */
    private var rankedHitsFor: ExploreVM.SearchResult? = null
    private var rankedHits: List<UniversalSearchHit> = emptyList()
    private var rankedTarget: SearchTarget? = null

    override fun onSearchStateChanged() {
        val result = searchResult
        isSearchQueryDeeplink = searchQuery.takeIf { it.isNotBlank() }
            ?.let { DeeplinkParser.parse(it.toUri()) } != null

        // searchResult lags the field, so keep the previous query's rows until the new ones land
        // rather than blanking the list on every keystroke. An empty-query result is dropped
        // instead, since its suggestion lists belong to a different screen state. openBestMatch()
        // still waits for a result matching the current query, so a stale row is never opened.
        val freshResult = result?.takeIf { searchQuery.isNotEmpty() && it.keyword.isNotEmpty() }
        displayedResult = freshResult

        // One ranked list decides the promoted row, so relevance rather than entity category picks
        // it, and the keyboard action opens exactly the row that is shown as the best match.
        if (rankedHitsFor !== freshResult) {
            rankedHitsFor = freshResult
            rankedHits = freshResult?.let { SearchResultRanker.rank(it) }.orEmpty()
            rankedTarget = freshResult?.let { promotedTarget(it.keyword, rankedHits) }
        }
        val target = rankedTarget
        bestMatchTarget = target

        regularWalletMatches = freshResult?.myWallets.orEmpty().let { matches ->
            val promoted = (target as? SearchTarget.OwnWallet)?.match
            if (promoted == null) matches else matches.filterNot { it == promoted }
        }
        regularTokenMatches = freshResult?.tokens.orEmpty().let { matches ->
            val promoted = (target as? SearchTarget.Token)?.tokenBalance
            val remaining =
                if (promoted == null) matches else matches.filterNot { it == promoted }
            // Follow the ranked order so a stronger name match outranks a larger balance; anything
            // the ranker did not score keeps its original position behind what it did.
            val rankedOrder = rankedHits
                .mapNotNull { (it.document.payload as? SearchTarget.Token)?.tokenBalance }
                .withIndex()
                .associate { (index, tokenBalance) -> tokenBalance to index }
            remaining.sortedBy { token -> rankedOrder[token] ?: Int.MAX_VALUE }
        }
        regularSiteMatches = freshResult?.recentVisitedSites.orEmpty().let { matches ->
            val promoted = (target as? SearchTarget.Site)?.site
            if (promoted == null) matches else matches.filterNot { it.url == promoted.url }
        }
        regularDappMatches = freshResult?.dapps.orEmpty().let { matches ->
            val promoted = (target as? SearchTarget.Dapp)?.dapp
            if (promoted == null) matches else matches.filterNot { it.url == promoted.url }
        }
        regularCollectibleMatches = freshResult?.collectibles.orEmpty().let { matches ->
            val promoted = (target as? SearchTarget.Collectible)?.match
            if (promoted == null) matches else matches.filterNot { it == promoted }
        }
        val promotedEntry = (target as? SearchTarget.App)?.entry
        regularActionMatches = freshResult?.actions.orEmpty()
            .filterNot { it.id == promotedEntry?.id }
        regularSettingMatches = freshResult?.settings.orEmpty()
            .filterNot { it.id == promotedEntry?.id }
    }

    /** A multi-word query is a request unless a hit covers all of its terms. */
    private fun promotedTarget(keyword: String, hits: List<UniversalSearchHit>): SearchTarget? {
        val topHit = hits.firstOrNull() ?: return SearchTarget.AskAgent.takeIf {
            UniversalSearchQuery(keyword).termCount > 1
        }
        val rank = topHit.rank
        val isWeakHit = rank.relevanceBand == SearchRelevanceBand.WEAK ||
            rank.matchedTermCount < rank.totalTermCount
        return if (isWeakHit && rank.totalTermCount > 1) {
            SearchTarget.AskAgent
        } else {
            topHit.document.payload as? SearchTarget
        }
    }

    private val hasRecentTokenSuggestions: Boolean
        get() = !searchResult?.recentTokens.isNullOrEmpty()

    private val selectedEmptyTokenMode: SearchSelectorHeaderCell.Mode
        get() = if (
            emptyTokenMode == SearchSelectorHeaderCell.Mode.RECENT &&
            !hasRecentTokenSuggestions
        ) {
            SearchSelectorHeaderCell.Mode.TRENDING
        } else {
            emptyTokenMode
        }

    private val visibleTokenMatches: List<MTokenBalance>
        get() {
            val result = searchResult ?: return emptyList()
            // The recent/trending lists belong to the empty-query state only.
            if (searchQuery.isNotEmpty()) return regularTokenMatches
            return when (selectedEmptyTokenMode) {
                SearchSelectorHeaderCell.Mode.RECENT -> result.recentTokens.orEmpty()
                SearchSelectorHeaderCell.Mode.TRENDING -> result.trendingTokens.orEmpty()
                SearchSelectorHeaderCell.Mode.SUGGEST -> emptyList()
            }
        }

    private val hasRecentDappSuggestions: Boolean
        get() = !searchResult?.recentDapps.isNullOrEmpty()

    private val hasTrendingDappSuggestions: Boolean
        get() = !searchResult?.trendingDapps.isNullOrEmpty()

    private val selectedEmptyDappMode: SearchSelectorHeaderCell.Mode
        get() = if (
            emptyDappMode == SearchSelectorHeaderCell.Mode.RECENT &&
            !hasRecentDappSuggestions
        ) {
            SearchSelectorHeaderCell.Mode.TRENDING
        } else {
            emptyDappMode
        }

    private val visibleDappMatches: List<IDapp>
        get() {
            val result = searchResult ?: return emptyList()
            if (searchQuery.isNotEmpty()) return regularDappMatches
            return when (selectedEmptyDappMode) {
                SearchSelectorHeaderCell.Mode.RECENT -> result.recentDapps.orEmpty()
                SearchSelectorHeaderCell.Mode.TRENDING -> result.trendingDapps.orEmpty()
                SearchSelectorHeaderCell.Mode.SUGGEST -> emptyList()
            }
        }

    private val visibleRecentChats
        get() = if (searchQuery.isEmpty()) {
            searchResult?.recentChats.orEmpty().take(1)
        } else {
            emptyList()
        }

    private val visibleSuggestedChats
        get() = if (searchQuery.isEmpty()) {
            searchResult?.suggestedChats.orEmpty()
        } else {
            emptyList()
        }

    override fun openBestMatch(): BestMatchResult {
        val result = searchResult?.takeIf { it.keyword == searchQuery }
            ?: return BestMatchResult.PENDING

        // A resolving address lookup can still outrank everything found so far, so wait for it
        // rather than opening a weaker match that the promoted row is about to replace.
        if (result.isWalletInfoLookupPending) return BestMatchResult.PENDING

        when (val target = bestMatchTarget) {
            is SearchTarget.WalletInfo -> openWalletInfo(target.match)

            is SearchTarget.OwnWallet -> openOwnWallet(target.match)

            is SearchTarget.Site -> openInAppBrowser(
                InAppBrowserConfig(
                    url = target.site.url,
                    injectDappConnect = true,
                    saveInVisitedHistory = true
                )
            )

            is SearchTarget.Token -> openToken(target.tokenBalance)

            is SearchTarget.Dapp -> openDapp(target.dapp)

            is SearchTarget.Collectible -> openCollectible(target.match)

            is SearchTarget.App -> searchVC.openAppEntry(target.entry)

            SearchTarget.AskAgent -> searchVC.openAgent(searchQuery)

            null -> return BestMatchResult.NOT_FOUND
        }
        return BestMatchResult.OPENED
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = SECTION_GOOGLE + 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = when (section) {
        SECTION_CHATS -> {
            // Header + one row per non-empty list (recent conversation, suggestion chips) + gap.
            val contentRows = (if (visibleRecentChats.isEmpty()) 0 else 1) +
                (if (visibleSuggestedChats.isEmpty()) 0 else 1)
            if (contentRows == 0) 0 else contentRows + 2
        }

        SECTION_MY_WALLETS -> {
            if (regularWalletMatches.isEmpty()) {
                0
            } else {
                3
            }
        }

        SECTION_BEST_MATCH -> {
            if (bestMatchTarget == null) 0 else 2
        }

        SECTION_RECENT_QUERIES -> {
            if (searchQuery.isEmpty() && !searchResult?.recentSearches.isNullOrEmpty()) {
                3
            } else {
                0
            }
        }

        SECTION_SUGGESTIONS -> {
            if (bestMatchTarget !is SearchTarget.Site &&
                !displayedResult?.recentSearches.isNullOrEmpty() &&
                displayedResult?.noResultsFound != true
            ) {
                3
            } else {
                0
            }
        }

        SECTION_DAPPS -> {
            if (visibleDappMatches.isEmpty()) 0 else 3
        }

        SECTION_TOKENS -> {
            if (visibleTokenMatches.isNotEmpty()) {
                3
            } else {
                0
            }
        }

        SECTION_COLLECTIBLES -> {
            if (regularCollectibleMatches.isEmpty()) 0 else 3
        }

        SECTION_ACTIONS -> {
            if (regularActionMatches.isEmpty()) 0 else 3
        }

        SECTION_SETTINGS -> {
            if (regularSettingMatches.isEmpty()) 0 else 3
        }

        SECTION_AGENT -> {
            if (searchQuery.isBlank() || bestMatchTarget is SearchTarget.AskAgent) 0 else 3
        }

        SECTION_SITES -> {
            if (regularSiteMatches.isEmpty()) 0 else 3
        }

        SECTION_GOOGLE -> {
            if (searchQuery.isBlank()) 0 else 3
        }

        else -> throw IllegalStateException("Unexpected search section: $section")
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        if (indexPath.row == 0) {
            return when (indexPath.section) {
                SECTION_BEST_MATCH -> when (bestMatchTarget) {
                    is SearchTarget.WalletInfo, is SearchTarget.OwnWallet -> SEARCH_BEST_WALLET_CELL
                    is SearchTarget.Site -> SEARCH_MATCH_CELL
                    is SearchTarget.Token -> SEARCH_BEST_TOKEN_CELL
                    is SearchTarget.Dapp -> SEARCH_BEST_DAPP_CELL
                    is SearchTarget.Collectible -> SEARCH_BEST_NFT_CELL
                    is SearchTarget.App -> SEARCH_BEST_APP_ITEM_CELL
                    SearchTarget.AskAgent -> SEARCH_BEST_AGENT_CELL
                    null -> SEARCH_BEST_TOKEN_CELL
                }

                SECTION_RECENT_QUERIES -> {
                    RECENT_SEARCH_TITLE_CELL
                }

                SECTION_TOKENS -> {
                    SEARCH_SELECTOR_TITLE_CELL
                }

                SECTION_DAPPS -> {
                    SEARCH_SELECTOR_TITLE_CELL
                }

                else -> {
                    SEARCH_TITLE_CELL
                }
            }
        }
        if (indexPath.row == recyclerViewNumberOfItems(rv, indexPath.section) - 1) {
            return GAP_CELL
        }

        return when (indexPath.section) {
            SECTION_AGENT -> SEARCH_AGENT_CELL

            SECTION_GOOGLE -> {
                if (isSearchQueryDeeplink) SEARCH_SEARCHED_CELL else SEARCH_GOOGLE_CELL
            }

            SECTION_MY_WALLETS,
            SECTION_CHATS,
            SECTION_RECENT_QUERIES,
            SECTION_SUGGESTIONS,
            SECTION_TOKENS,
            SECTION_COLLECTIBLES,
            SECTION_DAPPS,
            SECTION_ACTIONS,
            SECTION_SETTINGS,
            SECTION_SITES -> SEARCH_SECTION_CELL

            else -> throw IllegalStateException(
                "Unexpected search section: ${indexPath.section}"
            )
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        if (configureGapCell(rv, cellHolder, indexPath)) return

        when (indexPath.section) {
            SECTION_CHATS -> {
                val recentChats = visibleRecentChats
                val suggestedChats = visibleSuggestedChats
                if (indexPath.row == 0) {
                    configureSectionHeader(
                        cellHolder,
                        indexPath,
                        LocaleController.getString("Chats")
                    )
                } else if (indexPath.row == 1 && recentChats.isNotEmpty()) {
                    (cellHolder.cell as SearchSectionCell).configure(
                        recentChats.size,
                        60.dp,
                        SEARCH_RECENT_CHAT_CELL,
                        contentIdentity = recentChats.map { it.id },
                        bottomRadius = if (suggestedChats.isEmpty()) {
                            ViewConstants.BLOCK_RADIUS.dp
                        } else {
                            0f
                        },
                        createCell = { createCell(SEARCH_RECENT_CHAT_CELL) },
                        configureCell = { cell, itemIndex, isLastItem ->
                            (cell as SearchRecentChatCell).configure(
                                recentChats[itemIndex],
                                isLastItem
                            )
                        }
                    )
                } else {
                    (cellHolder.cell as SearchSectionCell).configure(
                        suggestedChats.size,
                        44.dp,
                        SEARCH_CHAT_HINT_CELL,
                        contentIdentity = suggestedChats.map { it.id },
                        maximumItemWidths = SearchChatHintCell.hintCellWidths(
                            context,
                            suggestedChats
                        ),
                        rowSpacing = 12.dp,
                        verticalPadding = 12.dp,
                        horizontalEndSpacing = SearchChatHintCell.SECTION_END_SPACING.dp,
                        createCell = { createCell(SEARCH_CHAT_HINT_CELL) },
                        configureCell = { cell, itemIndex, _ ->
                            (cell as SearchChatHintCell).configure(suggestedChats[itemIndex])
                        }
                    )
                }
            }

            SECTION_MY_WALLETS -> {
                if (indexPath.row == 0) {
                    configureSectionHeader(
                        cellHolder,
                        indexPath,
                        LocaleController.getString("Wallets")
                    )
                } else {
                    val wallets = regularWalletMatches
                    (cellHolder.cell as SearchSectionCell).configure(
                        wallets.size,
                        60.dp,
                        SEARCH_WALLET_CELL,
                        contentIdentity = wallets.map { it.account.accountId },
                        createCell = { createCell(SEARCH_WALLET_CELL) },
                        configureCell = { cell, itemIndex, isLastItem ->
                            (cell as SearchWalletCell).configure(
                                wallets[itemIndex],
                                isLastItem,
                                hasOpaqueBackground = false
                            )
                        }
                    )
                }
            }

            // One promoted row, captioned by whatever kind the ranker put first.
            SECTION_BEST_MATCH -> {
                val bestMatchCell = cellHolder.cell as SearchBestMatchCell
                when (val target = bestMatchTarget) {
                    is SearchTarget.WalletInfo -> {
                        bestMatchCell.configure(LocaleController.getString("View Wallet"))
                        (bestMatchCell.contentCell as SearchWalletCell).configure(
                            target.match,
                            isLastItem = true,
                            hasOpaqueBackground = false
                        )
                    }

                    is SearchTarget.OwnWallet -> {
                        bestMatchCell.configure(LocaleController.getString("Wallet"))
                        (bestMatchCell.contentCell as SearchWalletCell).configure(
                            target.match,
                            isLastItem = true,
                            hasOpaqueBackground = false
                        )
                    }

                    is SearchTarget.Site -> {
                        bestMatchCell.configure(LocaleController.getString("Site"))
                        (bestMatchCell.contentCell as SearchHistoryCell).configure(
                            target.site,
                            isLastItem = true,
                            hasOpaqueBackground = false,
                            onTap = {
                                openInAppBrowser(
                                    InAppBrowserConfig(
                                        url = target.site.url,
                                        injectDappConnect = true,
                                        saveInVisitedHistory = true
                                    )
                                )
                            }
                        )
                    }

                    is SearchTarget.Token -> {
                        val account = AccountStore.activeAccount ?: return
                        bestMatchCell.configure(LocaleController.getString("Token"))
                        (bestMatchCell.contentCell as TokenCell).configure(
                            account.accountId,
                            account.isMultichain,
                            target.tokenBalance,
                            isPinned = false,
                            isFirst = false,
                            isLast = true
                        )
                    }

                    is SearchTarget.Dapp -> {
                        bestMatchCell.configure(LocaleController.getString("App"))
                        (bestMatchCell.contentCell as SearchDappCell).configure(
                            target.dapp,
                            isLastItem = true,
                            hasOpaqueBackground = false
                        )
                    }

                    is SearchTarget.Collectible -> {
                        bestMatchCell.configure(LocaleController.getString("Collectible"))
                        (bestMatchCell.contentCell as SearchCollectibleCell).configure(
                            target.match,
                            isLastItem = true,
                            hasOpaqueBackground = false
                        )
                    }

                    is SearchTarget.App -> {
                        bestMatchCell.configure(
                            LocaleController.getString(
                                if (target.entry.isAction) "Action" else "Settings"
                            )
                        )
                        (bestMatchCell.contentCell as SearchAppItemCell).configure(
                            target.entry,
                            isLastItem = true,
                            hasOpaqueBackground = false
                        )
                    }

                    SearchTarget.AskAgent -> {
                        bestMatchCell.configure(LocaleController.getString("Ask Agent"))
                        (bestMatchCell.contentCell as SearchItemCell).configure(
                            searchQuery,
                            isLastItem = true,
                            hasOpaqueBackground = false
                        )
                    }

                    null -> return
                }
            }

            SECTION_RECENT_QUERIES -> {
                if (indexPath.row == 0) {
                    (cellHolder.cell as HeaderCell).apply {
                        findViewWithTag<WButton>(CLEAR_ALL_BUTTON_TAG).isGone = false
                    }
                    configureSectionHeader(
                        cellHolder,
                        indexPath,
                        LocaleController.getString("Recent Searches")
                    )
                } else {
                    val recentSearches = searchResult?.recentSearches.orEmpty()
                    (cellHolder.cell as SearchSectionCell).configure(
                        recentSearches.size,
                        50.dp,
                        SEARCH_SEARCHED_CELL,
                        contentIdentity = recentSearches.map { it.title },
                        createCell = { createCell(SEARCH_SEARCHED_CELL) },
                        configureCell = { cell, itemIndex, isLastItem ->
                            (cell as SearchItemCell).configure(
                                recentSearches[itemIndex].title,
                                isLastItem,
                                hasOpaqueBackground = false
                            )
                        }
                    )
                }
            }

            SECTION_SUGGESTIONS -> {
                if (indexPath.row == 0) {
                    configureSectionHeader(
                        cellHolder,
                        indexPath,
                        LocaleController.getString("Recent Searches")
                    )
                } else {
                    val suggestions = displayedResult?.recentSearches.orEmpty()
                    (cellHolder.cell as SearchSectionCell).configure(
                        suggestions.size,
                        60.dp,
                        SEARCH_HISTORY_CELL,
                        contentIdentity = suggestions.map { it.title },
                        createCell = { createCell(SEARCH_HISTORY_CELL) },
                        configureCell = { cell, itemIndex, isLastItem ->
                            val search = suggestions[itemIndex]
                            (cell as SearchHistoryCell).configure(
                                search,
                                isLastItem,
                                hasOpaqueBackground = false,
                                onTap = {
                                    val (isValidUrl, uri) =
                                        InAppBrowserVC.convertToUri(search.title)
                                    openInAppBrowser(
                                        InAppBrowserConfig(
                                            url = uri.toString(),
                                            injectDappConnect = true,
                                            saveInVisitedHistory = isValidUrl
                                        )
                                    )
                                }
                            )
                        }
                    )
                }
            }

            SECTION_DAPPS -> {
                if (indexPath.row == 0) {
                    (cellHolder.cell as SearchSelectorHeaderCell).configure(
                        title = LocaleController.getString("Apps"),
                        showsSelector = searchQuery.isEmpty() &&
                            hasRecentDappSuggestions &&
                            hasTrendingDappSuggestions,
                        selectedMode = selectedEmptyDappMode,
                        alternativeMode = SearchSelectorHeaderCell.Mode.TRENDING,
                        topRounding = topRounding(indexPath),
                        onModeSelected = { mode ->
                            val canSelect = when (mode) {
                                SearchSelectorHeaderCell.Mode.RECENT ->
                                    hasRecentDappSuggestions

                                SearchSelectorHeaderCell.Mode.TRENDING ->
                                    hasTrendingDappSuggestions

                                SearchSelectorHeaderCell.Mode.SUGGEST -> false
                            }
                            if (canSelect && emptyDappMode != mode) {
                                emptyDappMode = mode
                                rvAdapter.reloadData()
                            }
                        }
                    )
                } else {
                    val dapps = visibleDappMatches
                    (cellHolder.cell as SearchSectionCell).configure(
                        dapps.size,
                        60.dp,
                        SEARCH_DAPP_CELL,
                        contentIdentity = dapps.map { it.url ?: it.name.orEmpty() },
                        createCell = { createCell(SEARCH_DAPP_CELL) },
                        configureCell = { cell, itemIndex, isLastItem ->
                            (cell as SearchDappCell).configure(
                                dapps[itemIndex],
                                isLastItem,
                                hasOpaqueBackground = false
                            )
                        }
                    )
                }
            }

            SECTION_TOKENS -> {
                if (indexPath.row == 0) {
                    (cellHolder.cell as SearchSelectorHeaderCell).configure(
                        title = LocaleController.getString("Tokens and Stocks"),
                        showsSelector = searchQuery.isEmpty() &&
                            hasRecentTokenSuggestions,
                        selectedMode = selectedEmptyTokenMode,
                        alternativeMode = SearchSelectorHeaderCell.Mode.TRENDING,
                        topRounding = topRounding(indexPath),
                        onModeSelected = { mode ->
                            val canSelect = mode != SearchSelectorHeaderCell.Mode.RECENT ||
                                hasRecentTokenSuggestions
                            if (canSelect && emptyTokenMode != mode) {
                                emptyTokenMode = mode
                                rvAdapter.reloadData()
                            }
                        }
                    )
                } else {
                    val account = AccountStore.activeAccount ?: return
                    val tokens = visibleTokenMatches
                    (cellHolder.cell as SearchSectionCell).configure(
                        tokens.size,
                        60.dp,
                        SEARCH_TOKEN_CELL,
                        contentIdentity = tokens.map { it.token },
                        createCell = { createCell(SEARCH_TOKEN_CELL) },
                        configureCell = { cell, itemIndex, isLastItem ->
                            (cell as TokenCell).configure(
                                account.accountId,
                                account.isMultichain,
                                tokens[itemIndex],
                                isPinned = false,
                                isFirst = false,
                                isLast = isLastItem
                            )
                        }
                    )
                }
            }

            SECTION_COLLECTIBLES -> {
                if (indexPath.row == 0) {
                    configureSectionHeader(
                        cellHolder,
                        indexPath,
                        LocaleController.getString("Collectibles")
                    )
                } else {
                    val collectibles = regularCollectibleMatches
                    (cellHolder.cell as SearchSectionCell).configure(
                        collectibles.size,
                        60.dp,
                        SEARCH_COLLECTIBLE_CELL,
                        contentIdentity = collectibles.map { match ->
                            when (match) {
                                is ExploreVM.CollectibleMatch.Nft -> "nft:${match.nft.address}"

                                is ExploreVM.CollectibleMatch.Collection ->
                                    "collection:${match.collection.address}"
                            }
                        },
                        createCell = { createCell(SEARCH_COLLECTIBLE_CELL) },
                        configureCell = { cell, itemIndex, isLastItem ->
                            (cell as SearchCollectibleCell).configure(
                                collectibles[itemIndex],
                                isLastItem,
                                hasOpaqueBackground = false
                            )
                        }
                    )
                }
            }

            SECTION_ACTIONS -> configureAppEntrySection(
                cellHolder,
                indexPath,
                LocaleController.getString("Actions"),
                regularActionMatches
            )

            SECTION_SETTINGS -> configureAppEntrySection(
                cellHolder,
                indexPath,
                LocaleController.getString("Settings"),
                regularSettingMatches
            )

            SECTION_AGENT -> {
                if (indexPath.row == 0) {
                    configureSectionHeader(
                        cellHolder,
                        indexPath,
                        LocaleController.getString("Ask Agent")
                    )
                } else {
                    (cellHolder.cell as SearchItemCell).configure(
                        searchQuery,
                        isLastItem = true
                    )
                }
            }

            SECTION_SITES -> {
                if (indexPath.row == 0) {
                    configureSectionHeader(
                        cellHolder,
                        indexPath,
                        LocaleController.getString("Sites")
                    )
                } else {
                    val visitedSites = regularSiteMatches
                    (cellHolder.cell as SearchSectionCell).configure(
                        visitedSites.size,
                        60.dp,
                        SEARCH_HISTORY_CELL,
                        contentIdentity = visitedSites.map { it.url },
                        createCell = { createCell(SEARCH_HISTORY_CELL) },
                        configureCell = { cell, itemIndex, isLastItem ->
                            val site = visitedSites[itemIndex]
                            (cell as SearchHistoryCell).configure(
                                site,
                                isLastItem,
                                hasOpaqueBackground = false,
                                onTap = {
                                    openInAppBrowser(
                                        InAppBrowserConfig(
                                            url = site.url,
                                            injectDappConnect = true,
                                            saveInVisitedHistory = true
                                        )
                                    )
                                }
                            )
                        }
                    )
                }
            }

            SECTION_GOOGLE -> {
                if (indexPath.row == 0) {
                    configureSectionHeader(
                        cellHolder,
                        indexPath,
                        LocaleController.getString(
                            if (isSearchQueryDeeplink) "Open in App" else "Search in Google"
                        )
                    )
                } else {
                    (cellHolder.cell as SearchItemCell).configure(
                        searchQuery,
                        isLastItem = true
                    )
                }
            }
        }
    }

    private fun configureAppEntrySection(
        cellHolder: WCell.Holder,
        indexPath: IndexPath,
        title: String,
        entries: List<AppSearchEntry>
    ) {
        if (indexPath.row == 0) {
            configureSectionHeader(cellHolder, indexPath, title)
        } else {
            (cellHolder.cell as SearchSectionCell).configure(
                entries.size,
                60.dp,
                SEARCH_APP_ITEM_CELL,
                contentIdentity = entries.map { it.id },
                createCell = { createCell(SEARCH_APP_ITEM_CELL) },
                configureCell = { cell, itemIndex, isLastItem ->
                    (cell as SearchAppItemCell).configure(
                        entries[itemIndex],
                        isLastItem,
                        hasOpaqueBackground = false
                    )
                }
            )
        }
    }

    private fun configureSectionHeader(
        cellHolder: WCell.Holder,
        indexPath: IndexPath,
        title: String
    ) {
        (cellHolder.cell as HeaderCell).configure(
            title,
            titleColor = WColor.Tint,
            topRounding = topRounding(indexPath)
        )
    }
}
