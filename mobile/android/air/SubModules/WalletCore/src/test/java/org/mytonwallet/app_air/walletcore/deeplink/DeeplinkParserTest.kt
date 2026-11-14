package org.mytonwallet.app_air.walletcore.deeplink

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers

class DeeplinkParserTest {
    @Test
    fun buildsNewsShareLinksWithTheFeedLocale() {
        for ((locale, language) in listOf(
            "ru" to "ru",
            "en" to "en",
            "ru-RU" to "ru",
            "de" to "en"
        )) {
            val url = ExplorerHelpers.buildAgentNewsShareUrl(42, locale)
            assertEquals("https://my.tt/agent?news=42&lang=$language&utm_source=pulse_share", url)
        }
        assertEquals(
            "https://my.tt/agent?news=307&lang=en&utm_source=pulse_share",
            ExplorerHelpers.buildAgentNewsShareUrl(307, "en")
        )
    }

    @Test
    fun parsesAgentPushNewsAndDigestParametersAndFallsBackForInvalidValues() {
        val digestId = "ru:2026-11-08T18:00:00.000Z"
        assertEquals(
            Deeplink.Agent(null, newsEventId = 42),
            DeeplinkParser.parseAgentLink("42", null)
        )
        assertEquals(
            Deeplink.Agent(null, newsEventId = 307),
            DeeplinkParser.parseAgentLink("307", null)
        )
        assertEquals(
            Deeplink.Agent(null, digestId = digestId),
            DeeplinkParser.parseAgentLink(null, digestId)
        )
        for (news in listOf("", "abc", "-1", "0", "999999999999")) {
            assertEquals(Deeplink.Agent(null), DeeplinkParser.parseAgentLink(news, null))
        }
        for (digest in listOf("", " ", "x".repeat(65), "$digestId\n")) {
            assertEquals(Deeplink.Agent(null), DeeplinkParser.parseAgentLink(null, digest))
        }
        assertEquals(Deeplink.Agent(null), DeeplinkParser.parseAgentLink("42", digestId))
        assertEquals(Deeplink.Agent(null), DeeplinkParser.parseAgentLink(null, null))
    }

    @Test
    fun detectsWalletConnectSessionRequestIdentity() {
        assertTrue(
            DeeplinkParser.isWalletConnectSessionRequest(setOf("requestId", "sessionTopic"))
        )
        assertTrue(
            DeeplinkParser.isWalletConnectSessionRequest(setOf("topic", "wc_ev"))
        )
        assertTrue(
            DeeplinkParser.isWalletConnectSessionRequest(setOf("topic", "message"))
        )
    }

    @Test
    fun rejectsIncompleteWalletConnectSessionRequestIdentity() {
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("requestId")))
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("sessionTopic")))
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("topic")))
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("message")))
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("uri")))
    }

    @Test
    fun preservesReceiveChain() {
        assertEquals("tron", DeeplinkParser.receiveDeeplink("tron")?.chain)
        assertNull(DeeplinkParser.receiveDeeplink(""))
    }

    @Test
    fun recognizesMintCardCommands() {
        assertTrue(DeeplinkParser.mintCardDeeplink("nft-card") is Deeplink.MintCard)
        assertTrue(DeeplinkParser.mintCardDeeplink("mint") is Deeplink.MintCard)
        assertNull(DeeplinkParser.mintCardDeeplink("card"))
    }

    @Test
    fun parsesNotificationExtrasOnlyWhenAllowed() {
        val extras = mapOf("action" to "openUrl", "url" to "https://evil.example")

        assertNull(
            DeeplinkParser.parseLaunch(
                null,
                allowExtras = false,
                sdkInt = 30,
                getExtra = extras::get
            )
        )
        val deeplink =
            DeeplinkParser.parseLaunch(
                null,
                allowExtras = true,
                sdkInt = 30,
                getExtra = extras::get
            )
        assertEquals(
            "https://evil.example",
            (deeplink as? Deeplink.NotificationUrl)?.config?.url
        )
    }

    @Test
    fun injectsNotificationDappBridgeOnlyFromAndroid11() {
        val extras = mapOf("action" to "openUrl", "url" to "https://evil.example")
        fun config(sdkInt: Int) = (
            DeeplinkParser.parseLaunch(null, allowExtras = true, sdkInt, getExtra = extras::get)
                as Deeplink.NotificationUrl
            ).config

        assertFalse(config(24).injectDappConnect)
        assertFalse(config(29).injectDappConnect)
        assertTrue(config(30).injectDappConnect)
        assertTrue(config(36).injectDappConnect)
    }

    @Test
    fun parsesDataDeeplinkRegardlessOfExtrasTrust() {
        val dataDeeplink = Deeplink.Portfolio(accountAddress = null)
        val extras = mapOf("action" to "openUrl", "url" to "https://evil.example")

        for (allowExtras in listOf(false, true)) {
            assertEquals(
                dataDeeplink,
                DeeplinkParser.parseLaunch(
                    dataDeeplink,
                    allowExtras,
                    sdkInt = 30,
                    getExtra = extras::get
                )
            )
        }
    }

    @Test
    fun trustsOnlyOwnPackageReferrer() {
        val packageName = "org.mytonwallet.app"
        fun isOwn(referrer: String?) = LaunchSender.isOwnPackage({}, { referrer }, packageName)

        assertTrue(isOwn("android-app://$packageName"))
        assertFalse(isOwn("android-app://$packageName.evil"))
        assertFalse(isOwn("android-app://com.evil"))
        assertFalse(isOwn("https://$packageName"))
        assertFalse(isOwn(null))
    }

    @Test
    fun ignoresSenderSuppliedReferrerExtras() {
        val packageName = "org.mytonwallet.app"

        for (key in listOf(Intent.EXTRA_REFERRER, Intent.EXTRA_REFERRER_NAME)) {
            val extras = mutableMapOf(key to "android-app://$packageName")
            // Reads in the order of `Activity.getReferrer`: the extras, then the system's record
            val readReferrer = {
                extras[Intent.EXTRA_REFERRER]
                    ?: extras[Intent.EXTRA_REFERRER_NAME]
                    ?: "android-app://com.evil"
            }

            val isOwn = LaunchSender.isOwnPackage(
                removeExtra = { extras.remove(it) },
                readReferrer = readReferrer,
                packageName = packageName
            )

            assertFalse(key, isOwn)
        }
    }
}
