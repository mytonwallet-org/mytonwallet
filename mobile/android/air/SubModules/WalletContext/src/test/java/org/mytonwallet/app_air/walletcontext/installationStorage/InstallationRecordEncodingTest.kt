package org.mytonwallet.app_air.walletcontext.installationStorage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class InstallationRecordEncodingTest {
    // Bytes written before `collectedAt` existed: `AtomicJsonFile` rejects a document
    // that its adapter would re-encode differently
    private val legacyDocuments = listOf(
        listOf(
            """{"storageContract":2,"installationId":"8b0e2a8e-5c1f-4c6e-9d3a-2f6b7c8d9e0f",""",
            """"play":{"latest":{"packageInstalledAt":1760000000000,"playInstalledAt":null,""",
            """"installVersion":"","collectionStatus":"pending","source":null},""",
            """"pending":{"eventId":"1c2d3e4f-5a6b-4c7d-8e9f-0a1b2c3d4e5f","snapshot":""",
            """{"packageInstalledAt":1760000000000,"playInstalledAt":null,"installVersion":"",""",
            """"collectionStatus":"pending","source":null}}},"deeplink":null,""",
            """"walletAttribution":{"initialized":false,"source":null}}"""
        ),
        listOf(
            """{"storageContract":2,"installationId":"8b0e2a8e-5c1f-4c6e-9d3a-2f6b7c8d9e0f",""",
            """"play":{"latest":{"packageInstalledAt":1760000000000,""",
            """"playInstalledAt":1760000100000,"installVersion":"26.11.0",""",
            """"collectionStatus":"ok",""",
            """"source":{"channel":"","attributionKind":"referral","sourceOutcome":"referral",""",
            """"referrerDomain":null,"utmMedium":null,"utmCampaign":null,"utmContent":null}},""",
            """"pending":null},"deeplink":{"latest":{"packageInstalledAt":1760000000000,""",
            """"source":{"channel":"telegram","attributionKind":"utm","sourceOutcome":"utm",""",
            """"referrerDomain":null,"utmMedium":null,"utmCampaign":"c1","utmContent":null}},""",
            """"pending":null},"walletAttribution":{"initialized":true,"source":null}}"""
        ),
        listOf(
            """{"storageContract":2,"installationId":"8b0e2a8e-5c1f-4c6e-9d3a-2f6b7c8d9e0f",""",
            """"play":{"latest":{"packageInstalledAt":null,"playInstalledAt":null,""",
            """"installVersion":"","collectionStatus":"developer_error","source":null},""",
            """"pending":null},"deeplink":null,"walletAttribution":{"initialized":true,""",
            """"source":null}}"""
        )
    ).map { it.joinToString("") }

    private fun reencode(text: String) =
        installationRecordAdapter.toJson(installationRecordAdapter.fromJson(text))

    @Test
    fun documentsWrittenBeforeCollectedAtStayCanonical() {
        legacyDocuments.forEach { assertEquals(it, reencode(it)) }
    }

    @Test
    fun collectedAtIsWrittenOnlyWhenKnown() {
        val record = requireNotNull(installationRecordAdapter.fromJson(legacyDocuments[1]))
        val latest = record.play.latest.copy(collectedAt = 1_760_000_200_000L)
        val stamped = record.copy(play = record.play.copy(latest = latest))
        val text = installationRecordAdapter.toJson(stamped)

        assertTrue(text.contains(""""collectedAt":1760000200000}"""))
        assertEquals(stamped, installationRecordAdapter.fromJson(text))
        assertEquals(text, reencode(text))

        val explicitNull = legacyDocuments[0].replaceFirst(
            """"source":null}""",
            """"source":null,"collectedAt":null}"""
        )
        assertNotEquals(legacyDocuments[0], explicitNull)
        assertNotEquals(explicitNull, reencode(explicitNull))
    }
}
