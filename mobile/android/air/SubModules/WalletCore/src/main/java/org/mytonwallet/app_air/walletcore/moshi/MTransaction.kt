package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.R
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.utils.WEquatable
import org.mytonwallet.app_air.walletcontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletcontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.utils.gradientColors
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.helpers.PoisoningCacheHelper
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexTransactionStatus.SENDING
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.JsonSealed
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.JsonSealedSubtype
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger
import java.util.Date

@JsonClass(generateAdapter = true)
data class ActivityExtra(
    @Json(name = "withW5Gasless") val withW5Gasless: Boolean? = null // Only for TON
    // TODO Move other extra fields here (externalMsgHash, ...)
)

@JsonClass(generateAdapter = false)
enum class ApiTransactionStatus {
    @Json(name = "pending")
    PENDING,

    @Json(name = "pendingTrusted")
    PENDING_TRUSTED,

    @Json(name = "completed")
    COMPLETED,

    @Json(name = "failed")
    FAILED;
}

@JsonClass(generateAdapter = false)
enum class ApiSwapStatus {
    @Json(name = "pending")
    PENDING,

    @Json(name = "pendingTrusted")
    PENDING_TRUSTED,

    @Json(name = "completed")
    COMPLETED,

    @Json(name = "failed")
    FAILED,

    @Json(name = "expired")
    EXPIRED;

    val uiStatus: MApiTransaction.UIStatus
        get() = when (this) {
            EXPIRED -> MApiTransaction.UIStatus.EXPIRED
            FAILED -> MApiTransaction.UIStatus.FAILED
            COMPLETED -> MApiTransaction.UIStatus.COMPLETED
            else -> MApiTransaction.UIStatus.PENDING
        }

    val localized: String
        get() {
            return LocaleController.getString(
                when (this) {
                    PENDING, PENDING_TRUSTED -> "In Progress"
                    COMPLETED -> "Swapped"
                    FAILED -> "Swap Failed"
                    EXPIRED -> "Swap Expired"
                }
            )
        }
}

@JsonClass(generateAdapter = true)
data class ApiSwapCexTransaction(
    @Json(name = "payinAddress") val payinAddress: String,
    @Json(name = "payoutAddress") val payoutAddress: String,
    @Json(name = "payinExtraId") val payinExtraId: String? = null,
    @Json(name = "status") val status: MApiSwapCexTransactionStatus?,
    @Json(name = "transactionId") val transactionId: String
)

@JsonSealed("kind")
sealed class MApiTransaction : WEquatable<MApiTransaction> {
    abstract val id: String
    abstract val shouldHide: Boolean?
    abstract val externalMsgHashNorm: String?
    abstract val shouldLoadDetails: Boolean?
    abstract val extra: ActivityExtra?
    abstract val kind: String
    abstract val timestamp: Long
    abstract val title: String

    val tokenPrice: Double? = TokenStore.getToken(getTxSlug())?.price
    var isEmulation: Boolean = false

