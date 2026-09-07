package org.mytonwallet.app_air.walletcore

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
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
            InstallAttribution(
                "partner",
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
            InstallAttribution("unknown", isTechnical = true),
            sanitizeInstallAttribution("attribution_referrer=1.2.3.4")
        )
        assertEquals(
            InstallAttribution("unknown", isTechnical = true),
            sanitizeInstallAttribution("attribution_referrer=news.123abc")
        )
        assertEquals(
            InstallAttribution("", "news.xn--p1ai"),
            sanitizeInstallAttribution("attribution_referrer=news.xn--p1ai")
        )
    }

    @Test
    fun domainFallbackKeepsProvenanceAndUtmWins() {
        assertEquals(
            InstallAttribution("", "news.example"),
            sanitizeInstallAttribution("attribution_referrer=news.example")
        )
        assertEquals(
            InstallAttribution("unknown"),
            sanitizeInstallAttribution("attribution_referrer=news.example&utm_source=unknown")
        )
        assertEquals(
            InstallAttribution("wc"),
            sanitizeInstallAttribution("attribution_referrer=news.example&utm_source=wc")
        )
        assertEquals(
            InstallAttribution("unknown", isTechnical = true),
            sanitizeInstallAttribution("attribution_referrer=get.mywallet.io")
        )
        assertEquals(
            InstallAttribution("unknown", isTechnical = true),
            sanitizeInstallAttribution("attribution_referrer=news.example%2Fsecret")
        )
    }

    @Test
    fun extractsAllowlistedUtmSource() {
        assertEquals("wc", sanitizeReferrer("utm_source=wc&utm_medium=cpc"))
    }

    @Test
    fun bareUtmSourceResolvesToSlug() {
        assertEquals("wc", sanitizeReferrer("utm_source=wc"))
    }

    @Test
    fun googlePlayOrganicMarkerResolvesToOrganic() {
        assertEquals(
            "organic",
            sanitizeReferrer("utm_source=google-play&utm_medium=organic")
        )
    }

    @Test
    fun emptyReferrerResolvesToUnknown() {
        assertEquals("unknown", sanitizeReferrer(""))
    }

    @Test
    fun nullReferrerResolvesToUnknown() {
        assertEquals("unknown", sanitizeReferrer(null))
    }

    @Test
    fun rejectsInjectionPayload() {
        assertEquals("unknown", sanitizeReferrer("utm_source=%22)%3Bevil%2F%2F"))
    }

    @Test
    fun rejectsOverlongAndMissing() {
        assertEquals("unknown", sanitizeReferrer("utm_source=" + "a".repeat(65)))
        assertEquals("unknown", sanitizeReferrer("gclid=abc"))
    }

    @Test
    fun rejectsNonCanonicalSlugUtmSource() {
        // "google-play" alone (no organic utm_medium) passes input-safety (hyphen is
        // allowed there) but fails the stricter canonical slug guard.
        assertEquals("unknown", sanitizeReferrer("utm_source=google-play"))
    }

    @Test
    fun technicalReferralRequiresMarker() {
        assertEquals(
            InstallAttribution("referral", isTechnical = true, technicalKind = "referral"),
            sanitizeInstallAttribution("utm_source=referral&attribution_kind=referral")
        )
        assertEquals(
            InstallAttribution("referral"),
            sanitizeInstallAttribution("utm_source=referral")
        )
        assertEquals(
            InstallAttribution("partner"),
            sanitizeInstallAttribution("utm_source=partner&utm_campaign=%0Alaunch")
        )
    }

    @Test
    fun normalizeTechnicalMarkerComparisonsWithoutChangingExplicitDetails() {
        assertEquals(
            InstallAttribution("referral", isTechnical = true, technicalKind = "referral"),
            sanitizeInstallAttribution("utm_source=REFERRAL&attribution_kind=%20Referral%20")
        )
        assertEquals(
            InstallAttribution("organic", isTechnical = true),
            sanitizeInstallAttribution("utm_source=google-play&utm_medium=%20ORGANIC%20")
        )
        assertEquals(
            InstallAttribution("partner", utmMedium = "POST"),
            sanitizeInstallAttribution("utm_source=partner&utm_medium=%20POST%20")
        )
    }

    @Test
    fun admissionRequiresParsedPermittedEntryButNotAnAccount() {
        val entry = splitAttributionDeeplink("https://my.tt/market?utm_source=partner")
        assertEquals(null, entry.admittedAttribution(null, DeeplinkOpenSource.OS_EXTERNAL))
        assertEquals(
            InstallAttribution("partner"),
            entry.admittedAttribution(Deeplink.Market(null), DeeplinkOpenSource.OS_EXTERNAL)
        )
        val offramp = Deeplink.Offramp(null, null, null, null, null, null)
        assertEquals(null, entry.admittedAttribution(offramp, DeeplinkOpenSource.IN_APP_BROWSER))
        assertEquals(null, entry.admittedAttribution(offramp, DeeplinkOpenSource.QR_SCAN))
        assertEquals(
            InstallAttribution("partner"),
            entry.admittedAttribution(offramp, DeeplinkOpenSource.OS_EXTERNAL)
        )
        assertEquals(
            InstallAttribution("partner"),
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
    fun coldSourceSurvivesRestartAndOlderAckCannotEraseUpgrade() {
        var disk: InstallAttribution? = null
        var ready = false
        val sent = mutableListOf<InstallAttribution>()
        val completions = mutableListOf<(Boolean) -> Unit>()
        fun journal() = PendingInstallAttribution(
            read = { disk },
            write = {
                disk = it
                true
            },
            ready = { ready },
            send = { snapshot, complete ->
                sent.add(snapshot)
                completions.add(complete)
            }
        )
        val inferred = InstallAttribution("", "news.example")
        val explicit = InstallAttribution("partner", utmCampaign = "launch")
        journal().capture(inferred)
        assertEquals(inferred, disk)
        assertEquals(0, sent.size)
        val restored = journal()
        ready = true
        restored.bridgeReady()
        restored.capture(explicit)
        completions[0](true)
        assertEquals(listOf(inferred, explicit), sent)
        assertEquals(explicit, disk)
        completions[1](false)
        assertEquals(explicit, disk)
        restored.bridgeReady()
        completions[2](true)
        assertEquals(null, disk)
    }

    @Test
    fun newBridgeDoesNotWaitForOrTrustOldPendingCall() {
        var disk: InstallAttribution? = null
        val completions = mutableListOf<(Boolean) -> Unit>()
        val journal = PendingInstallAttribution(
            read = { disk },
            write = {
                disk = it
                true
            },
            ready = { true },
            send = { _, complete -> completions.add(complete) }
        )
        journal.capture(InstallAttribution("partner"))
        journal.bridgeReady()
        completions[0](true)
        assertEquals(InstallAttribution("partner"), disk)
        completions[1](true)
        assertEquals(null, disk)
    }

    @Test
    fun failedJournalWritesDoNotPretendDurabilityOrDiscardPending() {
        var disk: InstallAttribution? = null
        var canWrite = false
        val completions = mutableListOf<(Boolean) -> Unit>()
        val journal = PendingInstallAttribution(
            read = { disk },
            write = {
                if (canWrite) disk = it
                canWrite
            },
            ready = { true },
            send = { _, complete -> completions.add(complete) }
        )
        val explicit = InstallAttribution("partner")
        journal.capture(explicit)
        assertEquals(null, journal.pending)
        assertEquals(0, completions.size)
        canWrite = true
        journal.capture(explicit)
        canWrite = false
        completions[0](true)
        assertEquals(explicit, disk)
        assertEquals(explicit, journal.pending)
        canWrite = true
        journal.bridgeReady()
        completions[1](true)
        assertEquals(null, disk)
    }

    @Test
    fun encodedMarketingKeysUseTheSameParsingForCaptureAndRemoval() {
        val query = "utm%5Fsource=partner&utm%5Fcampaign=launch&amount=1&text=a%26b"
        val expected = InstallAttribution("partner", utmCampaign = "launch")
        assertEquals(expected, sanitizeInstallAttribution(query))
        val split = splitAttributionDeeplink("https://my.tt/send?$query")
        assertEquals(expected, split.attribution)
        assertEquals("https://my.tt/send?amount=1&text=a%26b", split.url)
    }
}
