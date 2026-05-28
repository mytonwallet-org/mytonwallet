package org.mytonwallet.app_air.walletcore.stores

import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcontext.cacheStorage.PortfolioCacheKey
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryResponse
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

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
        period: MHistoryTimePeriod,
    ): String = PortfolioCacheKey(
        methodName = methodName,
        accountId = accountId,
        currencyCode = baseCurrency.currencyCode,
        periodValue = period.value,
        bucket = currentBucket(period),
    ).toString()

    suspend fun get(
        methodName: String,
        accountId: String,
        baseCurrency: MBaseCurrency,
        period: MHistoryTimePeriod,
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
        response: ApiPortfolioHistoryResponse,
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
