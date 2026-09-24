package org.mytonwallet.app_air.walletcore.stores

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mytonwallet.app_air.walletcore.MINT_CARD_ADDRESS
import org.mytonwallet.app_air.walletcore.MINT_CARD_REFUND_COMMENT
import org.mytonwallet.app_air.walletcore.MTW_CARDS_COLLECTION
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.ApiNftMetadata
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

class PendingCardMintsTest {
    private val card = ApiNft(
        chain = MBlockchain.ton,
        address = "minted-card",
        thumbnail = null,
        image = null,
        collectionAddress = MTW_CARDS_COLLECTION,
        isOnSale = false,
        metadata = ApiNftMetadata(fragmentUrl = "https://fragment.com")
    )

    @Test
    fun deliveryBelongsOnlyToTheSubmittingAccountAndIsConsumedOnce() {
        val pending = PendingCardMints()
        pending.recordSubmission("minting", 100_500)
        pending.recordSubmission("removed", 100_500)
        pending.remove("removed")
        val delivery = transaction(nft = card)

        assertNull(pending.consume("other", listOf(delivery)))
        assertNull(pending.consume("removed", listOf(delivery)))
        assertEquals(
            PendingCardMints.Resolution.Minted(card),
            pending.consume("minting", listOf(delivery))
        )
        assertNull(pending.consume("minting", listOf(delivery)))
    }

    @Test
    fun historicalPendingFailedLocalAndMarketplaceActivitiesCannotInstallCard() {
        val pending = PendingCardMints()
        pending.recordSubmission("minting", 100_500)
        val ignored = listOf(
            transaction(nft = card, timestamp = 99_000),
            transaction(nft = card, status = ApiTransactionStatus.PENDING),
            transaction(nft = card, status = ApiTransactionStatus.FAILED),
            transaction(nft = card, id = "delivery:local"),
            transaction(nft = card, isIncoming = false),
            transaction(nft = card, type = ApiTransactionType.NFT_TRADE),
            transaction(nft = card).copy(shouldHide = true),
            transaction(nft = card.copy(chain = MBlockchain.tron)),
            transaction(nft = card.copy(collectionAddress = "other")),
            transaction(nft = card, slug = "trx")
        )

        ignored.forEach { assertNull(pending.consume("minting", listOf(it))) }
        assertEquals(
            PendingCardMints.Resolution.Minted(card),
            pending.consume("minting", ignored + transaction(nft = card))
        )
    }

    @Test
    fun confirmedRefundClearsPendingMintButDeliveryWinsWhenBothArrive() {
        val pending = PendingCardMints()
        pending.recordSubmission("minting", 100_500)
        val refund = transaction(
            fromAddress = MINT_CARD_ADDRESS,
            comment = MINT_CARD_REFUND_COMMENT
        )

        assertNull(
            pending.consume(
                "minting",
                listOf(refund.copy(status = ApiTransactionStatus.PENDING))
            )
        )
        assertNull(pending.consume("minting", listOf(refund.copy(fromAddress = "other"))))
        assertEquals(
            PendingCardMints.Resolution.Minted(card),
            pending.consume("minting", listOf(refund, transaction(nft = card)))
        )

        pending.recordSubmission("minting", 100_500)
        assertEquals(
            PendingCardMints.Resolution.Refunded,
            pending.consume("minting", listOf(refund))
        )
        assertNull(pending.consume("minting", listOf(transaction(nft = card))))
    }

    private fun transaction(
        id: String = "delivery",
        nft: ApiNft? = null,
        timestamp: Long = 100_000,
        status: ApiTransactionStatus = ApiTransactionStatus.COMPLETED,
        fromAddress: String = "sender",
        comment: String? = null,
        isIncoming: Boolean = true,
        type: ApiTransactionType? = null,
        slug: String = "toncoin"
    ) = MApiTransaction.Transaction(
        id = id,
        externalMsgHashNorm = null,
        timestamp = timestamp,
        amount = BigInteger.ZERO,
        fromAddress = fromAddress,
        toAddress = "wallet",
        comment = comment,
        fee = BigInteger.ZERO,
        slug = slug,
        isIncoming = isIncoming,
        normalizedAddress = null,
        type = type,
        nft = nft,
        status = status
    )
}
