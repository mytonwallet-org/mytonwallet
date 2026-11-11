package org.mytonwallet.app_air.walletcore

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.installationStorage.SourceSnapshot
import org.mytonwallet.app_air.walletcore.deeplink.Deeplink

class ReferrerSanitizerTest {
    @Test
    fun preservesTheWholeExplicitBundleAndBusinessQuery() {
        val split =
            splitAttributionDeeplink(
                "https://my.tt/send/ton:address?amount=1&r=business&utm_source=partner&utm_campaign=launch&utm_medium=post&utm_content=a"
            )
        assertEquals("https://my.tt/send/ton:address?amount=1&r=business", split.url)
        assertEquals(
            SourceSnapshot(
                "partner",
                "utm",
                "utm",
                utmMedium = "post",
                utmCampaign = "launch",
                utmContent = "a"
            ),
            split.attribution
        )
        assertEquals(
            null,
            splitAttributionDeeplink("https://evil.example/?utm_source=partner").attribution
        )
        assertEquals(
            true,
            splitAttributionDeeplink("https://my.tt/get/android?utm_source=partner").isGet
        )
    }

    @Test
    fun domainGrammarMatchesBackend() {
        assertEquals(
            SourceSnapshot("", "direct", "invalid_source"),
            sanitizeInstallAttribution("attribution_referrer=1.2.3.4")
        )
        assertEquals(
            SourceSnapshot("", "direct", "invalid_source"),
            sanitizeInstallAttribution("attribution_referrer=news.123abc")
        )
        assertEquals(
            SourceSnapshot("", "referrer", "external_referrer", "news.xn--p1ai"),
            sanitizeInstallAttribution("attribution_referrer=news.xn--p1ai")
        )
    }

    @Test
    fun domainFallbackKeepsProvenanceAndUtmWins() {
        assertEquals(
            SourceSnapshot("", "referrer", "external_referrer", "news.example"),
            sanitizeInstallAttribution("attribution_referrer=news.example")
        )
        assertEquals(
            SourceSnapshot("", "referrer", "external_referrer", "news.example"),
            sanitizeInstallAttribution(
                "attribution_referrer=news.example&attribution_referrer=get.mywallet.io"
            )
        )
        assertEquals(
            SourceSnapshot("unknown", "utm", "utm"),
            sanitizeInstallAttribution("attribution_referrer=news.example&utm_source=unknown")
        )
        assertEquals(
            SourceSnapshot("wc", "utm", "utm"),
            sanitizeInstallAttribution("attribution_referrer=news.example&utm_source=wc")
        )
        assertEquals(
            SourceSnapshot("", "direct", "invalid_source"),
            sanitizeInstallAttribution("attribution_referrer=get.mywallet.io")
        )
        assertEquals(
            SourceSnapshot("", "direct", "invalid_source"),
            sanitizeInstallAttribution("attribution_referrer=news.example%2Fsecret")
        )
    }

    @Test
    fun ownedGramDomainsAreNotReferrers() {
        for (domain in listOf("gramwallet.io", "get.gramwallet.io", "gramwallet.app")) {
            assertEquals(
                SourceSnapshot("", "direct", "invalid_source"),
                sanitizeInstallAttribution("attribution_referrer=$domain")
            )
        }
        assertEquals(
            SourceSnapshot("", "referrer", "external_referrer", "gramwallet.io.example"),
            sanitizeInstallAttribution("attribution_referrer=gramwallet.io.example")
        )
    }

    @Test
    fun extractsAllowlistedUtmSource() {
        assertEquals("wc", sanitizeInstallAttribution("utm_source=wc&utm_medium=cpc").channel)
    }

    @Test
    fun bareUtmSourceResolvesToSlug() {
        assertEquals("wc", sanitizeInstallAttribution("utm_source=wc").channel)
    }

