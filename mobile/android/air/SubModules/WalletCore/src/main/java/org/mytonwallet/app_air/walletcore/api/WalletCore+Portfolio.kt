package org.mytonwallet.app_air.walletcore.api

import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryResponse
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

suspend fun WalletCore.fetchPortfolioNetWorthHistory(
    wallets: List<String>,
    baseCurrency: MBaseCurrency,
    period: MHistoryTimePeriod,
): ApiPortfolioHistoryResponse {
    return fetchPortfolioHistory("fetchPortfolioNetWorthHistory", wallets, baseCurrency, period)
}

suspend fun WalletCore.fetchPortfolioPnlCumulativeHistory(
    wallets: List<String>,
    baseCurrency: MBaseCurrency,
    period: MHistoryTimePeriod,
): ApiPortfolioHistoryResponse {
    return fetchPortfolioHistory("fetchPortfolioPnlCumulativeHistory", wallets, baseCurrency, period)
}

suspend fun WalletCore.fetchPortfolioPnlHistory(
    wallets: List<String>,
    baseCurrency: MBaseCurrency,
    period: MHistoryTimePeriod,
): ApiPortfolioHistoryResponse {
    return fetchPortfolioHistory("fetchPortfolioPnlHistory", wallets, baseCurrency, period)
}

private suspend fun WalletCore.fetchPortfolioHistory(
    methodName: String,
    wallets: List<String>,
    baseCurrency: MBaseCurrency,
    period: MHistoryTimePeriod,
): ApiPortfolioHistoryResponse {
    val params = JSONObject().apply {
        put("from", period.toFromIsoString())
        put("density", period.toDensity())
    }
    return bridge!!.callApiAsync(
        methodName,
        ArgumentsBuilder()
            .jsArray(wallets, String::class.java)
            .string(baseCurrency.currencyCode)
            .jsonObject(params)
            .build(),
        ApiPortfolioHistoryResponse::class.java
    )
}

private fun MHistoryTimePeriod.toDensity(): String = when (this) {
    MHistoryTimePeriod.DAY -> "15m"
    MHistoryTimePeriod.WEEK -> "3h"
    MHistoryTimePeriod.MONTH,
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