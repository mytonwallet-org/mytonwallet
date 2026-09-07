package org.mytonwallet.app_air.uibrowser.search

import kotlin.math.max

/**
 * How trustworthy the match itself is, before any ranking signal applies. A weak band can never be
 * lifted above a strong one by popularity or ownership.
 */
enum class SearchRelevanceBand { WEAK, TERM, PHRASE, EXACT_IDENTIFIER }

enum class SearchTrustTier { UNKNOWN, ESTABLISHED, CURATED, VERIFIED }

/**
 * The full ordering of a hit. [compareTo] fixes the precedence: relevance band, term coverage,
 * entity tier, balance, trust tier, then match strength and field priority, then popularity.
 * Relevance always dominates; among equally relevant hits the entity tier decides.
 */
data class SearchRankKey(
    val relevanceBand: SearchRelevanceBand,
    val matchKind: SearchMatchKind,
    val matchedTermCount: Int,
    val totalTermCount: Int,
    val fieldPriority: Int,
    val entityPriority: Int,
    val trustTier: SearchTrustTier,
    val baseCurrencyValue: Double,
    val popularityValue: Double
) : Comparable<SearchRankKey> {

    override fun compareTo(other: SearchRankKey): Int {
        if (relevanceBand != other.relevanceBand) {
            return relevanceBand.ordinal.compareTo(other.relevanceBand.ordinal)
        }
        // Cross-multiplied so a 2-of-2 match outranks 2-of-3 without floating point.
        val coverage = matchedTermCount.toLong() * max(1, other.totalTermCount)
        val otherCoverage = other.matchedTermCount.toLong() * max(1, totalTermCount)
        if (coverage != otherCoverage) return coverage.compareTo(otherCoverage)
        if (entityPriority != other.entityPriority) {
            return entityPriority.compareTo(other.entityPriority)
        }
        if (baseCurrencyValue != other.baseCurrencyValue) {
            return baseCurrencyValue.compareTo(other.baseCurrencyValue)
        }
        if (trustTier != other.trustTier) {
            return trustTier.ordinal.compareTo(other.trustTier.ordinal)
        }
        if (matchKind != other.matchKind) return matchKind.weight.compareTo(other.matchKind.weight)
        if (fieldPriority != other.fieldPriority) {
            return fieldPriority.compareTo(other.fieldPriority)
        }
        return popularityValue.compareTo(other.popularityValue)
    }
}

data class UniversalSearchHit(
    val document: SearchDocument,
    val match: SearchMatch,
    val rank: SearchRankKey
)

data class UniversalSearchRankingPolicy(
    val matching: UniversalSearchMatchingPolicy = UniversalSearchMatchingPolicy.DEFAULT,
    val rankedSignalCap: Int = 100
) {
    companion object {
        val DEFAULT = UniversalSearchRankingPolicy()
    }
}

/**
 * Scores every document against a query and returns the hits in a single ranked order, so the
 * caller can take the first as the best match rather than choosing a category up front.
 */
