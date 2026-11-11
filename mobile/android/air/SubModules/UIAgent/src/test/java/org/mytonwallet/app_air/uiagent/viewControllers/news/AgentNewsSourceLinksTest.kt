package org.mytonwallet.app_air.uiagent.viewControllers.news

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem.Source
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard

class AgentNewsSourceLinksTest {
    private val dictionaryField =
        LocaleController::class.java.getDeclaredField("dictionary").apply { isAccessible = true }
    private var previousDictionary: Any? = null

    @Before
    fun setUpStrings() {
        previousDictionary = dictionaryField.get(null)
        dictionaryField.set(
            null,
            mapOf(
                "\$agent_news_source" to "Source: %sources%",
                "\$agent_news_sources" to "Sources: %sources%",
                "\$joining_comma" to "、"
            )
        )
    }

    @After
    fun restoreStrings() {
        dictionaryField.set(null, previousDictionary)
    }

    @Test
    fun rejectsWalletActionsAndUnsafeSourceUrls() {
        listOf(
            "mtw://transfer?address=UQ123&amount=100",
            "ton://transfer/UQ123?amount=100",
            "mtw://swap?from=TON&to=USDT",
            "javascript:transfer()",
            "https://user:password@news.example/story",
            "http://user:password@news.example/story",
            "http:///transfer?address=UQ123",
            "https://news.example\\@wallet.example/transfer"
        ).forEach { assertFalse(it, AgentNewsSourceLinks.isOpenable(it)) }

        assertTrue(AgentNewsSourceLinks.isOpenable("https://news.example/story"))
        assertTrue(AgentNewsSourceLinks.isOpenable("http://news.example/story"))
        assertTrue(AgentNewsSourceLinks.isOpenable("tg://resolve?domain=mypulse"))
    }

    @Test
    fun showsUpToThreeNamedDistinctSourcesInOrder() {
        val news = makeNews(
            sources = listOf(
                Source(name = "  Reuters ", url = "https://reuters.example/a"),
                Source(name = " ", url = "https://www.coindesk.example/b"),
                Source(name = null, url = "not a url"),
                Source(name = "REUTERS", url = "https://reuters.example/c"),
                Source(name = "Wallet", url = "mtw://transfer?address=UQ123"),
                Source(name = "Fourth", url = "https://fourth.example/d")
            ),
            source = "Stored"
        )

        assertEquals(
            listOf(
                AgentNewsSource("Reuters", "https://reuters.example/a"),
                AgentNewsSource("coindesk.example", "https://www.coindesk.example/b"),
                AgentNewsSource("Wallet", null)
            ),
            makeAgentNewsSources(news.sources, news.source)
        )
    }

    @Test
    fun linksOnlyOpenableSourcesInTheLocalizedLine() {
        assertNull(buildAgentNewsSourceLine(emptyList()))
        assertEquals(
            AgentNewsSourceLine("Source: Stored", emptyList()),
            buildAgentNewsSourceLine(listOf(AgentNewsSource("Stored", null)))
        )
        assertEquals(
            AgentNewsSourceLine(
                "Sources: A、Bb、C",
                listOf(
                    AgentNewsSourceLine.Link(9, 10, "https://a.example"),
                    AgentNewsSourceLine.Link(14, 15, "https://c.example")
                )
            ),
            buildAgentNewsSourceLine(
                listOf(
                    AgentNewsSource("A", "https://a.example"),
                    AgentNewsSource("Bb", null),
                    AgentNewsSource("C", "https://c.example")
                )
            )
        )
    }

    private fun makeNews(sources: List<Source>? = null, source: String? = null) =
        AgentV2ThreadNewsCard(
            eventId = 1,
            headline = "Headline",
            publishedAt = "2026-11-09T12:00:00Z",
            source = source,
            sources = sources
        )
}
