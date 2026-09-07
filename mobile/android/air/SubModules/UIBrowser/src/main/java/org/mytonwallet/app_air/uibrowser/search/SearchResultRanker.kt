package org.mytonwallet.app_air.uibrowser.search

import androidx.core.net.toUri
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVM
import org.mytonwallet.app_air.walletcore.models.MAssetsAndActivityData
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.IDapp
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

/**
 * The entity a ranked hit points back to, so the caller can open it without re-deriving which
 * collection the document came from.
 */
sealed interface SearchTarget {
    data class WalletInfo(val match: ExploreVM.WalletInfoMatch) : SearchTarget
    data class OwnWallet(val match: ExploreVM.MyWalletMatch) : SearchTarget
    data class Site(val site: MExploreHistory.VisitedSite) : SearchTarget
    data class Token(val tokenBalance: MTokenBalance) : SearchTarget
    data class Collectible(val match: ExploreVM.CollectibleMatch) : SearchTarget
    data class Dapp(val dapp: IDapp) : SearchTarget
    data class App(val entry: AppSearchEntry) : SearchTarget
    object AskAgent : SearchTarget
}

/**
 * Ranks every candidate in a [ExploreVM.SearchResult] against the query in one ordered list, so the
 * promoted row and the keyboard action both follow relevance instead of a fixed category order.
 *
 * Popularity is only known for the explore catalog feed; every other document ranks on relevance,
 * ownership, and balance.
 */
object SearchResultRanker {
    private val engine = UniversalSearchEngine()

    fun rank(result: ExploreVM.SearchResult): List<UniversalSearchHit> {
        val query = UniversalSearchQuery(result.keyword)
        if (query.isEmpty) return emptyList()
        return engine.search(query, documents(result))
    }

    private fun documents(result: ExploreVM.SearchResult): List<IndexedSearchDocument> {
        val documents = ArrayList<SearchDocument>()
        val trackedSlugs = trackedSlugs()
        result.walletInfo?.let { documents.add(walletInfoDocument(it)) }
        result.myWallets?.forEach { documents.add(ownWalletDocument(it)) }
        result.matchedVisitedSite?.let { documents.add(siteDocument(it)) }
        result.recentVisitedSites?.forEach { documents.add(siteDocument(it)) }
        result.tokens?.forEach { tokenDocument(it, trackedSlugs)?.let(documents::add) }
        result.collectibles?.forEach { documents.add(collectibleDocument(it)) }
        val connectedHosts = connectedDappHosts()
        result.dapps?.forEachIndexed { index, dapp ->
            documents.add(dappDocument(dapp, catalogRank = index + 1, connectedHosts))
        }
        result.actions?.forEach { documents.add(appEntryDocument(it)) }
        result.settings?.forEach { documents.add(appEntryDocument(it)) }
        return documents.distinctBy { it.id }.map { IndexedSearchDocument(it) }
    }

    /** A well-known address or domain resolved through the API; always an exact identifier hit. */
    private fun walletInfoDocument(match: ExploreVM.WalletInfoMatch) = SearchDocument(
        id = "wallet-info:${match.chain.name}:${match.address}",
        kind = SearchEntityKind.WALLET,
        fields = listOfNotNull(
            SearchField(match.address, SearchFieldKind.ADDRESS),
            match.domain?.let { SearchField(it, SearchFieldKind.DOMAIN) },
            match.name?.let { SearchField(it, SearchFieldKind.TITLE) }
        ),
        signals = SearchSignals(traits = setOf(SearchTrait.EXTERNAL)),
        payload = SearchTarget.WalletInfo(match)
    )

    private fun ownWalletDocument(match: ExploreVM.MyWalletMatch): SearchDocument {
        val fields = ArrayList<SearchField>()
        match.account.name.takeIf { it.isNotEmpty() }
            ?.let { fields.add(SearchField(it, SearchFieldKind.TITLE)) }
        match.account.byChain.forEach { (_, info) ->
            fields.add(SearchField(info.address, SearchFieldKind.ADDRESS))
            info.domain?.let { fields.add(SearchField(it, SearchFieldKind.DOMAIN)) }
        }
        val traits = HashSet<SearchTrait>()
        traits.add(SearchTrait.OWNED)
        if (match.account.isViewOnly) traits.add(SearchTrait.VIEW_ONLY)
        return SearchDocument(
            id = "own-wallet:${match.account.accountId}",
            kind = SearchEntityKind.WALLET,
            fields = fields,
            signals = SearchSignals(traits = traits),
            payload = SearchTarget.OwnWallet(match)
        )
    }