    @JsonSealedSubtype("transaction")
    @JsonClass(generateAdapter = true)
    data class Transaction(
        @Json(name = "id") override val id: String,
        @Json(name = "shouldHide") override val shouldHide: Boolean? = null,
        @Json(name = "externalMsgHashNorm") override val externalMsgHashNorm: String?,
        @Json(name = "shouldLoadDetails") override val shouldLoadDetails: Boolean? = null,
        @Json(name = "extra") override val extra: ActivityExtra? = null,
        @Json(name = "kind") override val kind: String = "transaction",
        @Json(name = "timestamp") override val timestamp: Long,

        @Json(name = "amount") val amount: BigInteger,
        @Json(name = "fromAddress") val fromAddress: String,
        @Json(name = "toAddress") val toAddress: String?,
        @Json(name = "comment") val comment: String? = null,
        @Json(name = "encryptedComment") val encryptedComment: String? = null,
        @Json(name = "fee") val fee: BigInteger,
        @Json(name = "slug") val slug: String,
        @Json(name = "isIncoming") val isIncoming: Boolean,
        @Json(name = "normalizedAddress") val normalizedAddress: String,
        @Json(name = "type") val type: ApiTransactionType? = null,
        @Json(name = "metadata") val metadata: ApiTransactionMetadata? = null,
        @Json(name = "nft") val nft: ApiNft? = null,
        @Json(name = "status") val status: ApiTransactionStatus = ApiTransactionStatus.COMPLETED,
    ) : MApiTransaction() {
        val isStaking: Boolean
            get() {
                return type == ApiTransactionType.STAKE ||
                    type == ApiTransactionType.UNSTAKE ||
                    type == ApiTransactionType.UNSTAKE_REQUEST
            }

        override val title: String
            get() {
                val transactionTime: ApiTransactionType.TransactionTime = when {
                    isLocal() -> ApiTransactionType.TransactionTime.PRESENT
                    isEmulation -> ApiTransactionType.TransactionTime.FUTURE
                    else -> ApiTransactionType.TransactionTime.PAST
                }
                return type?.getTitle(transactionTime, isIncoming) ?: if (isNft) {
                    when {
                        isIncoming && transactionTime == ApiTransactionType.TransactionTime.PAST -> "Received"
                        isIncoming && transactionTime == ApiTransactionType.TransactionTime.PRESENT -> "Receiving"
                        isIncoming -> "Receive"
                        !isIncoming && transactionTime == ApiTransactionType.TransactionTime.PAST -> "Sent"
                        !isIncoming && transactionTime == ApiTransactionType.TransactionTime.PRESENT -> "Sending"
                        else -> "Send"
                    }
                } else {
                    when {
                        isIncoming && transactionTime == ApiTransactionType.TransactionTime.PAST -> "Received"
                        isIncoming && transactionTime == ApiTransactionType.TransactionTime.PRESENT -> "Receiving"
                        isIncoming -> "Receive"
                        !isIncoming && transactionTime == ApiTransactionType.TransactionTime.PAST -> "Sent"
                        !isIncoming && transactionTime == ApiTransactionType.TransactionTime.PRESENT -> "Sending"
                        else -> "Send"
                    }
                }.let { LocaleController.getString(it) }
            }

        val token: MToken?
            get() {
                return TokenStore.getToken(getTxSlug())
            }

        val hasComment: Boolean
            get() {
                return (!comment.isNullOrEmpty() || encryptedComment != null) &&
                    (!isIncoming || !isPoisoningOrScam()) &&
                    !isStaking
            }

        val shouldShowTransactionAddress: Boolean
            get() {
                val shouldHide = isStaking || type == ApiTransactionType.BURN
                    || (!isIncoming && isNft && toAddress == nft?.address);

                return !shouldHide;
            }
    }

