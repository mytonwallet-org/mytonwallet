package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Moshi
import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ApiPromotionContractTest {
    private val adapter = Moshi.Builder().build().adapter(ApiPromotion::class.java)

    @Test
    fun decodesInfoBannerWithoutCardOverlay() {
        val promotion = checkNotNull(
            adapter.fromJson(
                """{"id":"restake","kind":"infoBanner","infoBanner":{"title":"More profitable staking available","description":"Tap **Earn** for higher returns.","actionButton":{"title":"Restake Now","onClickAction":"openEarn"}}}"""
            )
        )
        assertEquals("restake", promotion.id)
        assertNull(promotion.cardOverlay)
        assertEquals("Tap **Earn** for higher returns.", promotion.infoBanner?.description)
        assertEquals("openEarn", promotion.infoBanner?.actionButton?.onClickAction)
    }

    @Test
    fun encodesForeignUnstakeDraftExactlyAsTheSdkReturnedIt() {
        val adapter = MoshiBuilder.build().adapter(ApiForeignUnstakeDraft::class.java)
        val json =
            """{"amountNative":"bigint:100000000000","transfers":[{"toAddress":"provider-wallet","amount":"bigint:50000000","payload":"raw-payload"},{"toAddress":"other-wallet","amount":"bigint:1"}],"fee":"bigint:51000000","realFee":"bigint:1000000","isInstant":true}"""
        val draft = checkNotNull(adapter.fromJson(json))
        assertEquals(BigInteger("50000000"), draft.transfers.first().amount)
        assertEquals(json, adapter.toJson(draft))
    }

    @Test
    fun retainsCardOverlayDecoding() {
        val promotion = checkNotNull(
            adapter.fromJson(
                """{"id":"card","kind":"cardOverlay","cardOverlay":{"onClickAction":"openMintCardModal"}}"""
            )
        )
        assertEquals("openMintCardModal", promotion.cardOverlay?.onClickAction)
        assertNull(promotion.infoBanner)
    }
}