    private fun siteDocument(site: MExploreHistory.VisitedSite) = SearchDocument(
        id = "site:${site.url}",
        kind = SearchEntityKind.SITE,
        fields = listOf(
            SearchField(site.title, SearchFieldKind.TITLE),
            SearchField(site.url, SearchFieldKind.URL)
        ),
        signals = SearchSignals(traits = setOf(SearchTrait.FROM_HISTORY)),
        payload = SearchTarget.Site(site)
    )

    private fun tokenDocument(
        tokenBalance: MTokenBalance,
        trackedSlugs: Set<String>
    ): SearchDocument? {
        val slug = tokenBalance.token ?: return null
        val token = TokenStore.getToken(slug)
        val fields = ArrayList<SearchField>()
        token?.symbol?.takeIf { it.isNotEmpty() }
            ?.let { fields.add(SearchField(it, SearchFieldKind.SYMBOL)) }
        token?.name?.takeIf { it.isNotEmpty() }
            ?.let { fields.add(SearchField(it, SearchFieldKind.TITLE)) }
        token?.localizedName?.takeIf { it.isNotEmpty() && it != token.name }
            ?.let { fields.add(SearchField(it, SearchFieldKind.ALIAS)) }
        token?.tokenAddress?.takeIf { it.isNotEmpty() }
            ?.let { fields.add(SearchField(it, SearchFieldKind.ADDRESS)) }
        token?.keywords?.forEach { fields.add(SearchField(it, SearchFieldKind.KEYWORD)) }
        if (fields.isEmpty()) return null

        val traits = HashSet<SearchTrait>()
        if (tokenBalance.amountValue.signum() > 0) {
            traits.add(SearchTrait.HELD)
        } else if (slug in trackedSlugs) {
            traits.add(SearchTrait.TRACKED)
        }
        if (token?.isPopular == true) traits.add(SearchTrait.POPULAR)
        if (token?.price != null) traits.add(SearchTrait.HAS_MARKET_DATA)

        return SearchDocument(
            id = "token:$slug",
            kind = SearchEntityKind.TOKEN,
            fields = fields,
            signals = SearchSignals(
                traits = traits,
                baseCurrencyValue = tokenBalance.toBaseCurrency ?: tokenBalance.toUsdBaseCurrency
            ),
            payload = SearchTarget.Token(tokenBalance)
        )
    }

    private fun collectibleDocument(match: ExploreVM.CollectibleMatch): SearchDocument =
        when (match) {
            is ExploreVM.CollectibleMatch.Nft -> nftDocument(match, match.nft)

            is ExploreVM.CollectibleMatch.Collection -> SearchDocument(
                id = "collection:${match.collection.address}",
                kind = SearchEntityKind.COLLECTION,
                fields = listOf(
                    SearchField(match.collection.name, SearchFieldKind.TITLE),
                    SearchField(match.collection.address, SearchFieldKind.ADDRESS)
                ),
                signals = SearchSignals(traits = setOf(SearchTrait.OWNED)),
                payload = SearchTarget.Collectible(match)
            )
        }

    private fun nftDocument(match: ExploreVM.CollectibleMatch, nft: ApiNft): SearchDocument {
        val fields = ArrayList<SearchField>()
        nft.name?.takeIf { it.isNotEmpty() }
            ?.let { fields.add(SearchField(it, SearchFieldKind.TITLE)) }
        nft.collectionName?.takeIf { it.isNotEmpty() }
            ?.let { fields.add(SearchField(it, SearchFieldKind.ALIAS)) }
        fields.add(SearchField(nft.address, SearchFieldKind.ADDRESS))

        val traits = HashSet<SearchTrait>()
        traits.add(SearchTrait.OWNED)
        if (nft.isUnverified != true && nft.isScam != true) traits.add(SearchTrait.VERIFIED)

        return SearchDocument(
            id = "nft:${nft.address}",
            kind = SearchEntityKind.COLLECTIBLE,
            fields = fields,
            signals = SearchSignals(traits = traits),
            payload = SearchTarget.Collectible(match)
        )
    }