    @JsonSealedSubtype("swap")
    @JsonClass(generateAdapter = true)
    data class Swap(
        @Json(name = "id") override val id: String,
        @Json(name = "shouldHide") override val shouldHide: Boolean? = null,
        @Json(name = "externalMsgHashNorm") override val externalMsgHashNorm: String?,
        @Json(name = "shouldLoadDetails") override val shouldLoadDetails: Boolean? = null,
        @Json(name = "extra") override val extra: ActivityExtra? = null,
        @Json(name = "kind") override val kind: String = "swap",
        @Json(name = "timestamp") override val timestamp: Long,

        @Json(name = "lt") val lt: Long? = null,
        @Json(name = "from") val from: String,
        @Json(name = "fromAmount") val fromAmount: Double,
        @Json(name = "to") val to: String,
        @Json(name = "toAmount") val toAmount: Double,
        @Json(name = "networkFee") val networkFee: Double? = null,
        @Json(name = "swapFee") val swapFee: Double? = null,
        @Json(name = "ourFee") val ourFee: Double? = null,
        @Json(name = "status") val status: ApiSwapStatus,
        @Json(name = "hashes") val hashes: List<String>?,
        @Json(name = "isCanceled") val isCanceled: Boolean? = null,
        @Json(name = "cex") val cex: ApiSwapCexTransaction? = null
    ) : MApiTransaction() {
        val fromToken: MToken?
            get() {
                return TokenStore.getToken(from, searchMinterAddress = true)
            }

        val toToken: MToken?
            get() {
                return TokenStore.getToken(to, searchMinterAddress = true)
            }

        override val title: String
            get() {
                return LocaleController.getString(
                    when {
                        status.uiStatus == UIStatus.COMPLETED && !isEmulation -> "Swapped"
                        else -> "Swap"
                    }
                )
            }

        val subtitle: String
            get() {
                if (cex?.status != null) {
                    return if (cex.status == SENDING || cex.status == MApiSwapCexTransactionStatus.FINISHED) {
                        ""
                    } else {
                        if (cex.status == MApiSwapCexTransactionStatus.WAITING && isInternalSwap)
                            LocaleController.getString("In Progress")
                        else
                            cex.status.localized
                    }
                }
                return if (status == ApiSwapStatus.PENDING || status == ApiSwapStatus.COMPLETED) "" else status.localized
            }

        val isInProgress: Boolean
            get() {
                return isLocal() || status == ApiSwapStatus.PENDING || cex?.status?.isInProgress == true
            }

        val isInternalSwap: Boolean
            get() {
                val isMultichain = AccountStore.activeAccount?.isMultichain == true

                return (fromToken?.chain == MBlockchain.ton.name && toToken?.chain == MBlockchain.ton.name) ||
                    (isMultichain &&
                        fromToken != null &&
                        toToken != null &&
                        AccountStore.activeAccount?.addressByChain[fromToken!!.chain] != null &&
                        AccountStore.activeAccount?.addressByChain[toToken!!.chain] == cex?.payoutAddress)
            }
    }

    @JsonClass(generateAdapter = false)
    enum class UIStatus {
        @Json(name = "hold")
        HOLD,

        @Json(name = "pending")
        PENDING,

        @Json(name = "expired")
        EXPIRED,

        @Json(name = "failed")
        FAILED,

        @Json(name = "completed")
        COMPLETED;
    }

    companion object {
        fun fromJson(jsonObject: JSONObject): MApiTransaction? {
            val adapter = WalletCore.moshi.adapter(MApiTransaction::class.java)
            return adapter.fromJson(jsonObject.toString())
        }
    }

    fun toDictionary(): JSONObject {
        val adapter = WalletCore.moshi.adapter(MApiTransaction::class.java)
        return JSONObject(adapter.toJson(this))
    }

    fun getTxIdentifier(): String? {
        return when (this) {
            is Swap -> {
                if ((hashes?.size ?: 0) > 0) hashes?.first() else id.split(':').firstOrNull()
            }

            is Transaction -> {
                id
            }
        }
    }

    fun getTxHash(): String? {
        if (getTxIdentifier().isNullOrEmpty())
            return null
        val token = TokenStore.getToken(getTxSlug())
        val chain =
            if (token?.chain != null) MBlockchain.valueOf(
                token.chain
            ) else if (this is Swap) MBlockchain.ton else return null

        return when (chain) {
            MBlockchain.ton -> {
                getTxIdentifier()?.split(":")?.firstOrNull()
            }

            MBlockchain.tron -> {
                getTxIdentifier()?.split("|")?.firstOrNull()
            }

            else -> {
                null
            }
        }
    }

    fun getTxSlug(): String {
        return when (this) {
            is Swap -> {
                from
            }

            is Transaction -> {
                slug
            }
        }
    }

    fun isPending(): Boolean {
        return when (this) {
            is Swap -> {
                status == ApiSwapStatus.PENDING || status == ApiSwapStatus.PENDING_TRUSTED
            }

            is Transaction -> {
                status == ApiTransactionStatus.PENDING || status == ApiTransactionStatus.PENDING_TRUSTED
            }
        }
    }

