package org.mytonwallet.app_air.walletcore.api

import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryResponse
import org.mytonwallet.app_air.walletcore.stores.PortfolioStore
import java.text.SimpleDateFormat
import java.util.Calendar
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

    val params = JSONObject().apply {
        put("from", period.toFromIsoString())
        put("density", period.toDensity())
    }
    val response: ApiPortfolioHistoryResponse = bridge!!.callApiAsync(
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

private fun MHistoryTimePeriod.toFromIsoString(): String {
    val now = Date()
    val from = when (this) {
        MHistoryTimePeriod.DAY -> Date(now.time - 24L * 60 * 60 * 1000)
        MHistoryTimePeriod.WEEK -> Date(now.time - 7L * 24 * 60 * 60 * 1000)
        MHistoryTimePeriod.MONTH -> calendarMinus(now, Calendar.MONTH, 1)
        MHistoryTimePeriod.THREE_MONTHS -> calendarMinus(now, Calendar.MONTH, 3)
        MHistoryTimePeriod.YEAR -> calendarMinus(now, Calendar.YEAR, 1)
        MHistoryTimePeriod.ALL -> Date(PORTFOLIO_ALL_START_EPOCH_MS)
    }
    return ISO_DATE_FORMAT.get()!!.format(from)
}

private fun calendarMinus(base: Date, field: Int, amount: Int): Date {
    val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
    cal.time = base
    cal.add(field, -amount)
    return cal.time
}

private const val PORTFOLIO_ALL_START_EPOCH_MS: Long = 1_577_836_800_000L // 2020-01-01 UTC

private val ISO_DATE_FORMAT: ThreadLocal<SimpleDateFormat> = object : ThreadLocal<SimpleDateFormat>() {
    override fun initialValue(): SimpleDateFormat {
        return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
    }
}