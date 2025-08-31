package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class MApiLocalTransactionParams(
    // Optional fields that may be included
    @Json(name = "txId") val txId: String? = null,
    @Json(name = "normalizedAddress") val normalizedAddress: String? = null,

    // Required fields from ApiTransaction
    @Json(name = "amount") val amount: BigInteger,
    @Json(name = "fee") val fee: BigInteger,
    @Json(name = "fromAddress") val fromAddress: String,
    @Json(name = "toAddress") val toAddress: String,
    @Json(name = "slug") val slug: String,
    @Json(name = "blockchain") val blockchain: String? = null,

    // Optional fields from ApiTransaction
    @Json(name = "comment") val comment: String? = null,
    @Json(name = "encryptedComment") val encryptedComment: String? = null,
    @Json(name = "externalMsgHashNorm") val externalMsgHashNorm: String? = null,
    @Json(name = "shouldHide") val shouldHide: Boolean? = null,
    @Json(name = "type") val type: ApiTransactionType? = null,
    //@Json(name = "metadata") val metadata: ApiTransactionMetadata? = null,
    @Json(name = "nft") val nft: ApiNft? = null,
    @Json(name = "tokenSlug") val tokenSlug: String? = null,

    // From BaseActivity
    @Json(name = "status") val status: String? = null
)