    fun isLocal(): Boolean {
        return id.endsWith(":local") == true
    }

    fun isBackendSwapId(): Boolean {
        return id.endsWith(":backend-swap") == true
    }

    fun isPoisoningOrScam(): Boolean {
        return when (this) {
            is Transaction -> {
                if (metadata?.isScam == true) {
                    return true
                }
                if (PoisoningCacheHelper.getIsTransactionWithPoisoning(this))
                    return true
                return false
            }

            else -> false
        }
    }

    fun isTinyOrScam(): Boolean {
        return when (this) {
            is Transaction -> {
                if (isPoisoningOrScam())
                    return true
                val token = TokenStore.getToken(getTxSlug()) ?: return false
                if (nft != null || type != null) {
                    return false
                }
                token.priceUsd * amount.doubleAbsRepresentation(
                    token.decimals
                ) < 0.01
            }

            else -> false
        }
    }

    override fun isSame(comparing: WEquatable<*>): Boolean {
        if (comparing is MApiTransaction)
            return id == comparing.id
        return false
    }

    override fun isChanged(comparing: WEquatable<*>): Boolean {
        if (comparing is MApiTransaction) {
            if (shouldHide != comparing.shouldHide)
                return true
            if (tokenPrice != comparing.tokenPrice)
                return true
            if (this is Swap && comparing is Swap) {
                return status != comparing.status || cex?.status != comparing.cex?.status || hashes?.size != comparing.hashes?.size
            }
            if (this is Transaction) {
                return isLocal() != comparing.isLocal()
            }
        }
        return false
    }

    val dt: Date
        get() {
            return Date(timestamp)
        }

    val swapType: SwapType
        get() {
            if (this is Swap) {
                return when {
                    fromToken?.isOnChain == false -> SwapType.CROSS_CHAIN_TO_WALLET
                    toToken?.isOnChain == false -> SwapType.CROSS_CHAIN_FROM_WALLET
                    else -> SwapType.ON_CHAIN
                }
            }
            return SwapType.ON_CHAIN
        }

    val iconColors: IntArray
        get() {
            return (when (this) {
                is Transaction -> {
                    val text =
                        if (metadata?.name?.isNotEmpty() == true) metadata.name else (if (isIncoming) fromAddress else toAddress
                            ?: "")
                    text
                }

                else -> {
                    ""
                }
            }).gradientColors
        }

    val peerAddress: String
        get() {
            return (when (this) {
                is Transaction -> {
                    if (isIncoming)
                        fromAddress
                    else
                        toAddress
                            ?: ""
                }

                else -> {
                    ""
                }
            })
        }

    fun addressToShow(): Pair<String, Boolean>? {
        return (when (this) {
            is Transaction -> {
                AddressStore.getAddress(peerAddress)?.name?.let { name ->
                    Pair(name, true)
                } ?: run {
                    if (metadata?.name?.isNotEmpty() == true)
                        Pair(metadata.name, true) else
                        Pair(peerAddress.formatStartEndAddress(), false)
                }
            }

            else -> {
                null
            }
        })
    }

    val isNft: Boolean
        get() {
            return (this as? Transaction)?.nft != null
        }

    val explorerUrl: String?
        get() {
            if (getTxHash().isNullOrEmpty())
                return null
            val txHash = getTxHash()
            val token = TokenStore.getToken(getTxSlug())
            val chain =
                if (token?.chain != null) MBlockchain.valueOf(
                    token.chain
                ) else if (this is Swap) MBlockchain.ton else return null

            return when (chain) {
                MBlockchain.ton -> {
                    "${ExplorerHelpers.tonScanUrl(WalletCore.activeNetwork)}tx/$txHash"
                }

                MBlockchain.tron -> {
                    "${ExplorerHelpers.tronScanUrl(WalletCore.activeNetwork)}transaction/$txHash"
                }

                else -> {
                    null
                }
            }
        }

