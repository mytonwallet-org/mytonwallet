package org.mytonwallet.app_air.walletcontext.installationStorage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class TechnicalPlayOutcomeTest {
    private val installedAt = 1_760_000_000_000L
    private val edge = installedAt + PLAY_REFERRER_TTL_MS
    private val now = installedAt + PLAY_REFERRER_TTL_MS / 2
    private val organic = SourceSnapshot("", "direct", "organic")
    private val referral = SourceSnapshot("", "referral", "referral")

    private fun createAnswer(
        source: SourceSnapshot,
        playInstalledAt: Long? = installedAt,
        collectedAt: Long? = installedAt + 60_000L,
        packageInstalledAt: Long? = installedAt
    ) = PlaySnapshot(packageInstalledAt, playInstalledAt, "1.0", "ok", source, collectedAt)

    private fun createFailure(status: String) = PlaySnapshot(installedAt, null, "", status, null)

    @Test
    fun freshPlayAnswersReportTheirOwnOutcome() {
        listOf("organic", "empty_referrer", "missing_source", "invalid_source").forEach {
            val answer = createAnswer(SourceSnapshot("", "direct", it))
            assertEquals(it, resolveTechnicalPlayOutcome(answer, true, now))
        }
        assertEquals("referral", resolveTechnicalPlayOutcome(createAnswer(referral), true, now))
    }

    @Test
    fun explicitAnswersAndUnsettledCollectionsMakeNoTechnicalClaim() {
        val utm = SourceSnapshot("partner", "utm", "utm")
        val domain = SourceSnapshot("", "referrer", "external_referrer", "partner.example")
        assertNull(resolveTechnicalPlayOutcome(createAnswer(utm), false, now))
        assertNull(resolveTechnicalPlayOutcome(createAnswer(domain), false, now))
        listOf(
            "pending",
            "service_unavailable",
            "service_disconnected",
            "connection_exception",
            "read_exception"
        ).forEach {
            assertNull(resolveTechnicalPlayOutcome(createFailure(it), true, now))
            assertNull(resolveTechnicalPlayOutcome(createFailure(it), false, now))
        }
    }

    @Test
    fun finalCollectionFailuresReportPlayUnavailableAtAnyAge() {
        listOf("feature_not_supported", "developer_error", "unexpected_response").forEach {
            assertEquals(
                "play_unavailable",
                resolveTechnicalPlayOutcome(createFailure(it), true, now)
            )
            assertEquals(
                "play_unavailable",
                resolveTechnicalPlayOutcome(createFailure(it), null, edge * 2)
            )
        }
    }

    @Test
    fun nonPlayInstallerOverridesEveryTechnicalOutcome() {
        assertEquals(
            "not_play_install",
            resolveTechnicalPlayOutcome(createAnswer(organic), false, now)
        )
        assertEquals(
            "not_play_install",
            resolveTechnicalPlayOutcome(createAnswer(referral), false, now)
        )
        val unavailable = createFailure("developer_error")
        assertEquals("not_play_install", resolveTechnicalPlayOutcome(unavailable, false, now))
        assertEquals("organic", resolveTechnicalPlayOutcome(createAnswer(organic), null, now))
    }

    @Test
    fun answerCollectedAfterTheReferrerWindowIsStale() {
        val atEdge = createAnswer(organic, collectedAt = edge)
        assertEquals("organic", resolveTechnicalPlayOutcome(atEdge, true, now))
        val late = createAnswer(organic, collectedAt = edge + 1)
        assertEquals("stale_referrer", resolveTechnicalPlayOutcome(late, true, now))
        val lateReferral = createAnswer(referral, collectedAt = edge + 1)
        assertEquals("stale_referrer", resolveTechnicalPlayOutcome(lateReferral, true, now))
    }

    @Test
    fun missingStampsFallBackToReadTimeAndPackageInstallTime() {
        val unstamped = createAnswer(organic, collectedAt = null)
        assertEquals("organic", resolveTechnicalPlayOutcome(unstamped, true, now))
        assertEquals("stale_referrer", resolveTechnicalPlayOutcome(unstamped, true, edge + 1))
        val packageOnly = createAnswer(organic, playInstalledAt = null, collectedAt = edge + 1)
        assertEquals("stale_referrer", resolveTechnicalPlayOutcome(packageOnly, true, now))
        val undated = createAnswer(organic, null, edge + 1, null)
        assertEquals("organic", resolveTechnicalPlayOutcome(undated, true, edge + 1))
    }

    @Test
    fun onlySuccessfulAnswersCarryCollectionTime() {
        assertThrows(IllegalArgumentException::class.java) {
            PlaySnapshot(installedAt, null, "", "developer_error", null, installedAt)
        }
    }
}
