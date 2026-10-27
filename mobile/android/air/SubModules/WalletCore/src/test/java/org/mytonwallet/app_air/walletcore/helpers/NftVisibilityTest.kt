package org.mytonwallet.app_air.walletcore.helpers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MoshiBuilder

class NftVisibilityTest {

    @Test
    fun providerSpamMetadataSurvivesSdkAndCacheBoundaries() {
        val adapter = MoshiBuilder.build().adapter(ApiNft::class.java)
        val legacyAddress = "0x000000000000888741B254d37e1b27128AfEAaBC/" +
            "5261405894391250505533265397778618870761357154713600"
        // Supply the legacy link so constructing the NFT does not call Android's Uri in this JVM test.
        val nft = adapter.fromJson(
            """{"chain":"base","address":"$legacyAddress","isOnSale":false,"isHidden":true,
                "thumbnail":null,"image":null,"metadata":{"fragmentUrl":""},
                "spamInfo":{"provider":"alchemy","isSpam":true,
                "classifications":["SpammyMetadata","FutureClassification"]}}"""
        )!!
        val cached = adapter.fromJson(adapter.toJson(nft))!!

        assertEquals(legacyAddress.lowercase(), cached.address)
        assertEquals("alchemy", cached.spamInfo?.provider)
        assertEquals(true, cached.spamInfo?.isSpam)
        assertEquals(
            listOf("SpammyMetadata", "FutureClassification"),
            cached.spamInfo?.classifications
        )
        assertEquals(true, cached.isHidden)
    }

    @Test
    fun manuallyHiddenNftStaysHiddenWhenWhitelisted() {
        assertTrue(
            shouldHideNft(
                isHiddenByUser = true,
                isWhitelisted = true,
                isHidden = false,
                isUnverified = false,
                areUnverifiedNftsHidden = true
            )
        )
    }

    @Test
    fun whitelistOverridesAutomaticVisibilityRules() {
        assertFalse(
            shouldHideNft(
                isHiddenByUser = false,
                isWhitelisted = true,
                isHidden = true,
                isUnverified = true,
                areUnverifiedNftsHidden = true
            )
        )
    }

    @Test
    fun unverifiedNftIsHiddenWhenSettingIsEnabled() {
        assertTrue(
            shouldHideNft(
                isHiddenByUser = false,
                isWhitelisted = false,
                isHidden = false,
                isUnverified = true,
                areUnverifiedNftsHidden = true
            )
        )
    }

    @Test
    fun unverifiedNftIsVisibleWhenSettingIsDisabled() {
        assertFalse(
            shouldHideNft(
                isHiddenByUser = false,
                isWhitelisted = false,
                isHidden = false,
                isUnverified = true,
                areUnverifiedNftsHidden = false
            )
        )
    }

    @Test
    fun unverifiedActivityIsHiddenOnlyForIncomingTransfers() {
        assertTrue(
            shouldHideNftActivity(
                isHiddenByUser = false,
                isWhitelisted = false,
                isHidden = false,
                isUnverified = true,
                areUnverifiedNftsHidden = true,
                isIncoming = true,
                isNftTrade = false
            )
        )
        assertFalse(
            shouldHideNftActivity(
                isHiddenByUser = false,
                isWhitelisted = false,
                isHidden = false,
                isUnverified = true,
                areUnverifiedNftsHidden = true,
                isIncoming = false,
                isNftTrade = false
            )
        )
    }

    @Test
    fun unverifiedNftTradeActivityRemainsVisible() {
        assertFalse(
            shouldHideNftActivity(
                isHiddenByUser = false,
                isWhitelisted = false,
                isHidden = false,
                isUnverified = true,
                areUnverifiedNftsHidden = true,
                isIncoming = true,
                isNftTrade = true
            )
        )
    }

    @Test
    fun backendHiddenActivityRemainsHiddenRegardlessOfDirection() {
        assertTrue(
            shouldHideNftActivity(
                isHiddenByUser = false,
                isWhitelisted = false,
                isHidden = true,
                isUnverified = false,
                areUnverifiedNftsHidden = false,
                isIncoming = false,
                isNftTrade = false
            )
        )
    }
}