    data class ParsedTxId(
        val hash: String,
        val subId: String? = null,
        val type: UnusualTxType? = null
    )

    enum class UnusualTxType(val rawValue: String) {
        BACKEND_SWAP("backend-swap"),
        LOCAL("local"),
        ADDITIONAL("additional");

        companion object {
            fun fromRawValue(value: String): UnusualTxType? = entries.find { it.rawValue == value }
        }
    }

    val parsedTxId: ParsedTxId
        get() {
            val split = id.split(":", limit = 3)
            val hash = split.getOrNull(0).orEmpty()
            val subId = split.getOrNull(1)
            val type = split.getOrNull(2)?.let { UnusualTxType.fromRawValue(it) }
            return ParsedTxId(hash = hash, subId = subId, type = type)
        }
}

@JsonClass(generateAdapter = false)
enum class ApiTransactionType {
    @Json(name = "stake")
    STAKE,

    @Json(name = "unstake")
    UNSTAKE,

    @Json(name = "unstakeRequest")
    UNSTAKE_REQUEST,

    @Json(name = "callContract")
    CALL_CONTRACT,

    @Json(name = "excess")
    EXCESS,

    @Json(name = "contractDeploy")
    CONTRACT_DEPLOY,

    @Json(name = "bounced")
    BOUNCED,

    @Json(name = "mint")
    MINT,

    @Json(name = "burn")
    BURN,

    @Json(name = "auctionBid")
    AUCTION_BID,

    @Json(name = "nftTrade")
    NFT_TRADE,

    @Json(name = "dnsChangeAddress")
    DNS_CHANGE_ADDRESS,

    @Json(name = "dnsChangeSite")
    DNS_CHANGE_SITE,

    @Json(name = "dnsChangeSubdomains")
    DNS_CHANGE_SUBDOMAINS,

    @Json(name = "dnsChangeStorage")
    DNS_CHANGE_STORAGE,

    @Json(name = "dnsDelete")
    DNS_DELETE,

    @Json(name = "dnsRenew")
    DNS_RENEW,

    @Json(name = "liquidityDeposit")
    LIQUIDITY_DEPOSIT,

    @Json(name = "liquidityWithdraw")
    LIQUIDITY_WITHDRAW;

    private val icons: Map<ApiTransactionType, Int> by lazy {
        mapOf(
            STAKE to R.drawable.ic_act_percent,
            UNSTAKE to R.drawable.ic_act_percent,
            UNSTAKE_REQUEST to R.drawable.ic_act_percent,
            CALL_CONTRACT to R.drawable.ic_act_contract,
            EXCESS to R.drawable.ic_act_received,
            CONTRACT_DEPLOY to R.drawable.ic_act_contract,
            BOUNCED to R.drawable.ic_act_received,
            MINT to R.drawable.ic_act_mint,
            BURN to R.drawable.ic_act_burn,
            AUCTION_BID to R.drawable.ic_act_auction,
            NFT_TRADE to R.drawable.ic_act_nft_purchase,
            DNS_CHANGE_ADDRESS to R.drawable.ic_act_ton_dns,
            DNS_CHANGE_SITE to R.drawable.ic_act_ton_dns,
            DNS_CHANGE_SUBDOMAINS to R.drawable.ic_act_ton_dns,
            DNS_CHANGE_STORAGE to R.drawable.ic_act_ton_dns,
            DNS_DELETE to R.drawable.ic_act_ton_dns,
            DNS_RENEW to R.drawable.ic_act_ton_dns,
            LIQUIDITY_DEPOSIT to R.drawable.ic_act_liquidity_provided,
            LIQUIDITY_WITHDRAW to R.drawable.ic_act_liquidity_withdrawn
        )
    }

