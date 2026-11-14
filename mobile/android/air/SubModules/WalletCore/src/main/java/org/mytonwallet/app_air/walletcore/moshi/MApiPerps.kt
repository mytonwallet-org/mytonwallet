package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import kotlin.math.abs
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

const val PERPS_CHAIN_HYPERLIQUID = "hyperliquid"

@JsonClass(generateAdapter = false)
enum class MApiPerpsSide(private val labelKey: String) {
    @Json(name = "long")
    LONG("Long"),

    @Json(name = "short")
    SHORT("Short");

    val title: String
        get() = LocaleController.getString(labelKey)
}

@JsonClass(generateAdapter = true)
data class MApiPerpsAssetContext(
    val funding: String? = null,
    val openInterest: String? = null,
    val prevDayPx: String? = null,
    val dayNtlVlm: String? = null,
    val markPx: String? = null,
    val midPx: String? = null,
    val oraclePx: String? = null,
    val percentChange24h: Double? = null,
    /** Already a percentage. */
    val fundingPercent: String? = null,
    val fundingIntervalHours: Int? = null,
    val openInterestUsd: String? = null
)

@JsonClass(generateAdapter = true)
data class MApiPerpsListedAsset(
    val id: String,
    val index: Int,
    val name: String,
    val chain: String,
    val provider: String,
    val dex: String = "",
    val symbol: String,
    val image: String? = null,
    val tintColor: String? = null,
    val szDecimals: Int = 0,
    val maxLeverage: Int = 1,
    val onlyIsolated: Boolean? = null,
    val isDelisted: Boolean? = null,
    val context: MApiPerpsAssetContext? = null,
    val displayName: String? = null,
    val description: String? = null,
    val keywords: List<String>? = null,
    /** Recent prices for a section's chart, when the backend sends them. */
    val sparkline: List<Double>? = null,
    /** Absent in the cached catalogue. */
    val tradingAvailability: MApiPerpsTradingAvailability? = null
) {
    val markPrice: Double?
        get() = context?.markPx?.toDoubleOrNull()

    val isRwaStock: Boolean
        get() = keywords?.contains("rwa") == true

    val isTradingUnavailable: Boolean
        get() = tradingAvailability?.isAvailable == false || isDelisted == true

    /** Change of the mark price over the last 24 hours, in percent. */
    val change24h: Double?
        get() {
            context?.percentChange24h?.let { return it }
            val price = markPrice ?: return null
            val previous = context?.prevDayPx?.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
            return (price / previous - 1) * 100
        }

    val volume24h: Double
        get() = context?.dayNtlVlm?.toDoubleOrNull() ?: 0.0
}

@JsonClass(generateAdapter = true)
data class MApiPerpsLeverage(val type: String, val value: Double)

@JsonClass(generateAdapter = true)
data class MApiPerpsCumFunding(val allTime: String, val sinceOpen: String, val sinceChange: String)

@JsonClass(generateAdapter = true)
data class MApiPerpsPosition(
    val coin: String,
    val cumFunding: MApiPerpsCumFunding? = null,
    val entryPx: String? = null,
    val leverage: MApiPerpsLeverage,
    val liquidationPx: String? = null,
    val marginUsed: String,
    val positionValue: String,
    val returnOnEquity: String,
    val szi: String,
    val unrealizedPnl: String
)

/** Normalized position of the shared SDK; monetary values are USD decimal strings. */
@JsonClass(generateAdapter = true)
data class MApiPerpsNativePosition(
    val id: String,
    val assetId: String,
    val dex: String = "",
    val side: MApiPerpsSide,
    val size: String,
    val collateral: String,
    val equity: String,
    val isNearLiquidation: Boolean? = null,
    /** A ratio: `0.1` is 10%. */
    val returnOnEquity: String? = null,
    /** Positive when received. */
    val funding: String? = null,
    val raw: MApiPerpsPosition
) {
    val coin: String
        get() = raw.coin

    val asset: MApiPerpsListedAsset?
        get() = PerpsStore.assetsById[assetId]

    val symbol: String
        get() = asset?.symbol ?: coin

    val image: String?
        get() = asset?.image

    val markPrice: Double?
        get() = asset?.markPrice

    val leverage: Int
        get() = raw.leverage.value.toInt()

    val sideText: String
        get() = "${side.title} ${leverage}x"

    val sizeAmount: Double
        get() = size.toDoubleOrNull() ?: 0.0

    /** Invested margin plus unrealized PnL. */
    val value: Double
        get() = equity.toDoubleOrNull() ?: 0.0

    /** Notional value of the position. */
    val positionValue: Double
        get() = raw.positionValue.toDoubleOrNull() ?: 0.0

    val pnl: Double
        get() = raw.unrealizedPnl.toDoubleOrNull() ?: 0.0

    val pnlPercent: Double
        get() = (returnOnEquity?.toDoubleOrNull() ?: 0.0) * 100

    val invested: Double
        get() = collateral.toDoubleOrNull() ?: 0.0

    val entryPrice: Double?
        get() = raw.entryPx?.toDoubleOrNull()

    val liquidationPrice: Double?
        get() = raw.liquidationPx?.toDoubleOrNull()

    val fundingReceived: Double?
        get() = funding?.toDoubleOrNull()
}

