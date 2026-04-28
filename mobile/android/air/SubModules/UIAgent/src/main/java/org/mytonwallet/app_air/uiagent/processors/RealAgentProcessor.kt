package org.mytonwallet.app_air.uiagent.processors

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.APP_SCHEME
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.io.BufferedInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class RealAgentProcessor : AgentProcessor {

    companion object {
        private const val BASE_URL = "https://agent.mytonwallet.org/api"
        private const val ENDPOINT = "$BASE_URL/message"
        private const val HINTS_ENDPOINT = "$BASE_URL/hints"
        private const val PLATFORM = "android"
        private const val CLIENT = "native"
        private val DEEPLINK_REGEX by lazy { Regex("""\[([^\]]+)]\(($APP_SCHEME://[^)\s]+)\)\s*$""") }
        private const val TAG = "RealAgentProcessor"
    }

    @Volatile
    private var clientId: String = loadOrCreateClientId()

    override suspend fun streamMessage(
        userId: String,
        message: String,
        userAddresses: List<AgentUserAddress>,
        savedAddresses: List<AgentUserAddress>,
        onEvent: (AgentStreamEvent) -> Unit,
        onDone: () -> Unit,
        onError: (Exception) -> Unit
    ) {
        withContext(Dispatchers.IO) {
            var connection: HttpURLConnection? = null
            try {
                val body = buildRequestBody(message, userAddresses, savedAddresses)
                Log.d(TAG, "Request: $body")

                val url = URL(ENDPOINT)
                connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doInput = true
                    doOutput = true
                    connectTimeout = 15_000
                    readTimeout = 120_000
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Accept", "text/plain")
                }

                val bytes = body.toByteArray(Charsets.UTF_8)
                connection.outputStream.use { it.write(bytes) }

                if (connection.responseCode !in 200..299) {
                    val errorBody = connection.errorStream?.bufferedReader()?.readText()
                    throw Exception(
                        errorBody?.takeIf { it.isNotBlank() }
                            ?: "Request failed with status ${connection.responseCode}"
                    )
                }

                val inputStream = BufferedInputStream(connection.inputStream)
                val buffer = ByteArray(4096)
                val allBytes = java.io.ByteArrayOutputStream()
                var lastEmitted = ""

                while (true) {
                    ensureActive()
                    val bytesRead = inputStream.read(buffer)
                    if (bytesRead == -1) break

                    allBytes.write(buffer, 0, bytesRead)
                    val decoded = try {
                        String(allBytes.toByteArray(), Charsets.UTF_8)
                    } catch (_: Exception) {
                        continue // partial UTF-8 byte, wait for more
                    }

                    if (decoded.length > lastEmitted.length && decoded.startsWith(lastEmitted)) {
                        val delta = decoded.substring(lastEmitted.length)
                        lastEmitted = decoded
                        onEvent(AgentStreamEvent.Chunk(delta))
                    }
                }

                // Parse deeplinks from final text
                val finalText = lastEmitted.trim()
                Log.d(TAG, "Response: $finalText")
                val match = DEEPLINK_REGEX.find(finalText)
                if (match != null) {
                    val title = match.groupValues[1]
                    val deeplink = match.groupValues[2]
                    val cleanText = finalText.removeRange(match.range).trim()

                    val result = AgentResult(
                        type = "deeplink",
                        message = cleanText,
                        deeplinks = listOf(AgentResultDeeplink(title = title, url = deeplink)),
                        raw = JSONObject()
                    )
                    onEvent(AgentStreamEvent.Results(listOf(result)))
                }

                onDone()
            } catch (e: Exception) {
                onError(e)
            } finally {
                connection?.disconnect()
            }
        }
    }

    private fun buildAddressesArray(addresses: List<AgentUserAddress>): JSONArray {
        val array = JSONArray()
        for (wallet in addresses) {
            array.put(JSONObject().apply {
                put("name", wallet.name)
                val addrsArray = JSONArray()
                wallet.addresses.forEach { addrsArray.put(it) }
                put("addresses", addrsArray)
                wallet.accountType?.let { put("accountType", it) }
                if (wallet.isActive) put("isActive", true)
            })
        }
        return array
    }

    private fun buildRequestBody(
        message: String,
        userAddresses: List<AgentUserAddress>,
        savedAddresses: List<AgentUserAddress>
    ): String {
        val context = JSONObject().apply {
            put("platform", PLATFORM)
            put("client", CLIENT)
            put("lang", LocaleController.activeLanguage.langCode)
            put("baseCurrency", WalletCore.baseCurrency.currencyCode)

            val userAddressesArray = buildAddressesArray(userAddresses)
            if (userAddressesArray.length() > 0) put("userAddresses", userAddressesArray)

            val savedAddressesArray = buildAddressesArray(savedAddresses)
            if (savedAddressesArray.length() > 0) put("savedAddresses", savedAddressesArray)

            val accountId = AccountStore.activeAccountId
            if (accountId != null) {
                val balancesMap = BalanceStore.getBalances(accountId)
                if (balancesMap != null && balancesMap.isNotEmpty()) {
                    val balancesArray = JSONArray()
                    for ((slug, balance) in balancesMap.entries.sortedBy { it.key }) {
                        balancesArray.put("$slug:$balance")
                    }
                    put("balances", balancesArray)
                }

                val tokensArray = JSONArray()
                for ((slug, _) in balancesMap?.entries?.sortedBy { it.key } ?: emptyList()) {
                    val token = TokenStore.getToken(slug) ?: continue
                    tokensArray.put(JSONArray().apply {
                        put(token.slug)
                        put(token.symbol)
                        put(token.name)
                        put(token.decimals.toString())
                        put(token.priceUsd.toString())
                    })
                }
                if (tokensArray.length() > 0) put("walletTokens", tokensArray)
            }
        }

        return JSONObject().apply {
            put("clientId", clientId)
            put("text", message)
            put("context", context)
        }.toString()
    }

    override suspend fun loadHints(langCode: String?): List<AgentHint> =
        withContext(Dispatchers.IO) {
            var connection: HttpURLConnection? = null
            try {
                val urlStr = buildString {
                    append(HINTS_ENDPOINT)
                    if (!langCode.isNullOrEmpty()) append("?langCode=$langCode")
                }
                connection = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    setRequestProperty("Accept", "application/json")
                }

                if (connection.responseCode !in 200..299) return@withContext emptyList()

                val body = connection.inputStream.bufferedReader().readText()
                val json = JSONObject(body)
                val items = json.optJSONArray("items") ?: return@withContext emptyList()
                (0 until items.length()).mapNotNull { i ->
                    val obj = items.getJSONObject(i)
                    val title = obj.optString("title", "").trim()
                    val subtitle = obj.optString("subtitle", "").trim()
                    val prompt = obj.optString("prompt", "").trim()
                    if (title.isEmpty() || subtitle.isEmpty() || prompt.isEmpty()) null
                    else AgentHint(
                        id = obj.optString("id", i.toString()),
                        title = title,
                        subtitle = subtitle,
                        prompt = prompt
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadHints failed", e)
                emptyList()
            } finally {
                connection?.disconnect()
            }
        }

    override fun resetClientId() {
        val newId = UUID.randomUUID().toString()
        WCacheStorage.setAgentClientId(newId)
        clientId = newId
    }

    private fun loadOrCreateClientId(): String {
        val existing = WCacheStorage.getAgentClientId()
        if (!existing.isNullOrEmpty()) return existing

        val newId = UUID.randomUUID().toString()
        WCacheStorage.setAgentClientId(newId)
        return newId
    }
}
