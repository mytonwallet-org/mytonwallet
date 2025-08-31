package org.mytonwallet.app_air.walletcore.api

import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.helpers.logger.Logger
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import java.util.concurrent.Executors

fun WalletCore.fetchAllActivitySlice(
    accountId: String,
    limit: Int,
    toTimestamp: Long?,
    callback: (ArrayList<MApiTransaction>?, MBridgeError?) -> Unit
) {
    Logger.d(
        Logger.LogTag.ACTIVITY_STORE,
        "fetchAllActivitySlice, Account: $accountId - limit: $limit - toTimestamp: $toTimestamp"
    )
    bridge?.callApi(
        "fetchPastActivities",
        "[${JSONObject.quote(accountId)}, $limit, null, ${toTimestamp ?: System.currentTimeMillis()}]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, error)
        } else {
            val executor = Executors.newSingleThreadExecutor()
            executor.run {
                try {
                    val transactions = ArrayList<MApiTransaction>()
                    val transactionJSONArray = JSONArray(result)
                    for (index in 0..<transactionJSONArray.length()) {
                        val transactionObj = transactionJSONArray.getJSONObject(index)
                        val transaction = MApiTransaction.fromJson(transactionObj)!!
                        transactions.add(transaction)
                    }
                    Handler(Looper.getMainLooper()).post {
                        callback(transactions, null)
                    }
                } catch (_: Exception) {
                    Handler(Looper.getMainLooper()).post {
                        callback(null, null)
                    }
                }
            }
        }
    }
}

fun WalletCore.fetchTokenActivitySlice(
    accountId: String,
    slug: String,
    fromTimestamp: Long?,
    limit: Int,
    callback: (ArrayList<MApiTransaction>?, MBridgeError?, String) -> Unit
) {
    Logger.d(
        Logger.LogTag.ACTIVITY_STORE,
        "fetchTokenActivitySlice, Account: $accountId - Slug: $slug"
    )
    bridge?.callApi(
        "fetchPastActivities",
        "[${JSONObject.quote(accountId)}, $limit, ${
            if (slug == TONCOIN_SLUG)
                null
            else
                JSONObject.quote(slug)
        }, ${fromTimestamp ?: System.currentTimeMillis()}]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, error, accountId)
        } else {
            val executor = Executors.newSingleThreadExecutor()
            executor.run {
                try {
                    val transactions = ArrayList<MApiTransaction>()
                    val transactionJSONArray =
                        if (result == "undefined") JSONArray() else JSONArray(result)
                    for (index in 0..<transactionJSONArray.length()) {
                        val transactionObj = transactionJSONArray.getJSONObject(index)
                        val transaction = MApiTransaction.fromJson(transactionObj)!!
                        transactions.add(transaction)
                    }
                    Handler(Looper.getMainLooper()).post {
                        callback(transactions, null, accountId)
                    }
                } catch (_: Error) {
                    Handler(Looper.getMainLooper()).post {
                        callback(null, null, accountId)
                    }
                }
            }
        }
    }
}

fun WalletCore.tryUpdatePrices() {
    bridge?.callApi(
        "tryUpdateTokens",
        "[]"
    ) { _, _ ->
    }
    bridge?.callApi(
        "tryUpdateSwapTokens",
        "[]"
    ) { _, _ ->
    }
}

fun WalletCore.fetchPriceHistory(
    slug: String,
    period: MHistoryTimePeriod,
    baseCurrency: String,
    callback: (Array<Array<Double>>?, MBridgeError?) -> Unit
) {
    bridge?.callApi(
        "fetchPriceHistory",
        "[\"$slug\", \"${period.value}\", \"$baseCurrency\"]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, error)
        } else {
            val executor = Executors.newSingleThreadExecutor()
            executor.execute {
                try {
                    val arrayOfArray = JSONArray(result)
                    val parsedList = Array(arrayOfArray.length()) { i ->
                        Array(arrayOfArray.getJSONArray(i).length()) { j ->
                            arrayOfArray.getJSONArray(i).getDouble(j)
                        }
                    }

                    Handler(Looper.getMainLooper()).post {
                        callback(parsedList, null)
                    }
                } catch (_: Error) {
                    Handler(Looper.getMainLooper()).post {
                        callback(null, null)
                    }
                }
            }
        }
    }
}
