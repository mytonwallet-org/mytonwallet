package org.mytonwallet.app_air.walletcore.helpers

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NftVisibilityTest {

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
