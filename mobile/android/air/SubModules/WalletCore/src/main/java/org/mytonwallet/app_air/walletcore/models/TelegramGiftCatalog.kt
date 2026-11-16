package org.mytonwallet.app_air.walletcore.models

import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

data class TelegramGiftCollection(
    val collection: MCollectionTabToShow,
    val count: Int,
    val hiddenCount: Int
)

data class TelegramGiftCatalog(
    val collections: List<TelegramGiftCollection> = emptyList()
) {
    val count: Int get() = collections.sumOf { it.count }
    val hiddenCount: Int get() = collections.sumOf { it.hiddenCount }
    val visibleCollections: List<TelegramGiftCollection> get() = collections.filter { it.hiddenCount < it.count }

    companion object {
        fun from(nfts: List<ApiNft>, isHidden: (ApiNft) -> Boolean): TelegramGiftCatalog {
            val gifts = nfts.filter {
                (it.chain == null || it.chain == MBlockchain.ton) &&
                    it.isTelegramGift == true && !it.collectionAddress.isNullOrBlank()
            }.distinctBy { it.address }
            val collections = gifts.groupBy { requireNotNull(it.collectionAddress) }
                .map { (address, items) ->
                    val visibleItems = items.filterNot(isHidden)
                    val name = visibleItems.mapNotNull { it.collectionName?.trim()?.takeIf(String::isNotEmpty) }
                        .minOrNull() ?: address
                    TelegramGiftCollection(
                        collection = MCollectionTabToShow(chain = "ton", address = address, name = name),
                        count = items.size,
                        hiddenCount = items.size - visibleItems.size
                    )
                }.sortedWith(
                    compareByDescending<TelegramGiftCollection> { it.count }
                        .thenBy { it.collection.name }
                        .thenBy { it.collection.address }
                )
            return TelegramGiftCatalog(collections)
        }
    }
}
