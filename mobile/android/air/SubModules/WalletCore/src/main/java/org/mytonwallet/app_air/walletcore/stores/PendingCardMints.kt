package org.mytonwallet.app_air.walletcore.stores

import org.mytonwallet.app_air.walletcore.MINT_CARD_ADDRESS
import org.mytonwallet.app_air.walletcore.MINT_CARD_REFUND_COMMENT
import org.mytonwallet.app_air.walletcore.MTW_CARDS_COLLECTION
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

internal class PendingCardMints {
    sealed class Resolution {
        data class Minted(val nft: ApiNft) : Resolution()
        object Refunded : Resolution()
    }

    private val startedAtByAccountId = HashMap<String, Long>()

    fun recordSubmission(accountId: String, startedAt: Long) {
        startedAtByAccountId[accountId] = startedAt / 1_000 * 1_000
    }

    fun remove(accountId: String) {
        startedAtByAccountId.remove(accountId)
    }

    fun consume(accountId: String, activities: Collection<MApiTransaction>): Resolution? {
        val startedAt = startedAtByAccountId[accountId] ?: return null
        val transactions = activities.filterIsInstance<MApiTransaction.Transaction>().filter {
            !it.isLocal() &&
                (
                    it.status == ApiTransactionStatus.CONFIRMED ||
                        it.status == ApiTransactionStatus.COMPLETED
                    ) &&
                it.timestamp >= startedAt &&
                it.shouldHide != true &&
                it.isIncoming &&
                it.type != ApiTransactionType.NFT_TRADE &&
                (it.slug == TONCOIN_SLUG || it.slug.startsWith("ton-"))
        }
        val nft = transactions.mapNotNull { it.nft }.firstOrNull {
            it.chain == MBlockchain.ton && it.collectionAddress == MTW_CARDS_COLLECTION
        }
        if (nft != null) {
            remove(accountId)
            return Resolution.Minted(nft)
        }
        if (transactions.any {
                it.fromAddress == MINT_CARD_ADDRESS && it.comment == MINT_CARD_REFUND_COMMENT
            }
        ) {
            remove(accountId)
            return Resolution.Refunded
        }
        return null
    }
}
