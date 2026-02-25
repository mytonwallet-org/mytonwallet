package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MToken
import java.math.BigDecimal

data class MApiSwapAsset(
    override val name: String? = null,
    override val symbol: String? = null,
    override val chain: String? = null,
    override val slug: String,
    override val decimals: Int,
    override val isPopular: Boolean? = null,
    val priceUsd: Double? = null,
    override val image: String? = null,
    override val tokenAddress: String? = null,
    override val keywords: List<String>? = null,
    val color: String? = null
) : IApiToken {

    companion object {
        fun from(token: MToken): MApiSwapAsset {
            return MApiSwapAsset(
                name = token.name,
                symbol = token.symbol,
                chain = token.chain,
                slug = token.slug,
                decimals = token.decimals,
                isPopular = token.isPopular,
                priceUsd = token.priceUsd,
                image = token.image,
                tokenAddress = token.tokenAddress,
                keywords = token.keywords
            )
        }
    }
}

@JsonClass(generateAdapter = true)
data class MApiSwapPairAsset(
    val symbol: String,
    val slug: String,
    val contract: String?,
    val isReverseProhibited: Boolean?
)

@JsonClass(generateAdapter = true)
data class MApiSwapEstimateVariant(
    val fromAmount: BigDecimal,
    val toAmount: BigDecimal,
    val toMinAmount: BigDecimal,
    val swapFee: BigDecimal,
    val networkFee: Double,
    val realNetworkFee: Double?,
    val impact: Double,
    val dexLabel: MApiSwapDexLabel?
)

@JsonClass(generateAdapter = true)
data class MApiSwapEstimateRequest(
    val from: String,
    val to: String,
    val slippage: Float,
    val fromAmount: BigDecimal?,
    val toAmount: BigDecimal?,
    val fromAddress: String,
    val shouldTryDiesel: Boolean,
    val walletVersion: MApiTonWalletVersion?,
    val isFromAmountMax: Boolean,
    val toncoinBalance: String
)

@JsonClass(generateAdapter = true)
data class MApiSwapEstimateResponse(
    val toAmount: BigDecimal,
    val fromAmount: BigDecimal,
    val toMinAmount: BigDecimal,
    val networkFee: Double,
    val realNetworkFee: Double?,
    val swapFee: BigDecimal,
    val swapFeePercent: Double,
    val ourFee: String?,
    val ourFeePercent: Double?,
    val impact: Double,
    val dexLabel: MApiSwapDexLabel?,
    val dieselStatus: MDieselStatus?,
    val dieselFee: String?,
    val from: String,
    val to: String,
    val slippage: Double,

    /// only in v2
    val other: List<MApiSwapEstimateVariant>?,
    // only in v3
    val routes: List<List<JSONObject>>?,

    val bestDexLabel: MApiSwapDexLabel? = null,
    val all: List<MApiSwapEstimateVariant>? = null
)

@JsonClass(generateAdapter = true)
data class MApiSwapBuildRequest(
    val toAmount: BigDecimal,
    val fromAmount: BigDecimal,
    val toMinAmount: BigDecimal,
    val networkFee: Double,
    val swapFee: BigDecimal,
    val dexLabel: String?,
    val from: String,
    val to: String,
    val slippage: Float,
    val fromAddress: String,
    val swapVersion: Int?,
    val ourFee: String?,
    val dieselFee: String?,
    val shouldTryDiesel: Boolean,
    val routes: List<List<JSONObject>>?
)

@JsonClass(generateAdapter = true)
data class MApiSwapBuildResponse(
    val id: String,
    val transfers: List<MApiSwapTransfer>
)

@JsonClass(generateAdapter = true)
data class MApiSwapCexEstimateRequest(
    val from: String,
    val fromAmount: BigDecimal,
    val to: String,
)

@JsonClass(generateAdapter = true)
data class MApiSwapCexEstimateResponse(
    val from: String? = null,
    val fromAmount: BigDecimal? = null,
    val to: String? = null,
    val toAmount: BigDecimal? = null,
    val swapFee: BigDecimal? = null,
    val fromMin: BigDecimal? = null,
    val fromMax: BigDecimal? = null,
    val errors: List<SwapEstimateError>? = null
) {
    @JsonClass(generateAdapter = true)
    data class SwapEstimateError(
        val msg: String,
    )

    enum class SwapErrorType {
        InvalidPair,
        NotEnoughLiquidity,
        TooSmallAmount,
    }

    val error: MBridgeError?
        get() {
            return errors?.firstOrNull()?.msg.let { msg ->
                when (SERVER_ERRORS_MAP[msg]) {
                    SwapErrorType.InvalidPair -> {
                        MBridgeError.PAIR_NOT_FOUND
                    }

                    SwapErrorType.NotEnoughLiquidity -> {
                        MBridgeError.INSUFFICIENT_LIQUIDITY
                    }

                    SwapErrorType.TooSmallAmount -> {
                        MBridgeError.TOO_SMALL_AMOUNT
                    }

                    null -> null
                }
            }
        }

    companion object {
        val SERVER_ERRORS_MAP = mapOf(
            "Insufficient liquidity" to SwapErrorType.NotEnoughLiquidity,
            "Tokens must be different" to SwapErrorType.InvalidPair,
            "Asset not found" to SwapErrorType.InvalidPair,
            "Pair not found" to SwapErrorType.InvalidPair,
            "Too small amount" to SwapErrorType.TooSmallAmount,
        )
    }
}

@JsonClass(generateAdapter = true)
data class MApiSwapCexCreateTransactionRequest(
    val from: String,
    val fromAmount: BigDecimal,
    val fromAddress: String,        // Always TON address
    val to: String,
    val toAddress: String,          // TON or other crypto address
    val payoutExtraId: String?,
    val swapFee: BigDecimal,        // from estimate request
    val networkFee: Double?         // only for sent TON
)

