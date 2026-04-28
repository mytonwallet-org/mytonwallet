package org.mytonwallet.app_air.walletcore.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

enum class HttpMethod(val value: String) {
    GET("GET"),
    POST("POST"),
    PUT("PUT"),
    DELETE("DELETE"),
}

data class NetworkRequest(
    val url: String,
    val method: HttpMethod = HttpMethod.GET,
    val headers: Map<String, String> = emptyMap(),
    val body: String? = null,
    val connectTimeoutMs: Int = 15_000,
    val readTimeoutMs: Int = 30_000,
    val writeTimeoutMs: Int = 30_000,
    val callTimeoutMs: Int = 45_000,
    val retryCount: Int = 0,
    val retryDelayMs: Long = 0L,
    val retryOnConnectionFailure: Boolean = true,
)

data class NetworkResponse(
    val statusCode: Int,
    val body: String,
    val headers: Map<String, List<String>>,
) {
    val isSuccessful: Boolean
        get() = statusCode in 200..299
}

object NetworkClient {
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    private val defaultClient = OkHttpClient()
    private val clients = ConcurrentHashMap<ClientConfig, OkHttpClient>()

    suspend fun request(request: NetworkRequest): NetworkResponse = withContext(Dispatchers.IO) {
        executeWithRetry(request)
    }

    fun execute(request: NetworkRequest): NetworkResponse {
        return executeOnce(request)
    }

    private suspend fun executeWithRetry(request: NetworkRequest): NetworkResponse {
        var lastException: IOException? = null

        repeat(request.retryCount + 1) { attempt ->
            currentCoroutineContext().ensureActive()
            try {
                return executeOnce(request)
            } catch (e: IOException) {
                lastException = e
                if (attempt == request.retryCount) {
                    throw e
                }
                if (request.retryDelayMs > 0) {
                    delay(request.retryDelayMs * (attempt + 1))
                }
            }
        }

        throw lastException ?: IOException("Network request failed")
    }

    private fun executeOnce(request: NetworkRequest): NetworkResponse {
        val client = getClient(request)

        val requestBody = when (request.method) {
            HttpMethod.GET -> null
            HttpMethod.DELETE -> request.body?.toRequestBody(jsonMediaType)
            HttpMethod.POST,
            HttpMethod.PUT -> (request.body ?: "").toRequestBody(jsonMediaType)
        }
        val okhttpRequest = Request.Builder()
            .url(request.url)
            .header("Accept", "application/json")
            .method(request.method.value, requestBody)
            .apply {
                request.headers.forEach { (key, value) ->
                    header(key, value)
                }
            }
            .build()

        client.newCall(okhttpRequest).execute().use { response ->
            return NetworkResponse(
                statusCode = response.code,
                body = response.body.string(),
                headers = response.headers.toMultimap(),
            )
        }
    }

    private fun getClient(request: NetworkRequest): OkHttpClient {
        val config = ClientConfig(
            connectTimeoutMs = request.connectTimeoutMs,
            readTimeoutMs = request.readTimeoutMs,
            writeTimeoutMs = request.writeTimeoutMs,
            callTimeoutMs = request.callTimeoutMs,
            retryOnConnectionFailure = request.retryOnConnectionFailure,
        )

        return clients.computeIfAbsent(config) {
            defaultClient.newBuilder()
                .connectTimeout(config.connectTimeoutMs.toLong(), TimeUnit.MILLISECONDS)
                .readTimeout(config.readTimeoutMs.toLong(), TimeUnit.MILLISECONDS)
                .writeTimeout(config.writeTimeoutMs.toLong(), TimeUnit.MILLISECONDS)
                .callTimeout(config.callTimeoutMs.toLong(), TimeUnit.MILLISECONDS)
                .retryOnConnectionFailure(config.retryOnConnectionFailure)
                .build()
        }
    }

    private data class ClientConfig(
        val connectTimeoutMs: Int,
        val readTimeoutMs: Int,
        val writeTimeoutMs: Int,
        val callTimeoutMs: Int,
        val retryOnConnectionFailure: Boolean,
    )
}
