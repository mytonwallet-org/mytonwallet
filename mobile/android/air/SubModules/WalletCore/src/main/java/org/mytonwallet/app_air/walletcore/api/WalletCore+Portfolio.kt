package org.mytonwallet.app_air.walletcore.api

import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryResponse
import org.mytonwallet.app_air.walletcore.stores.PortfolioStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

suspend fun WalletCore.fetchPortfolioNetWorthHistory(
    accountId: String,
    wallets: List<String>,
    baseCurrency: MBaseCurrency,
    period: MHistoryTimePeriod,
    cacheOnly: Boolean = false,
): ApiPortfolioHistoryResponse? {
    return fetchPortfolioHistory(
        "fetchPortfolioNetWorthHistory", accountId, wallets, baseCurrency, period, cacheOnly
    )
}

suspend fun WalletCore.fetchPortfolioPnlCumulativeHistory(
    accountId: String,
    wallets: List<String>,
    baseCurrency: MBaseCurrency,
    period: MHistoryTimePeriod,
    cacheOnly: Boolean = false,
): ApiPortfolioHistoryResponse? {
    return fetchPortfolioHistory(
        "fetchPortfolioPnlCumulativeHistory", accountId, wallets, baseCurrency, period, cacheOnly
    )
}

suspend fun WalletCore.fetchPortfolioPnlHistory(
    accountId: String,
    wallets: List<String>,
    baseCurrency: MBaseCurrency,
    period: MHistoryTimePeriod,
    cacheOnly: Boolean = false,
): ApiPortfolioHistoryResponse? {
    return fetchPortfolioHistory(
        "fetchPortfolioPnlHistory", accountId, wallets, baseCurrency, period, cacheOnly
    )
}

private suspend fun WalletCore.fetchPortfolioHistory(
    methodName: String,
    accountId: String,
    wallets: List<String>,
    baseCurrency: MBaseCurrency,
    period: MHistoryTimePeriod,
    cacheOnly: Boolean,
): ApiPortfolioHistoryResponse? {
    PortfolioStore.get(methodName, accountId, baseCurrency, period)?.let { return it }
    if (cacheOnly) return null

    val nowMs = System.currentTimeMillis()
    val params = JSONObject().apply {
        put("from", period.fromIsoString(nowMs))
        put("to", toIsoString(nowMs))
        put("density", period.toDensity())
    }
    val response: ApiPortfolioHistoryResponse = requiredBridge.callApiAsync(
        methodName,
        ArgumentsBuilder()
            .jsArray(wallets, String::class.java)
            .string(baseCurrency.currencyCode)
            .jsonObject(params)
            .build(),
        ApiPortfolioHistoryResponse::class.java
    )
    PortfolioStore.put(methodName, accountId, baseCurrency, period, response)
    return response
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
private fun toIsoString(nowMs: Long): String {
    return isoDateFormat().format(Date(startOfUtcDay(nowMs) + DAY_MS - 1000L))
}

// The epoch is aligned to UTC midnight, so flooring by whole days yields start-of-day UTC.
private fun startOfUtcDay(ms: Long): Long = ms - (ms % DAY_MS)

private const val DAY_MS: Long = 24L * 60 * 60 * 1000
private const val PORTFOLIO_ALL_START_EPOCH_MS: Long = 1_577_836_800_000L // 2020-01-01 UTC

private val ISO_DATE_FORMAT: ThreadLocal<SimpleDateFormat> =
    object : ThreadLocal<SimpleDateFormat>() {
        override fun initialValue(): SimpleDateFormat {
            return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
        }
    }

private fun isoDateFormat(): SimpleDateFormat = requireNotNull(ISO_DATE_FORMAT.get())