class UniversalSearchEngine(
    private val policy: UniversalSearchRankingPolicy = UniversalSearchRankingPolicy.DEFAULT
) {
    private val matcher = UniversalSearchMatcher(policy.matching)

    fun search(
        query: UniversalSearchQuery,
        documents: List<IndexedSearchDocument>
    ): List<UniversalSearchHit> {
        if (query.isEmpty) return emptyList()

        val bestHitById = LinkedHashMap<String, UniversalSearchHit>()
        for (entry in documents) {
            val match = matcher.match(entry, query) ?: continue
            val hit = makeHit(entry.document, match)
            val previous = bestHitById[entry.document.id]
            if (previous == null || outranks(hit, previous)) {
                bestHitById[entry.document.id] = hit
            }
        }

        return bestHitById.values.sortedWith { left, right ->
            if (outranks(left, right)) {
                -1
            } else if (outranks(right, left)) {
                1
            } else {
                0
            }
        }
    }

    private fun outranks(lhs: UniversalSearchHit, rhs: UniversalSearchHit): Boolean {
        val comparison = lhs.rank.compareTo(rhs.rank)
        if (comparison != 0) return comparison > 0
        return lhs.document.id < rhs.document.id
    }

    private fun makeHit(document: SearchDocument, match: SearchMatch): UniversalSearchHit {
        val rank = SearchRankKey(
            relevanceBand = relevanceBand(match),
            matchKind = match.kind,
            matchedTermCount = match.matchedTermCount,
            totalTermCount = match.totalTermCount,
            fieldPriority = match.fieldKind.rankingPriority,
            entityPriority = entityPriority(document),
            trustTier = trustTier(document),
            baseCurrencyValue = document.signals.baseCurrencyValue
                ?.takeIf { it.isFinite() && it >= 0 } ?: 0.0,
            popularityValue = rankedValue(document.signals.popularityRank)
        )
        return UniversalSearchHit(document = document, match = match, rank = rank)
    }

    /**
     * Keyword and description hits stay weak however strongly they matched: they describe an entity
     * rather than name it.
     */
    private fun relevanceBand(match: SearchMatch): SearchRelevanceBand {
        if (match.kind == SearchMatchKind.EXACT_IDENTIFIER) {
            return SearchRelevanceBand.EXACT_IDENTIFIER
        }
        if (match.fieldKind == SearchFieldKind.KEYWORD ||
            match.fieldKind == SearchFieldKind.DESCRIPTION
        ) {
            return SearchRelevanceBand.WEAK
        }
        return when (match.kind) {
            SearchMatchKind.EXACT_PHRASE,
            SearchMatchKind.PHRASE_PREFIX -> SearchRelevanceBand.PHRASE

            SearchMatchKind.EXACT_WORD, SearchMatchKind.WORD_PREFIX -> SearchRelevanceBand.TERM

            SearchMatchKind.SUBSTRING, SearchMatchKind.FUZZY -> SearchRelevanceBand.WEAK

            SearchMatchKind.EXACT_IDENTIFIER -> SearchRelevanceBand.EXACT_IDENTIFIER
        }
    }

    private fun entityPriority(document: SearchDocument): Int {
        val traits = document.signals.traits
        return when (document.kind) {
            SearchEntityKind.WALLET -> when {
                SearchTrait.EXTERNAL in traits -> 1600
                SearchTrait.VIEW_ONLY in traits -> 900
                else -> 1000
            }

            SearchEntityKind.APPLICATION ->
                if (SearchTrait.CONNECTED in traits) 1500 else 500

            SearchEntityKind.TOKEN -> when {
                SearchTrait.POPULAR in traits -> 1450
                SearchTrait.HELD in traits -> 1400
                SearchTrait.TRACKED in traits -> 1300
                else -> 450
            }

            SearchEntityKind.COLLECTIBLE -> 1200

            SearchEntityKind.COLLECTION -> 1100

            SearchEntityKind.ACTION -> 800

            SearchEntityKind.SETTING -> 700

            SearchEntityKind.SITE ->
                if (SearchTrait.FROM_HISTORY in traits) 400 else 300
        }
    }

    private fun trustTier(document: SearchDocument): SearchTrustTier {
        val traits = document.signals.traits
        return when {
            SearchTrait.VERIFIED in traits -> SearchTrustTier.VERIFIED

            SearchTrait.CURATED in traits ||
                SearchTrait.POPULAR in traits -> SearchTrustTier.CURATED

            SearchTrait.HAS_MARKET_DATA in traits -> SearchTrustTier.ESTABLISHED

            else -> SearchTrustTier.UNKNOWN
        }
    }

    /** Turns an ordered feed position into a bounded score. */
    private fun rankedValue(rank: Int?): Double {
        if (rank == null || rank <= 0 || rank > policy.rankedSignalCap) return 0.0
        return (policy.rankedSignalCap - rank + 1).toDouble() / policy.rankedSignalCap.toDouble()
    }
}
