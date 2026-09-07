package org.mytonwallet.app_air.uibrowser.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UniversalSearchEngineTest {
    private val engine = UniversalSearchEngine()
    private val matcher = UniversalSearchMatcher()

    private fun token(
        id: String,
        symbol: String,
        name: String,
        traits: Set<SearchTrait> = emptySet(),
        value: Double? = null
    ) = SearchDocument(
        id = id,
        kind = SearchEntityKind.TOKEN,
        fields = listOf(
            SearchField(symbol, SearchFieldKind.SYMBOL),
            SearchField(name, SearchFieldKind.TITLE)
        ),
        signals = SearchSignals(traits = traits, baseCurrencyValue = value)
    )

    private fun search(query: String, vararg documents: SearchDocument) =
        engine.search(UniversalSearchQuery(query), documents.map { IndexedSearchDocument(it) })

    @Test
    fun exactWordOutranksSubstring() {
        val hits = search(
            "ton",
            token("a", "TONCOIN", "Toncoin Wrapped"),
            token("b", "TON", "Toncoin")
        )
        assertEquals("b", hits.first().document.id)
    }

    @Test
    fun categoryIsOnlyTheFinalTiebreaker() {
        // A wallet that merely contains the term must not beat an exact token symbol, which is the
        // behavior the previous hardcoded wallet-before-token chain produced.
        val wallet = SearchDocument(
            id = "wallet",
            kind = SearchEntityKind.WALLET,
            fields = listOf(SearchField("my usdt savings", SearchFieldKind.TITLE))
        )
        val hits = search("usdt", wallet, token("token", "USDT", "Tether USD"))
        assertEquals("token", hits.first().document.id)
    }

    @Test
    fun heldBalanceBreaksTiesBetweenEqualMatches() {
        val hits = search(
            "tether",
            token("copycat", "TETHER", "Tether"),
            token("held", "TETHER", "Tether", traits = setOf(SearchTrait.HELD), value = 25.0)
        )
        assertEquals("held", hits.first().document.id)
    }

    @Test
    fun phrasePrefixMatchesMultiWordName() {
        val hits = search("usd c", token("usdc", "USDC", "USD Coin"))
        assertEquals(1, hits.size)
        assertEquals(SearchMatchKind.PHRASE_PREFIX, hits.first().match.kind)
    }

    @Test
    fun singleCharacterTypoStillMatches() {
        val match = matcher.match(
            token("usdt", "USDT", "Tether"),
            UniversalSearchQuery("teter")
        )
        assertNotNull(match)
        assertEquals(SearchMatchKind.FUZZY, match!!.kind)
    }

    @Test
    fun transposedCharactersExceedTheEditBudget() {
        // Plain Levenshtein counts a swap as two edits, so `tehter` stays unmatched. Recovering it
        // would need Damerau-Levenshtein, which iOS does not use either.
        assertNull(
            matcher.match(token("usdt", "USDT", "Tether"), UniversalSearchQuery("tehter"))
        )
    }

    @Test
    fun diacriticsAreIgnored() {
        assertNotNull(
            matcher.match(token("usdt", "USDT", "Tether"), UniversalSearchQuery("téther"))
        )
    }

    @Test
    fun keywordHitsStayWeakerThanNameHits() {
        val keyworded = SearchDocument(
            id = "keyworded",
            kind = SearchEntityKind.TOKEN,
            fields = listOf(SearchField("stable", SearchFieldKind.KEYWORD))
        )
        val hits = search("stable", keyworded, token("named", "STABLE", "Stable"))
        assertEquals("named", hits.first().document.id)
    }

    @Test
    fun longUnbrokenQueryOnlyMatchesIdentifierFields() {
        val address = "UQDuGgqZU7_AEgiOwEe-abozIefuoairTWLOyd7c_f8Gh27a"
        val wallet = SearchDocument(
            id = "wallet",
            kind = SearchEntityKind.WALLET,
            fields = listOf(SearchField(address, SearchFieldKind.ADDRESS))
        )
        val decoy = SearchDocument(
            id = "decoy",
            kind = SearchEntityKind.TOKEN,
            fields = listOf(SearchField(address, SearchFieldKind.DESCRIPTION))
        )
        val hits = search(address, wallet, decoy)
        assertEquals(1, hits.size)
        assertEquals("wallet", hits.first().document.id)
        assertEquals(SearchMatchKind.EXACT_IDENTIFIER, hits.first().match.kind)
    }

    @Test
    fun appTitlePrefixOutranksUnrelatedTokenSubstring() {
        // "bub" -> Bubblemaps. An app must be promotable, which the old wallet/site/token-only
        // sections could not represent.
        val app = SearchDocument(
            id = "dapp:bubblemaps",
            kind = SearchEntityKind.APPLICATION,
            fields = listOf(
                SearchField("Bubblemaps", SearchFieldKind.TITLE),
                SearchField("https://bubblemaps.io", SearchFieldKind.URL)
            )
        )
        val hits = search("bub", app, token("noise", "XBUBX", "Wrapped Xbubx"))
        assertEquals("dapp:bubblemaps", hits.first().document.id)
        assertEquals(SearchRelevanceBand.PHRASE, hits.first().rank.relevanceBand)
    }

    @Test
    fun collectibleCanWinPromotion() {
        val nft = SearchDocument(
            id = "nft:1",
            kind = SearchEntityKind.COLLECTIBLE,
            fields = listOf(SearchField("Rare Panda", SearchFieldKind.TITLE)),
            signals = SearchSignals(traits = setOf(SearchTrait.OWNED))
        )
        val hits = search("rare panda", nft, token("t", "PANDA", "Panda Token"))
        assertEquals("nft:1", hits.first().document.id)
    }

    private fun document(
        id: String,
        kind: SearchEntityKind,
        title: String,
        traits: Set<SearchTrait> = emptySet()
    ) = SearchDocument(
        id = id,
        kind = kind,
        fields = listOf(SearchField(title, SearchFieldKind.TITLE)),
        signals = SearchSignals(traits = traits)
    )

    @Test
    fun connectedAppOutranksHeldToken() {
        val hits = search(
            "tether",
            token("held", "TETHER", "Tether", traits = setOf(SearchTrait.HELD), value = 25.0),
            document(
                "dapp",
                SearchEntityKind.APPLICATION,
                "Tether",
                traits = setOf(SearchTrait.CONNECTED)
            )
        )
        assertEquals("dapp", hits.first().document.id)
    }

    @Test
    fun popularOutranksHeldOutranksTrackedToken() {
        val hits = search(
            "tether",
            token("tracked", "TETHER", "Tether", traits = setOf(SearchTrait.TRACKED)),
            token("held", "TETHER", "Tether", traits = setOf(SearchTrait.HELD), value = 25.0),
            token("popular", "TETHER", "Tether", traits = setOf(SearchTrait.POPULAR))
        )
        assertEquals(listOf("popular", "held", "tracked"), hits.map { it.document.id })
    }

    @Test
    fun heldPopularTokenOutranksUnheldPopularToken() {
        val hits = search(
            "tether",
            token("unheld", "TETHER", "Tether", traits = setOf(SearchTrait.POPULAR)),
            token(
                "held",
                "TETHER",
                "Tether",
                traits = setOf(SearchTrait.HELD, SearchTrait.POPULAR),
                value = 25.0
            )
        )
        assertEquals(listOf("held", "unheld"), hits.map { it.document.id })
    }

    @Test
    fun viewOnlyWalletTrailsOwnedWallet() {
        val hits = search(
            "main",
            document(
                "view",
                SearchEntityKind.WALLET,
                "Main",
                traits = setOf(SearchTrait.OWNED, SearchTrait.VIEW_ONLY)
            ),
            document("own", SearchEntityKind.WALLET, "Main", traits = setOf(SearchTrait.OWNED))
        )
        assertEquals(listOf("own", "view"), hits.map { it.document.id })
    }

    @Test
    fun actionOutranksSettingAndUnownedEntities() {
        val hits = search(
            "swap",
            token("obscure", "SWAP", "Swap"),
            document("dapp", SearchEntityKind.APPLICATION, "Swap"),
            document("settings", SearchEntityKind.SETTING, "Swap"),
            document("action", SearchEntityKind.ACTION, "Swap")
        )
        assertEquals(
            listOf("action", "settings", "dapp", "obscure"),
            hits.map { it.document.id }
        )
    }

    @Test
    fun popularAppOutranksNonPopularToken() {
        val hits = search(
            "fragment",
            token("obscure", "FRAGMENT", "Fragment"),
            document(
                "dapp",
                SearchEntityKind.APPLICATION,
                "Fragment",
                traits = setOf(SearchTrait.CURATED, SearchTrait.POPULAR)
            )
        )
        assertEquals(listOf("dapp", "obscure"), hits.map { it.document.id })
    }

    @Test
    fun emptyQueryReturnsNothing() {
        assertTrue(search("", token("a", "TON", "Toncoin")).isEmpty())
    }

    @Test
    fun rankingIsStableForIdenticalDocuments() {
        val first = search("ton", token("a", "TON", "Toncoin"), token("b", "TON", "Toncoin"))
        val second = search("ton", token("b", "TON", "Toncoin"), token("a", "TON", "Toncoin"))
        assertEquals(first.map { it.document.id }, second.map { it.document.id })
    }
}