/** A backend Futures group; its assets are resolved against the trading catalogue. */
@JsonClass(generateAdapter = true)
data class MApiPerpsMarketSection(
    val id: String,
    val title: String,
    /** `largeHorizontal`, `grid` or `rows`. */
    val layout: String,
    val limit: Int? = null,
    val mobileLimit: Int? = null,
    /** The backend has markets beyond those it sent. */
    val hasMore: Boolean = false,
    val assets: List<MApiPerpsListedAsset> = emptyList()
) {
    /** Markets shown before Show All. */
    val displayLimit: Int
        get() = (mobileLimit ?: limit ?: assets.size).coerceAtLeast(1)

    val visibleAssets: List<MApiPerpsListedAsset>
        get() = assets.take(displayLimit)

    val hasHiddenAssets: Boolean
        get() = assets.size > displayLimit

    val showsSeeAll: Boolean
        get() = hasMore || hasHiddenAssets
}

@JsonClass(generateAdapter = true)
data class MApiPerpsLeverageEstimate(val leverage: Int, val liquidationPrice: String? = null)

/** What a deposit needs on Arbitrum; amounts are decimal strings. */
@JsonClass(generateAdapter = true)
data class MApiPerpsFundingRequirements(
    val requiredUsdc: String,
    /** Paymaster cost in USDC when the deposit is gasless. `"0"` when the wallet pays gas in ETH. */
    val requiredGasUsdc: String = "0",
    val requiredEth: String,
    /** Approximate USD value of [requiredEth]. */
    val requiredEthUsd: String,
    val needsUsdc: Boolean,
    val needsEth: Boolean,
    /** The most a new order can post as margin, after the fees it pays. */
    val availableCollateral: String? = null
)

/** `reason` is a localization key. */
@JsonClass(generateAdapter = true)
data class MApiPerpsTradingAvailability(val isAvailable: Boolean, val reason: String? = null)

/** The markets catalogue as cached between launches. */
@JsonClass(generateAdapter = true)
data class MApiPerpsCatalogue(
    val assets: List<MApiPerpsListedAsset> = emptyList(),
    val marketSections: List<MApiPerpsMarketSection>? = null,
    val onboarding: MApiPerpsOnboarding? = null
)

@JsonClass(generateAdapter = true)
data class MApiPerpsMarketSnapshot(
    val assets: List<MApiPerpsListedAsset> = emptyList(),
    val marketSections: List<MApiPerpsMarketSection>? = null,
    /** Zero when unknown. */
    val assetsFetchedAt: Long = 0,
    val onboarding: MApiPerpsOnboarding? = null
)

/** Read leniently. */
@JsonClass(generateAdapter = true)
data class MApiPerpsOnboarding(val stories: List<MApiPerpsOnboardingStory> = emptyList())

@JsonClass(generateAdapter = true)
data class MApiPerpsOnboardingStory(
    val id: String,
    /** HEVC. */
    val url: String,
    /** 8-bit H.264 copy of [url]. */
    val h264Url: String? = null,
    /** First frame of [url]. */
    val preview: String,
    /** Seconds. */
    val duration: Double,
    val bytes: Long
)