    @Test
    fun technicalSourceOutcomesDoNotInventAttribution() {
        val cases = listOf(
            "utm_source=google-play&utm_medium=organic" to "organic",
            "" to "empty_referrer",
            null to "empty_referrer",
            "utm_source=%22)%3Bevil%2F%2F" to "invalid_source",
            "utm_source=" + "a".repeat(65) to "invalid_source",
            "gclid=abc" to "missing_source",
            "utm_source=google-play" to "invalid_source"
        )
        cases.forEach { (raw, outcome) ->
            assertEquals(SourceSnapshot("", "direct", outcome), sanitizeInstallAttribution(raw))
        }
    }

    @Test
    fun technicalReferralRequiresMarker() {
        assertEquals(
            SourceSnapshot("", "referral", "referral"),
            sanitizeInstallAttribution("utm_source=referral&attribution_kind=referral")
        )
        assertEquals(
            SourceSnapshot("referral", "utm", "utm"),
            sanitizeInstallAttribution("utm_source=referral")
        )
        assertEquals(
            SourceSnapshot("partner", "utm", "utm"),
            sanitizeInstallAttribution("utm_source=partner&utm_campaign=%0Alaunch")
        )
    }

    @Test
    fun normalizeTechnicalMarkerComparisonsWithoutChangingExplicitDetails() {
        assertEquals(
            SourceSnapshot("", "referral", "referral"),
            sanitizeInstallAttribution("utm_source=REFERRAL&attribution_kind=%20Referral%20")
        )
        assertEquals(
            SourceSnapshot("", "direct", "organic"),
            sanitizeInstallAttribution("utm_source=google-play&utm_medium=%20ORGANIC%20")
        )
        assertEquals(
            SourceSnapshot("partner", "utm", "utm", utmMedium = "POST"),
            sanitizeInstallAttribution("utm_source=partner&utm_medium=%20POST%20")
        )
    }

    @Test
    fun admissionRequiresParsedPermittedEntryButNotAnAccount() {
        val entry = splitAttributionDeeplink("https://my.tt/market?utm_source=partner")
        assertEquals(null, entry.admittedAttribution(null, DeeplinkOpenSource.OS_EXTERNAL))
        assertEquals(
            SourceSnapshot("partner", "utm", "utm"),
            entry.admittedAttribution(Deeplink.Market(null), DeeplinkOpenSource.OS_EXTERNAL)
        )
        val offramp = Deeplink.Offramp(null, null, null, null, null, null)
        assertEquals(null, entry.admittedAttribution(offramp, DeeplinkOpenSource.IN_APP_BROWSER))
        assertEquals(null, entry.admittedAttribution(offramp, DeeplinkOpenSource.QR_SCAN))
        assertEquals(
            SourceSnapshot("partner", "utm", "utm"),
            entry.admittedAttribution(offramp, DeeplinkOpenSource.OS_EXTERNAL)
        )
        assertEquals(
            SourceSnapshot("partner", "utm", "utm"),
            splitAttributionDeeplink("https://my.tt/get?utm_source=partner")
                .admittedAttribution(null, DeeplinkOpenSource.OS_EXTERNAL)
        )
        assertEquals(
            null,
            splitAttributionDeeplink("https://other.example/market?utm_source=partner")
                .admittedAttribution(Deeplink.Market(null), DeeplinkOpenSource.OS_EXTERNAL)
        )
    }

    @Test
    fun encodedMarketingKeysUseTheSameParsingForCaptureAndRemoval() {
        val query = "utm%5Fsource=partner&utm%5Fcampaign=launch&amount=1&text=a%26b"
        val expected = SourceSnapshot("partner", "utm", "utm", utmCampaign = "launch")
        assertEquals(expected, sanitizeInstallAttribution(query))
        val split = splitAttributionDeeplink("https://my.tt/send?$query")
        assertEquals(expected, split.attribution)
        assertEquals("https://my.tt/send?amount=1&text=a%26b", split.url)
    }
}
