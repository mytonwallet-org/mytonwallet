package org.mytonwallet.app_air.walletsdk.methods

import com.squareup.moshi.JsonClass
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.walletsdk.WalletSDK
import org.mytonwallet.app_air.walletsdk.utils.NetworkUtils
import java.lang.reflect.Type

sealed class SDKApiMethod<T> {

    interface ApiCallback<T> {
        fun onSuccess(result: T)
        fun onError(error: Throwable)
    }

    enum class Service(val baseUrl: String) {
        MyTonWallet("https://api.mytonwallet.org/")
    }

    abstract val service: Service
    abstract val path: String
    abstract val method: NetworkUtils.Method
    abstract val responseType: Type

    object Common {
        class CurrencyRates() : SDKApiMethod<CurrencyRates>() {
            @JsonClass(generateAdapter = true)
            data class CurrencyRates(
                val rates: Map<String, Double>
            )

            override val service = Service.MyTonWallet
            override val path = "currency-rates"
            override val method = NetworkUtils.Method.GET
            override val responseType: Type = CurrencyRates::class.java
        }
    }

    object Token {
        class PriceChart(
            assetId: String,
            period: String,
            baseCurrency: String
        ) : SDKApiMethod<Array<Array<Double>>>() {
            override val service = Service.MyTonWallet
            override val path = "prices/chart/${assetId}?period=$period&base=$baseCurrency"
            override val method = NetworkUtils.Method.GET
            override val responseType: Type = Array<Array<Double>>::class.java
        }
    }

    fun call(callback: ApiCallback<T>) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val fullUrl = service.baseUrl + path
                val response = NetworkUtils.request(
                    urlString = fullUrl,
                    method = method
                )

                if (response != null) {
                    val moshi = WalletSDK.moshi
                    val adapter = moshi.adapter<T>(responseType).lenient()
                    val result = adapter.fromJson(response)

                    if (result != null) {
                        withContext(Dispatchers.Main) {
                            callback.onSuccess(result)
                        }
                    } else {
                        withContext(Dispatchers.Main) {
                            callback.onError(IllegalStateException("Failed to parse response: $response"))
                        }
                    }
                } else {
                    withContext(Dispatchers.Main) {
                        callback.onError(IllegalStateException("Network request failed"))
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback.onError(e)
                }
            }
        }
    }
}