@JsonClass(generateAdapter = true)
data class MApiPerpsSnapshot(
    val assets: List<MApiPerpsListedAsset> = emptyList(),
    /** Absent on an older backend; an empty list shows no sections. */
    val marketSections: List<MApiPerpsMarketSection>? = null,
    /** Zero when unknown. */
    val assetsFetchedAt: Long = 0,
    val onboarding: MApiPerpsOnboarding? = null,
    val positions: List<MApiPerpsNativePosition> = emptyList(),
    val totalEquity: String = "0",
    val totalPnl: String = "0",
    /** A ratio: `0.1` is 10%. */
    val totalReturnOnEquity: String? = null,
    val timestamp: Long = 0,
    /** Books that failed to load; the totals then miss their positions. */
    val unavailableDexs: List<String> = emptyList(),
    val tradingAvailability: MApiPerpsTradingAvailability? = null,
    /** Free USDC on Hyperliquid. */
    val balanceWithdrawal: MApiPerpsBalanceWithdrawal? = null,
    /** Hyperliquid USDC each book can post as margin; `""` is the native book. */
    val spendableUsdcByDex: Map<String, String>? = null
) {
    /** A closed position can stay listed with zero size. */
    val openPositions: List<MApiPerpsNativePosition>
        get() = positions.filter { it.sizeAmount != 0.0 }

    val totalEquityAmount: Double
        get() = totalEquity.toDoubleOrNull() ?: 0.0

    val totalPnlAmount: Double
        get() = totalPnl.toDoubleOrNull() ?: 0.0

    val totalPnlPercent: Double
        get() = (totalReturnOnEquity?.toDoubleOrNull() ?: 0.0) * 100
}

@JsonClass(generateAdapter = true)
data class MApiPerpsFillLiquidation(val markPx: String? = null, val method: String? = null)

@JsonClass(generateAdapter = true)
data class MApiPerpsActivityDeposit(
    val grossAmount: String,
    val bridgeFee: String? = null,
    val txHash: String? = null
)

@JsonClass(generateAdapter = true)
data class MApiPerpsActivityWithdrawal(
    val amount: String,
    val receivedAmount: String? = null,
    val status: String? = null,
    val txHash: String? = null
)

/** Fees of one trade; [total] includes the bridge fee. */
@JsonClass(generateAdapter = true)
data class MApiPerpsFees(val trading: String? = null, val total: String)

enum class MApiPerpsActivityType(
    val titleKey: String,
    val detailsTitleKey: String,
    val paymentKey: String?
) {
    OPENED("\$perps_activity_opened", "Position Opened", "You Pay"),
    INCREASED("\$perps_activity_increased", "Position Increased", "You Paid"),
    REDUCED("\$perps_activity_reduced", "Position Reduced", "You Received"),
    CLOSED("\$perps_activity_closed", "Position Closed", "You Receive"),
    LIQUIDATED("\$perps_activity_liquidated", "Position Liquidated", null)
}