@JsonClass(generateAdapter = true)
data class MApiSwapCexCreateTransactionResponse(
    // val request: ApiSwapCexCreateTransactionRequest,
    val swap: MApiSwapHistoryItem
)

@JsonClass(generateAdapter = true)
data class MApiSwapTransfer(
    val toAddress: String,
    val amount: String,
    val payload: String?
)

@JsonClass(generateAdapter = true)
data class MApiSwapHistoryItem(
    val id: String,
    val timestamp: Long,
    val lt: Long? = null,
    val from: String,
    val fromAmount: BigDecimal,
    val to: String,
    val toAmount: BigDecimal,
    val networkFee: Double,
    val swapFee: BigDecimal,
    val status: MApiSwapHistoryItemStatus,
    val txIds: List<String>,
    val isCanceled: Boolean?,
    val cex: Cex? = null
) {
    @JsonClass(generateAdapter = true)
    data class Cex(
        val payinAddress: String,
        val payoutAddress: String,
        val payinExtraId: String? = null,
        val status: MApiSwapCexTransactionStatus,
        val transactionId: String
    )
}

@JsonClass(generateAdapter = true)
data class MSwapCexValidateAddressParams(
    val slug: String,
    val address: String
)

@JsonClass(generateAdapter = true)
data class MSwapCexValidateAddressResult(
    val result: Boolean,
    val message: String? = null
)

@JsonClass(generateAdapter = false)
enum class MApiSwapHistoryItemStatus {
    @Json(name = "pending")
    PENDING,

    @Json(name = "pendingTrusted")
    PENDING_TRUSTED,

    @Json(name = "completed")
    COMPLETED,

    @Json(name = "failed")
    FAILED,

    @Json(name = "expired")
    EXPIRED
}

@JsonClass(generateAdapter = false)
enum class MApiSwapDexLabel {
    @Json(name = "dedust")
    DEDUST,

    @Json(name = "ston")
    STON;

    val displayName: String
        get() {
            return when (this) {
                DEDUST -> "DeDust"
                STON -> "STON.fi"
            }
        }

    val icon: Int
        get() {
            return when (this) {
                DEDUST -> org.mytonwallet.app_air.icons.R.drawable.ic_dex_dedust
                STON -> org.mytonwallet.app_air.icons.R.drawable.ic_dex_stonfi
            }
        }
}

@JsonClass(generateAdapter = false)
enum class MApiTonWalletVersion {
    @Json(name = "simpleR1")
    SIMPLE_R1,

    @Json(name = "simpleR2")
    SIMPLE_R2,

    @Json(name = "simpleR3")
    SIMPLE_R3,

    @Json(name = "v2R1")
    V2_R1,

    @Json(name = "v2R2")
    V2_R2,

    @Json(name = "v3R1")
    V3_R1,

    @Json(name = "v3R2")
    V3_R2,

    @Json(name = "v4R2")
    V4_R2,

    @Json(name = "W5")
    W5
}

@JsonClass(generateAdapter = false)
enum class MApiSwapCexTransactionStatus {
    @Json(name = "new")
    NEW,

    @Json(name = "waiting")
    WAITING,

    @Json(name = "confirmed")
    CONFIRMED,

    @Json(name = "confirming")
    CONFIRMING,

    @Json(name = "exchanging")
    EXCHANGING,

    @Json(name = "sending")
    SENDING,

    @Json(name = "finished")
    FINISHED,

    @Json(name = "failed")
    FAILED,

    @Json(name = "refunded")
    REFUNDED,

    @Json(name = "hold")
    HOLD,

    @Json(name = "overdue")
    OVERDUE,

    @Json(name = "expired")
    EXPIRED;

    companion object {
        private var IN_PROGRESS_STATUSES =
            listOf(
                NEW,
                WAITING,
                CONFIRMING,
                EXCHANGING,
                SENDING,
                HOLD
            )
        private var FINISHED_STATUSES =
            listOf(
                CONFIRMED,
                FINISHED
            )
    }

    val uiStatus: MApiTransaction.UIStatus
        get() = when (this) {
            NEW, WAITING, CONFIRMING, EXCHANGING, SENDING -> MApiTransaction.UIStatus.PENDING
            EXPIRED, REFUNDED, OVERDUE -> MApiTransaction.UIStatus.EXPIRED
            FAILED -> MApiTransaction.UIStatus.FAILED
            CONFIRMED, FINISHED -> MApiTransaction.UIStatus.COMPLETED
            HOLD -> MApiTransaction.UIStatus.HOLD
        }

    val localized: String
        get() {
            return LocaleController.getString(
                when (this) {
                    WAITING -> "Waiting for Payment"
                    NEW, CONFIRMING, EXCHANGING, SENDING -> "In Progress"
                    CONFIRMED, FINISHED -> ""
                    FAILED -> "Failed"
                    REFUNDED -> "Refunded"
                    HOLD -> "On Hold"
                    OVERDUE, EXPIRED -> "Expired"
                }
            )
        }

    val color: WColor
        get() {
            return when (this) {
                WAITING, NEW, CONFIRMING, EXCHANGING, SENDING -> WColor.SecondaryText
                CONFIRMED, FINISHED -> WColor.Green
                FAILED, REFUNDED, OVERDUE, EXPIRED -> WColor.Red
                HOLD -> WColor.Orange
            }
        }

    val isInProgress: Boolean
        get() {
            return IN_PROGRESS_STATUSES.contains(this)
        }

    val isFinished: Boolean
        get() {
            return FINISHED_STATUSES.contains(this)
        }
}