    private fun dappDocument(
        dapp: IDapp,
        catalogRank: Int?,
        connectedHosts: Set<String>
    ): SearchDocument {
        val fields = ArrayList<SearchField>()
        dapp.name?.takeIf { it.isNotEmpty() }
            ?.let { fields.add(SearchField(it, SearchFieldKind.TITLE)) }
        dapp.url?.takeIf { it.isNotEmpty() }
            ?.let { fields.add(SearchField(it, SearchFieldKind.URL)) }
        // The raw URL keeps its scheme once normalized, so only the bare host can phrase-prefix.
        siteHost(dapp.url)?.let { fields.add(SearchField(it, SearchFieldKind.DOMAIN)) }

        val traits = HashSet<SearchTrait>()
        var popularityRank: Int? = null
        if (dapp is MExploreSite) {
            traits.add(SearchTrait.CURATED)
            traits.add(SearchTrait.POPULAR)
            if (dapp.isVerified) traits.add(SearchTrait.VERIFIED)
            if (dapp.isFeatured) traits.add(SearchTrait.TRENDING)
            if (rawHost(dapp.url) in connectedHosts) traits.add(SearchTrait.CONNECTED)
            dapp.description?.takeIf { it.isNotEmpty() }
                ?.let { fields.add(SearchField(it, SearchFieldKind.DESCRIPTION)) }
            popularityRank = catalogRank
        } else {
            traits.add(SearchTrait.CONNECTED)
        }

        return SearchDocument(
            id = "dapp:${canonicalDappId(dapp)}",
            kind = SearchEntityKind.APPLICATION,
            fields = fields,
            signals = SearchSignals(traits = traits, popularityRank = popularityRank),
            payload = SearchTarget.Dapp(dapp)
        )
    }

    private fun appEntryDocument(entry: AppSearchEntry) = SearchDocument(
        id = entry.id,
        kind = if (entry.isAction) SearchEntityKind.ACTION else SearchEntityKind.SETTING,
        fields = buildList {
            add(SearchField(entry.title, SearchFieldKind.TITLE))
            entry.aliases.forEach { add(SearchField(it, SearchFieldKind.ALIAS)) }
            entry.keywords.forEach { add(SearchField(it, SearchFieldKind.KEYWORD)) }
        },
        payload = SearchTarget.App(entry)
    )

    /** Zero-balance tokens the account still monitors, added through Assets & Activity. */
    private fun trackedSlugs(): Set<String> {
        val accountId = AccountStore.activeAccountId ?: return emptySet()
        val assetsData = MAssetsAndActivityData(accountId)
        return buildSet {
            addAll(assetsData.addedTokens)
            addAll(assetsData.visibleTokens)
        }
    }

    private fun connectedDappHosts(): Set<String> {
        val accountId = AccountStore.activeAccountId ?: return emptySet()
        return DappsStore.dApps[accountId].orEmpty().mapNotNullTo(HashSet()) { rawHost(it.url) }
    }

    private fun canonicalDappId(dapp: IDapp): String {
        val url = dapp.url?.takeIf { it.isNotEmpty() } ?: return dapp.name.orEmpty()
        val host = rawHost(url) ?: return url.trim().lowercase()
        if (host == "t.me" || host == "telegram.me") {
            val username = firstPathSegment(url)
            return if (username == null) host else "t.me/$username"
        }
        return host.removePrefix("www.")
    }

    private fun siteHost(url: String?): String? {
        val host = rawHost(url) ?: return null
        return if (host == "t.me") firstPathSegment(url) else host
    }

    private fun rawHost(url: String?): String? =
        runCatching { url?.toUri()?.host }.getOrNull()?.lowercase()?.takeIf { it.isNotEmpty() }

    private fun firstPathSegment(url: String?): String? =
        runCatching { url?.toUri()?.pathSegments?.firstOrNull() }
            .getOrNull()
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }
}