/** A backend trade activity, or a Hyperliquid fill the SDK classified. */
@JsonClass(generateAdapter = true)
data class MApiPerpsFill(
    val activityId: String? = null,
    val coin: String,
    val tid: Long? = null,
    val oid: Long? = null,
    val time: Long,
    val px: String? = null,
    val sz: String? = null,
    val side: String? = null,
    val dir: String? = null,
    val startPosition: String? = null,
    val closedPnl: String? = null,
    val fee: String? = null,
    val feeToken: String = "USDC",
    val leverage: Int? = null,
    /** Margin before and after this trade; backend activities only. */
    val collateralBefore: String? = null,
    val collateralAfter: String? = null,
    val receiptFees: MApiPerpsFees? = null,
    val deposit: MApiPerpsActivityDeposit? = null,
    val withdrawal: MApiPerpsActivityWithdrawal? = null,
    /** `opened`, `increased`, `reduced`, `closed` or `liquidated`. */
    val eventKind: String? = null,
    val positionSide: MApiPerpsSide? = null,
    val netPnl: String? = null,
    /** Executed size × price, not margin. */
    val notional: String? = null,
    val previousNotional: String? = null,
    val positionNotional: String? = null,
    val entryPrice: String? = null,
    /** Only when the fills reach back to the position's open. */
    val positionOpenedAt: Long? = null,
    val liquidation: MApiPerpsFillLiquidation? = null
) {
    /** `tid` alone is not unique across coins and times. */
    val identity: String
        get() = activityId ?: "$time:$coin:$tid"

    val asset: MApiPerpsListedAsset?
        get() = PerpsStore.assetsByCoin[coin]

    val symbol: String
        get() = asset?.symbol ?: coin

    val name: String
        get() = asset?.displayName ?: asset?.symbol ?: coin

    val resolvedSide: MApiPerpsSide
        get() = positionSide ?: if (dir.orEmpty().substringAfter(" > ").contains("Short")) {
            MApiPerpsSide.SHORT
        } else {
            MApiPerpsSide.LONG
        }

    val price: Double?
        get() = px?.toDoubleOrNull()

    private fun sizeAmount(): Double = sz?.toDoubleOrNull() ?: 0.0

    private fun startSize(): Double = abs(startPosition?.toDoubleOrNull() ?: 0.0)

    /** The SDK classifies fills whose history proves it; the rest follow Hyperliquid's `dir`. */
    val activityType: MApiPerpsActivityType
        get() = when (eventKind) {
            "opened" -> MApiPerpsActivityType.OPENED

            "increased" -> MApiPerpsActivityType.INCREASED

            "reduced" -> MApiPerpsActivityType.REDUCED

            "closed" -> MApiPerpsActivityType.CLOSED

            "liquidated" -> MApiPerpsActivityType.LIQUIDATED

            else -> when {
                liquidation != null -> MApiPerpsActivityType.LIQUIDATED

                dir.orEmpty().contains(" > ") || dir.orEmpty().startsWith("Open") ->
                    if (startSize() == 0.0 || dir.orEmpty().contains(" > ")) {
                        MApiPerpsActivityType.OPENED
                    } else {
                        MApiPerpsActivityType.INCREASED
                    }

                sizeAmount() >= startSize() -> MApiPerpsActivityType.CLOSED

                else -> MApiPerpsActivityType.REDUCED
            }
        }

    /** Closes and liquidations show their profit or loss rather than an amount. */
    val isResult: Boolean
        get() = activityType == MApiPerpsActivityType.CLOSED ||
            activityType == MApiPerpsActivityType.LIQUIDATED

    private fun fillNotional(): Double =
        notional?.toDoubleOrNull() ?: price?.let { sizeAmount() * it } ?: 0.0

    private fun previousNotionalAmount(): Double? = previousNotional?.toDoubleOrNull()
        ?: startPosition?.toDoubleOrNull()?.let { start -> price?.let { abs(start) * it } }

    /** The position's notional after the trade, or the profit or loss of a [isResult] one. */
    val amount: Double
        get() {
            val previous = previousNotionalAmount()
            return when (activityType) {
                MApiPerpsActivityType.OPENED -> fillNotional()

                MApiPerpsActivityType.INCREASED -> if (previous == null) {
                    fillNotional()
                } else {
                    positionNotional?.toDoubleOrNull() ?: (previous + fillNotional())
                }

                MApiPerpsActivityType.REDUCED -> if (previous == null) {
                    fillNotional()
                } else {
                    positionNotional?.toDoubleOrNull() ?: (previous - fillNotional())
                }

                MApiPerpsActivityType.CLOSED, MApiPerpsActivityType.LIQUIDATED ->
                    netPnl?.toDoubleOrNull() ?: closedPnl?.toDoubleOrNull() ?: 0.0
            }
        }

    val previousAmount: Double?
        get() = when (activityType) {
            MApiPerpsActivityType.INCREASED, MApiPerpsActivityType.REDUCED ->
                previousNotionalAmount()

            else -> null
        }

    val positionSize: Double?
        get() = if (isResult) {
            previousNotional
        } else {
            positionNotional
        }?.toDoubleOrNull()

    /** Executed size × price, shown as "Trade Size" where the position size is unknown. */
    val tradeSize: Double?
        get() = notional?.toDoubleOrNull()?.takeIf { it >= 0 }

    /** Margin after the trade, when the backend states it. */
    val margin: Double?
        get() = collateralAfter?.toDoubleOrNull()

    val previousMargin: Double?
        get() = collateralBefore?.toDoubleOrNull()
            ?.takeIf { activityType != MApiPerpsActivityType.OPENED }

    val payment: String?
        get() {
            val amount = deposit?.grossAmount ?: withdrawal?.let {
                if (it.status == WITHDRAWAL_COMPLETED) it.receivedAmount else return "—"
            }
            return amount?.toDoubleOrNull()?.toString(
                PAYMENT_DECIMALS,
                feeToken,
                PAYMENT_DECIMALS,
                smartDecimals = true,
                forceCurrencyToRight = true
            )
        }

    /** Profit or loss realized by a reduction, close or liquidation, after trading fees when known. */
    val realizedPnl: Double?
        get() = netPnl?.toDoubleOrNull() ?: closedPnl?.toDoubleOrNull()

    val closingValue: Double?
        get() = withdrawal?.takeIf {
            activityType == MApiPerpsActivityType.CLOSED && it.status == WITHDRAWAL_COMPLETED
        }?.receivedAmount?.toDoubleOrNull()

    val feeAmount: Double?
        get() = receiptFees?.total?.toDoubleOrNull() ?: fee?.toDoubleOrNull()

    val transferId: String?
        get() = deposit?.txHash ?: withdrawal?.txHash

    val entryPriceAmount: Double?
        get() = entryPrice?.toDoubleOrNull()

    val badgeText: String
        get() = leverage?.let { "${it}x ${resolvedSide.title}" } ?: resolvedSide.title

    /** The trade size in the header of a trade whose margin is unknown. */
    val headerTradeSize: Double?
        get() = tradeSize?.takeIf { !isResult && margin == null }

    /** Margin after the trade, the closing value of a close, or the profit or loss of a [isResult] one. */
    val headerAmount: Double
        get() = when {
            !isResult -> margin ?: headerTradeSize ?: amount
            activityType == MApiPerpsActivityType.CLOSED -> closingValue ?: amount
            else -> amount
        }

    val title: String
        get() = LocaleController.getStringWithKeyValues(
            activityType.titleKey,
            listOf("%asset%" to symbol)
        )

    val detailsTitle: String
        get() = LocaleController.getString(activityType.detailsTitleKey)

    private companion object {
        const val PAYMENT_DECIMALS = 4
        const val WITHDRAWAL_COMPLETED = "completed"
    }
}

