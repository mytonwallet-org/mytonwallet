package org.mytonwallet.app_air.walletcore.api

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError

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
            scope.launch {
                try {
                    val arrayOfArray = JSONArray(result)
                    val parsedList = Array(arrayOfArray.length()) { i ->
                        Array(arrayOfArray.getJSONArray(i).length()) { j ->
                            arrayOfArray.getJSONArray(i).getDouble(j)
                        }
                    }

                    withContext(Dispatchers.Main) {
                        callback(parsedList, null)
                    }
                } catch (_: Error) {
                    withContext(Dispatchers.Main) {
                        callback(null, null)
                    }
                }
            }
        }
    }
}