    enum class TransactionTime {
        PAST,        // e.g. "Received"
        PRESENT,     // e.g. "Receiving"
        FUTURE       // e.g. "Receive"
    }

    private val titles: Map<ApiTransactionType, Triple<String, String, String>> by lazy {
        mapOf(
            STAKE to Triple("Staked", "Staking", "Stake"),
            UNSTAKE to Triple("Unstaked", "Unstaking", "Unstake"),
            UNSTAKE_REQUEST to Triple("Unstake Request", "Requesting Unstake", "Request Unstake"),
            CALL_CONTRACT to Triple("Contract Called", "Calling Contract", "Call Contract"),
            EXCESS to Triple("Excess", "Processing Excess", "Process Excess"),
            CONTRACT_DEPLOY to Triple("Contract Deployed", "Deploying Contract", "Deploy Contract"),
            BOUNCED to Triple("Bounced", "Bouncing", "Bounce"),
            MINT to Triple("Minted", "Minting", "Mint"),
            BURN to Triple("Burned", "Burning", "Burn"),
            AUCTION_BID to Triple(
                "NFT Auction Bid",
                "Bidding Auction",
                "Bid at NFT Auction"
            ),
            DNS_CHANGE_ADDRESS to Triple("Address Updated", "Updating Address", "Update Address"),
            DNS_CHANGE_SITE to Triple("Site Updated", "Updating Site", "Update Site"),
            DNS_CHANGE_SUBDOMAINS to Triple(
                "Subdomains Updated",
                "Updating Subdomains",
                "Update Subdomains"
            ),
            DNS_CHANGE_STORAGE to Triple("Storage Updated", "Updating Storage", "Update Storage"),
            DNS_DELETE to Triple(
                "Domain Record Deleted",
                "Deleting Domain Record",
                "Delete Domain Record"
            ),
            DNS_RENEW to Triple("Domain Renewed", "Renewing Domain", "Renew Domain"),
            LIQUIDITY_DEPOSIT to Triple(
                "Provided Liquidity",
                "Providing Liquidity",
                "Provide Liquidity"
            ),
            LIQUIDITY_WITHDRAW to Triple(
                "Withdrawn Liquidity",
                "Withdrawing Liquidity",
                "Withdraw Liquidity"
            )
        )
    }

    private val directionalTitles: Map<ApiTransactionType, Pair<Triple<String, String, String>, Triple<String, String, String>>> by lazy {
        mapOf(
            // (incoming past,present,future), (outgoing past,present,future)
            NFT_TRADE to Pair(
                Triple("NFT Sold", "Selling NFT", "Sell NFT"),
                Triple("NFT Bought", "Buying NFT", "Buy NFT")
            )
        )
    }

    fun getTitle(time: TransactionTime, isIncoming: Boolean): String? {
        directionalTitles[this]?.let { (incomingTriple, outgoingTriple) ->
            val selectedTriple = if (isIncoming) incomingTriple else outgoingTriple
            return LocaleController.getString(
                when (time) {
                    TransactionTime.PAST -> selectedTriple.first
                    TransactionTime.PRESENT -> selectedTriple.second
                    TransactionTime.FUTURE -> selectedTriple.third
                }
            )
        }

        val triple = titles[this] ?: return null
        return LocaleController.getString(
            when (time) {
                TransactionTime.PAST -> triple.first
                TransactionTime.PRESENT -> triple.second
                TransactionTime.FUTURE -> triple.third
            }
        )
    }

    fun getIcon(): Int? {
        return icons[this]
    }
}

@JsonClass(generateAdapter = true)
data class ApiTransactionMetadata(
    @Json(name = "name") val name: String? = null,
    @Json(name = "isScam") val isScam: Boolean? = null,
    @Json(name = "isMemoRequired") val isMemoRequired: Boolean? = null
)

data class LocalActivityParams(
    val type: ApiTransactionType? = null,
    val inMsgHash: String? = null,
    val slug: String? = null,
    val toAddress: String? = null
)
