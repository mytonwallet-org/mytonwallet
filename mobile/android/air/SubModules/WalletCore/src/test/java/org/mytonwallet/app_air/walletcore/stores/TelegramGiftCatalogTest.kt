package org.mytonwallet.app_air.walletcore.stores

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.models.TelegramGiftCatalog
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

class TelegramGiftCatalogTest {
    private fun gift(index: Int, collection: String = "large") = ApiNft(
        chain = MBlockchain.ton, address = "gift-$index", thumbnail = null, image = null,
        collectionAddress = collection, collectionName = collection, isOnSale = false,
        isTelegramGift = true
    )

    @Test
    fun countsHaveNoThousandItemCutoff() {
        for (count in listOf(0, 1, 999, 1000, 1001, 2501)) {
            val catalog = TelegramGiftCatalog.from((0 until count).map { gift(it) }) { false }
            assertEquals(count, catalog.count)
            assertEquals(count, catalog.collections.firstOrNull()?.count ?: 0)
        }
    }

    @Test
    fun collectionIdentitySortingAndHiddenCountsDoNotDependOnNames() {
        val gifts = (0 until 1501).map { gift(it, "z") } +
            (1501 until 2501).map { gift(it, "a") }
        val catalog = TelegramGiftCatalog.from(gifts.map { it.copy(collectionName = "Same") }) {
            it.address == "gift-0"
        }
        assertEquals(2501, catalog.count)
        assertEquals(listOf("z", "a"), catalog.collections.map { it.collection.address })
        assertEquals(listOf(1501, 1000), catalog.collections.map { it.count })
        assertEquals(1, catalog.hiddenCount)
        assertEquals(1, catalog.collections.first().hiddenCount)
    }

    @Test
    fun duplicatesNonGiftsAndOtherChainsAreExcluded() {
        val first = gift(1)
        val catalog = TelegramGiftCatalog.from(listOf(
            first, first, gift(2).copy(isTelegramGift = false),
            gift(3).copy(chain = MBlockchain.ethereum), gift(4).copy(collectionAddress = null)
        )) { false }
        assertEquals(1, catalog.count)
    }

    @Test
    fun equalCountsHaveAStableOrderAndNamelessCollectionsRemainAccessible() {
        val gifts = listOf(gift(1, "z"), gift(2, "a")).map { it.copy(collectionName = null) }
        val first = TelegramGiftCatalog.from(gifts) { false }
        assertEquals(first, TelegramGiftCatalog.from(gifts.reversed()) { false })
        assertEquals(listOf("a", "z"), first.collections.map { it.collection.name })
    }

    @Test
    fun completelyHiddenCollectionsAreCountedWithoutBeingDisplayed() {
        val catalog = TelegramGiftCatalog.from(listOf(gift(1, "visible"), gift(2, "hidden"))) {
            it.collectionAddress == "hidden"
        }
        assertEquals(2, catalog.count)
        assertEquals(1, catalog.hiddenCount)
        assertEquals(listOf("visible"), catalog.visibleCollections.map { it.collection.address })
    }

    @Test
    fun labelsUseVisibleMetadataAndRemainStableAcrossPageOrder() {
        val gifts = listOf(
            gift(1).copy(collectionName = "  Z  "),
            gift(2).copy(collectionName = "A hidden metadata"),
            gift(3).copy(collectionName = "  ")
        )
        val first = TelegramGiftCatalog.from(gifts) { it.address == "gift-2" }
        assertEquals(first, TelegramGiftCatalog.from(gifts.reversed()) { it.address == "gift-2" })
        assertEquals("Z", first.collections.single().collection.name)
        assertEquals(3, first.count)
        assertEquals(1, first.hiddenCount)
    }
}