/** One page of the account's activity, newest first. */
@JsonClass(generateAdapter = true)
data class MApiPerpsActivityHistory(
    val fills: List<MApiPerpsFill> = emptyList(),
    /** Continues with older activity; absent on the last page. */
    val nextCursor: String? = null,
    /** Any trade exists, rendered or not. */
    val hasActivity: Boolean = false
)

/** What the user entered; the SDK resolves it into a quote. */
@JsonClass(generateAdapter = true)
data class MApiPerpsDraftRequest(
    val assetId: String,
    val side: MApiPerpsSide,
    val amount: String,
    /** `currency` for USD collateral, `asset` for the leveraged asset quantity. */
    val unit: String,
    val leverage: Int,
    /** The amount is the target total collateral of the existing position. */
    val editing: Boolean? = null,
    val close: Boolean? = null,
    val fraction: Int? = null,
    val reset: Boolean? = null,
    /** [PERPS_FUNDING_BALANCE] pays from Hyperliquid; absent pays from the wallet. */
    val funding: String? = null,
    /** Changes leverage at the current position size. */
    val leverageOnly: Boolean? = null
)

/** A reviewed order, held by the SDK for 60 seconds. */
@JsonClass(generateAdapter = true)
data class MApiPerpsQuote(
    val id: String,
    val accountId: String,
    val assetId: String,
    /** `open`, `increase`, `reduce`, `close`, `leverage` or `unchanged`. */
    val kind: String,
    val side: MApiPerpsSide,
    val leverage: Int,
    val isCross: Boolean = false,
    val inputAmount: String,
    val collateral: String,
    val previousCollateral: String? = null,
    val estimatedCollateral: String? = null,
    /** Deposit left free on Hyperliquid after margin and fees. */
    val estimatedRemainingCollateral: String? = null,
    val equity: String? = null,
    val profitLoss: String? = null,
    val returnOnEquity: String? = null,
    val size: String,
    val previousSize: String? = null,
    val notional: String,
    val previousNotional: String? = null,
    val markPrice: String,
    val entryPrice: String? = null,
    /** The current position's, not the reviewed target's. */
    val liquidationPrice: String? = null,
    val estimatedLiquidationPrice: String? = null,
    /** Gross Arbitrum USDC paid with the bridge fee, or the margin taken from Hyperliquid. */
    val paymentAmount: String,
    /** `pending` until the released margin of a reduce or close is known. */
    val receiveStatus: String? = null,
    val estimatedReceiveAmount: String? = null,
    /** Set when the order deposits; `needsUsdc`/`needsEth` are false on a prepared quote. */
    val fundingRequirements: MApiPerpsFundingRequirements? = null,
    val bridgeFee: String,
    /** Absent when rates are unavailable; fees are then known at execution. */
    val estimatedFees: MApiPerpsFees? = null,
    /** Arbitrum gas of a wallet deposit, apart from [estimatedFees]. */
    val estimatedNetworkFeeEth: String? = null,
    val estimatedNetworkFeeUsd: String? = null,
    val switchesToUnified: Boolean? = null,
    /** [PERPS_FUNDING_BALANCE] when paid from Hyperliquid. */
    val funding: String? = null,
    val expiresAt: Long,
    val createdAt: Long
)

