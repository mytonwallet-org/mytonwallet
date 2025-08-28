package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.JsonSealed
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.JsonSealedSubtype
import java.math.BigInteger

@JsonSealed("type")
sealed class ApiParsedPayload {

    @JsonSealedSubtype("comment")
    @JsonClass(generateAdapter = true)
    data class ApiCommentPayload(
        val comment: String?,
        val text: String?
    ) : ApiParsedPayload()

    @JsonSealedSubtype("encrypted-comment")
    @JsonClass(generateAdapter = true)
    data class ApiEncryptedCommentPayload(
        val encryptedComment: String
    ) : ApiParsedPayload()

    @JsonSealedSubtype("nft:transfer")
    @JsonClass(generateAdapter = true)
    data class ApiNftTransferPayload(
        val queryId: BigInteger,
        val newOwner: String,
        val responseDestination: String,
        val customPayload: String? = null,
        val forwardAmount: BigInteger,
        val forwardPayload: String? = null,
        val nftAddress: String,
        val nftName: String? = null,
        val nft: ApiNft? = null,
        val comment: String? = null
    ) : ApiParsedPayload()

    @JsonSealedSubtype("nft:ownership-assigned")
    @JsonClass(generateAdapter = true)
    data class ApiNftOwnershipAssignedPayload(
        val queryId: BigInteger,
        val prevOwner: String,
        val nftAddress: String,
        val nft: ApiNft? = null,
        val comment: String? = null
    ) : ApiParsedPayload()

    @JsonSealedSubtype("tokens:transfer")
    @JsonClass(generateAdapter = true)
    data class ApiTokensTransferPayload(
        val queryId: BigInteger,
        val amount: BigInteger,
        val destination: String,
        val responseDestination: String,
        val customPayload: String? = null,
        val forwardAmount: BigInteger,
        val forwardPayload: String? = null,
        val slug: String
    ) : ApiParsedPayload()

    @JsonSealedSubtype("tokens:transfer-non-standard")
    @JsonClass(generateAdapter = true)
    data class ApiTokensTransferNonStandardPayload(
        val queryId: BigInteger,
        val amount: BigInteger,
        val destination: String,
        val slug: String
    ) : ApiParsedPayload()

    @JsonSealedSubtype("unknown")
    @JsonClass(generateAdapter = true)
    data class ApiUnknownPayload(
        val base64: String
    ) : ApiParsedPayload()

    @JsonSealedSubtype("tokens:burn")
    @JsonClass(generateAdapter = true)
    data class ApiTokensBurnPayload(
        val queryId: BigInteger,
        val amount: BigInteger,
        val address: String,
        val customPayload: String? = null,
        val slug: String,
        val isLiquidUnstakeRequest: Boolean
    ) : ApiParsedPayload()

    @JsonSealedSubtype("liquid-staking:deposit")
    @JsonClass(generateAdapter = true)
    data class ApiLiquidStakingDepositPayload(
        val queryId: BigInteger,
        val appId: BigInteger? = null
    ) : ApiParsedPayload()

    @JsonSealedSubtype("liquid-staking:withdrawal-nft")
    @JsonClass(generateAdapter = true)
    data class ApiLiquidStakingWithdrawalNftPayload(
        val queryId: BigInteger
    ) : ApiParsedPayload()

    @JsonSealedSubtype("liquid-staking:withdrawal")
    @JsonClass(generateAdapter = true)
    data class ApiLiquidStakingWithdrawalPayload(
        val queryId: BigInteger
    ) : ApiParsedPayload()

    @JsonSealedSubtype("token-bridge:pay-swap")
    @JsonClass(generateAdapter = true)
    data class ApiTokenBridgePaySwap(
        val queryId: BigInteger,
        val swapId: String
    ) : ApiParsedPayload()

    @JsonSealedSubtype("dns:change-record")
    @JsonClass(generateAdapter = true)
    data class ApiDnsChangeRecord(
        val queryId: BigInteger,
        val record: Record,
        val domain: String
    ) : ApiParsedPayload() {
        @JsonClass(generateAdapter = true)
        data class Record(
            val type: DnsCategory? = null,
            val flags: Int? = null,
            val value: String? = null,
            val key: String? = null,
        )
    }

    @JsonSealedSubtype("vesting:add-whitelist")
    @JsonClass(generateAdapter = true)
    data class ApiVestingAddWhitelistPayload(
        val queryId: BigInteger,
        val address: String
    ) : ApiParsedPayload()

    @JsonSealedSubtype("single-nominator:withdraw")
    @JsonClass(generateAdapter = true)
    data class ApiSingleNominatorWithdrawPayload(
        val queryId: BigInteger,
        val amount: BigInteger
    ) : ApiParsedPayload()

    @JsonSealedSubtype("single-nominator:change-validator")
    @JsonClass(generateAdapter = true)
    data class ApiSingleNominatorChangeValidatorPayload(
        val queryId: BigInteger,
        val address: String
    ) : ApiParsedPayload()

    @JsonSealedSubtype("liquid-staking:vote")
    @JsonClass(generateAdapter = true)
    data class ApiLiquidStakingVotePayload(
        val queryId: BigInteger,
        val votingAddress: String,
        val expirationDate: Long,
        val vote: Boolean,
        val needConfirmation: Boolean
    ) : ApiParsedPayload()


    val payloadIsToken
        get() = when (this) {
            is ApiTokensTransferPayload -> true
            is ApiTokensTransferNonStandardPayload -> true
            is ApiTokensBurnPayload -> true
            else -> false
        }
    val payloadTokenSlug: String?
        get() = when (this) {
            is ApiTokensTransferPayload -> this.slug
            is ApiTokensTransferNonStandardPayload -> this.slug
            is ApiTokensBurnPayload -> this.slug
            else -> null
        }
    val payloadTokenAmount: BigInteger?
        get() = when (this) {
            is ApiTokensTransferPayload -> this.amount
            is ApiTokensTransferNonStandardPayload -> this.amount
            is ApiTokensBurnPayload -> this.amount
            else -> null
        }

    val payloadIsNft
        get() = when (this) {
            is ApiNftTransferPayload -> true
            is ApiNftOwnershipAssignedPayload -> true
            else -> false
        }
    val payloadNft: ApiNft?
        get() = when (this) {
            is ApiNftTransferPayload -> this.nft
            is ApiNftOwnershipAssignedPayload -> this.nft
            else -> null
        }

    val payloadComment: String?
        get() = when (this) {
            is ApiCommentPayload -> this.comment
            is ApiNftTransferPayload -> this.comment
            is ApiNftOwnershipAssignedPayload -> this.comment
            else -> null
        }
}

@JsonClass(generateAdapter = false)
enum class DnsCategory {
    @Json(name = "dns_next_resolver")
    DNS_NEXT_RESOLVER,

    @Json(name = "wallet")
    WALLET,

    @Json(name = "site")
    SITE,

    @Json(name = "storage")
    STORAGE
}
