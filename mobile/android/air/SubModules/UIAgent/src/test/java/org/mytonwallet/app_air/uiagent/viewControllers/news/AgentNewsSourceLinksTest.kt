package org.mytonwallet.app_air.uiagent.viewControllers.news

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentNewsSourceLinksTest {
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
}