/** A snapshot preview, or a prepared review with [id]. */
@JsonClass(generateAdapter = true)
data class MApiPerpsBalanceWithdrawal(
    val balance: String,
    /** Includes the bridge fee. */
    val amount: String,
    val bridgeFee: String,
    val firstTransferFee: String? = null,
    val receiveAmount: String,
    val id: String? = null,
    val accountId: String? = null,
    val destination: String? = null,
    val expiresAt: Long? = null
)

/** Progress of a reviewed order; clients persist it to recover after a restart. */
@JsonClass(generateAdapter = true)
data class MApiPerpsOperation(
    val id: String,
    val accountId: String,
    val assetId: String,
    val kind: String,
    /** `running`, `completed`, `partial`, `unknown` or `failed`. */
    val state: String,
    /** `preparing`, `deposit`, `trade`, `withdrawal` or `finished`. */
    val stage: String,
    val createdAt: Long,
    val depositTxHash: String? = null,
    val acknowledgedAt: Long? = null,
    val orderId: Long? = null,
    /** Kept so that reconciling a restored record can tell a partial fill. */
    val submittedOrderSize: String? = null,
    val orderStatus: String? = null,
    val filledSize: String? = null,
    val positionSize: String? = null,
    val averagePrice: String? = null,
    val withdrawalAmount: String? = null,
    val withdrawalRequestedAmount: String? = null,
    val error: String? = null,
    val balanceWithdrawal: MApiPerpsBalanceWithdrawal? = null,
    /** The reviewed values a restored reduce needs; kept when SDK progress replaces this record. */
    val reviewedQuote: MApiPerpsQuote? = null
) {
    /** Still saved for recovery and reconciled. */
    val isUnresolved: Boolean
        get() = state != PERPS_OPERATION_COMPLETED && state != PERPS_OPERATION_FAILED

    val isUnseenPartialFill: Boolean
        get() = state == PERPS_OPERATION_COMPLETED && error == PERPS_PARTIAL_FILL_ERROR

    /** Blocks another order of the account until it settles or the user acknowledges it. */
    val blocksTrading: Boolean
        get() = isUnresolved && !(state == PERPS_OPERATION_UNKNOWN && acknowledgedAt != null)
}

const val PERPS_OPERATION_COMPLETED = "completed"
const val PERPS_OPERATION_FAILED = "failed"
const val PERPS_OPERATION_PARTIAL = "partial"
const val PERPS_OPERATION_RUNNING = "running"
const val PERPS_OPERATION_UNKNOWN = "unknown"
const val PERPS_PARTIAL_FILL_ERROR = "PerpsPartialFill"

const val PERPS_QUOTE_OPEN = "open"
const val PERPS_QUOTE_INCREASE = "increase"
const val PERPS_QUOTE_REDUCE = "reduce"
const val PERPS_QUOTE_CLOSE = "close"
const val PERPS_QUOTE_LEVERAGE = "leverage"
const val PERPS_QUOTE_UNCHANGED = "unchanged"
const val PERPS_QUOTE_WITHDRAW = "withdraw"
const val PERPS_BALANCE_WITHDRAWAL_ASSET_ID = "USDC"

const val PERPS_LAYOUT_LARGE_HORIZONTAL = "largeHorizontal"
const val PERPS_LAYOUT_GRID = "grid"
const val PERPS_LAYOUT_ROWS = "rows"

const val PERPS_UNIT_CURRENCY = "currency"
const val PERPS_FUNDING_BALANCE = "balance"

/** Token that funds perps and receives their payouts: USDC on Arbitrum, bridged to Hyperliquid. */
const val PERPS_PAYMENT_TOKEN_SLUG = "arbitrum-0xaf88d065"
