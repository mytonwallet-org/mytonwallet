package org.mytonwallet.app_air.walletcore.stores

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlinx.coroutines.suspendCancellableCoroutine
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcontext.cacheStorage.PortfolioCacheKey
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryResponse
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

// Caches portfolio history responses with a time-bucketed key. Each period stays valid for the
// duration of its sampling density (DAY -> 5m, WEEK -> 1h, everything coarser -> 1d): the cache
// key embeds `floor(unixtime / windowSeconds)`, so once the bucket rolls over the old entry is no
// longer looked up. Backed by WCacheStorage so it survives process restarts.
//
// Reads are served from the in-memory map when warm; otherwise the keyed disk read + JSON parse,
// and the prefix-based pruning that scans `sharedPreferences.all`, run on a background executor so
// they never block the main thread.
object PortfolioStore : IStore {

    private val adapter by lazy {
        WalletCore.moshi.adapter(ApiPortfolioHistoryResponse::class.java)
    }

    private val memoryCache = ConcurrentHashMap<String, ApiPortfolioHistoryResponse>()
    private val diskExecutor = Executors.newSingleThreadExecutor()

    private fun MHistoryTimePeriod.cacheWindowSeconds(): Long = when (this) {
        MHistoryTimePeriod.DAY -> 5L * 60

        MHistoryTimePeriod.WEEK -> 60L * 60

        MHistoryTimePeriod.MONTH,
        MHistoryTimePeriod.THREE_MONTHS,
        MHistoryTimePeriod.YEAR,
        MHistoryTimePeriod.ALL -> 24L * 60 * 60
    }

    private fun currentBucket(period: MHistoryTimePeriod): Long =
        System.currentTimeMillis() / 1000 / period.cacheWindowSeconds()

    private fun cacheKey(
        methodName: String,
        accountId: String,
        baseCurrency: MBaseCurrency,
        period: MHistoryTimePeriod
    ): String = PortfolioCacheKey(
        methodName = methodName,
        accountId = accountId,
        currencyCode = baseCurrency.currencyCode,
        periodValue = period.value,
        bucket = currentBucket(period)
    ).toString()

    suspend fun get(
        methodName: String,
        accountId: String,
        baseCurrency: MBaseCurrency,
        period: MHistoryTimePeriod
    ): ApiPortfolioHistoryResponse? {
        val key = cacheKey(methodName, accountId, baseCurrency, period)
        memoryCache[key]?.let { return it }
        return onDiskThread {
            val cached = WCacheStorage.getPortfolio(key) ?: return@onDiskThread null
            try {
                adapter.fromJson(cached)?.also { memoryCache[key] = it }
            } catch (_: Throwable) {
                null
            }
        }
    }

    fun put(
        methodName: String,
        accountId: String,
        baseCurrency: MBaseCurrency,
        period: MHistoryTimePeriod,
        response: ApiPortfolioHistoryResponse
    ) {
        val key = cacheKey(methodName, accountId, baseCurrency, period)
        // Drop the chart's prior entries (older buckets / other currencies) so it keeps one entry.
        val chartPrefix = PortfolioCacheKey.chartPrefix(accountId, methodName, period.value)
        memoryCache.keys.removeAll { it.startsWith(chartPrefix) }
        memoryCache[key] = response
        diskExecutor.execute {
            WCacheStorage.cleanPortfolioChart(accountId, methodName, period.value)
            try {
                WCacheStorage.setPortfolio(key, adapter.toJson(response))
            } catch (_: Throwable) {
            }
        }
    }

    suspend fun fetchHistory(
        kind: ApiMethod.Portfolio.HistoryKind,
        accountId: String,
        wallets: List<String>,
        baseCurrency: MBaseCurrency,
        period: MHistoryTimePeriod,
        cacheOnly: Boolean = false
    ): ApiPortfolioHistoryResponse? {
        get(kind.methodName, accountId, baseCurrency, period)?.let { return it }
        if (cacheOnly) return null

        val nowMs = System.currentTimeMillis()
        val params = ApiMethod.Portfolio.FetchHistory.Params(
            from = period.fromIsoString(nowMs),
            to = toIsoString(nowMs),
            density = period.toDensity()
        )
        val response = WalletCore.call(
            ApiMethod.Portfolio.FetchHistory(kind, wallets, baseCurrency.currencyCode, params)
        )
        put(kind.methodName, accountId, baseCurrency, period, response)
        return response
    }

    fun removeAccount(accountId: String) {
        memoryCache.keys.removeAll { PortfolioCacheKey.parse(it)?.accountId == accountId }
    }

    private suspend fun <T> onDiskThread(block: () -> T): T =
        suspendCancellableCoroutine { continuation ->
            diskExecutor.execute {
                if (continuation.isActive) {
                    continuation.resumeWith(runCatching { block() })
                }
            }
        }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        memoryCache.clear()
    }
}

private fun MHistoryTimePeriod.toDensity(): String = when (this) {
    MHistoryTimePeriod.DAY -> "5m"

    MHistoryTimePeriod.WEEK -> "1h"

    MHistoryTimePeriod.MONTH -> "4h"

    MHistoryTimePeriod.THREE_MONTHS,
    MHistoryTimePeriod.YEAR,
    MHistoryTimePeriod.ALL -> "1d"
}

private fun MHistoryTimePeriod.durationMs(): Long? = when (this) {
    MHistoryTimePeriod.DAY -> DAY_MS
    MHistoryTimePeriod.WEEK -> 7 * DAY_MS
    MHistoryTimePeriod.MONTH -> 30 * DAY_MS
    MHistoryTimePeriod.THREE_MONTHS -> 90 * DAY_MS
    MHistoryTimePeriod.YEAR -> 365 * DAY_MS
    MHistoryTimePeriod.ALL -> null
}

// `from` is the start of the UTC day of (now − period length); ALL is anchored at 2020-01-01.
private fun MHistoryTimePeriod.fromIsoString(nowMs: Long): String {
    val fromMs = durationMs()?.let { startOfUtcDay(nowMs - it) } ?: PORTFOLIO_ALL_START_EPOCH_MS
    return isoDateFormat().format(Date(fromMs))
}

// `to` is the end of the UTC day of now (23:59:59.000).
private fun toIsoString(nowMs: Long): String =
    isoDateFormat().format(Date(startOfUtcDay(nowMs) + DAY_MS - 1000L))

// The epoch is aligned to UTC midnight, so flooring by whole days yields start-of-day UTC.
private fun startOfUtcDay(ms: Long): Long = ms - (ms % DAY_MS)

private const val DAY_MS: Long = 24L * 60 * 60 * 1000
private const val PORTFOLIO_ALL_START_EPOCH_MS: Long = 1_577_836_800_000L // 2020-01-01 UTC

private val ISO_DATE_FORMAT: ThreadLocal<SimpleDateFormat> =
    object : ThreadLocal<SimpleDateFormat>() {
        override fun initialValue(): SimpleDateFormat =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
    }

private fun isoDateFormat(): SimpleDateFormat = requireNotNull(ISO_DATE_FORMAT.get())
