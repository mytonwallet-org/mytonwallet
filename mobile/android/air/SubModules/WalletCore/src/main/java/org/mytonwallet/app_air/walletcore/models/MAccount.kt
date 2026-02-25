package org.mytonwallet.app_air.walletcore.models

import android.net.Uri
import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.DEFAULT_SHOWN_TOKENS
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.inject.ApiDappSessionChain
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletcore.utils.sortedByBalance

@JsonClass(generateAdapter = true)
class MAccount(
    var accountId: String,
    var byChain: Map<String, AccountChain>,
    var name: String,
    var accountType: AccountType,
    var importedAt: Long?,
    var isTemporary: Boolean,
) {

    override fun equals(other: Any?): Boolean {
        return other is MAccount && other.accountId == this.accountId
    }

    override fun hashCode(): Int = accountId.hashCode()

    @JsonClass(generateAdapter = true)
    data class AccountChain(
        val address: String,
        val domain: String? = null,
        val isMultisig: Boolean? = null,
    ) {
        val jsonObject: JSONObject
            get() {
                return JSONObject().apply {
                    put("address", address)
                    put("domain", domain)
                    put("isMultisig", isMultisig)
                }
            }
    }

    @JsonClass(generateAdapter = false)
    enum class AccountType(val value: String) {
        MNEMONIC("mnemonic"),
        HARDWARE("hardware"),
        VIEW("view");

        companion object {
            fun fromValue(value: String): AccountType? = entries.find { it.value == value }
        }
    }

    val isViewOnly: Boolean
        get() {
            return accountType == AccountType.VIEW
        }

    @JsonClass(generateAdapter = true)
    data class Ledger(val driver: Driver, val index: Int) {
        @JsonClass(generateAdapter = false)
        enum class Driver(val value: String) {
            HID("HID"),
        }

        constructor(json: JSONObject) : this(
            Driver.valueOf(json.optString("driver")),
            json.optInt("index")
        )
    }

    val network: MBlockchainNetwork = MBlockchainNetwork.ofAccountId(accountId)

    init {
        if (name.isEmpty()) {
            name = WGlobalStorage.getAccountName(accountId) ?: ""
        }
    }

    constructor(accountId: String, globalJSON: JSONObject) : this(
        accountId,
        parseByChain(globalJSON.optJSONObject("byChain")),
        globalJSON.optString("title"),
        AccountType.fromValue(globalJSON.optString("type"))!!,
        globalJSON.optLong("importedAt"),
        globalJSON.optBoolean("isTemporary"),
    )

    companion object {
        fun parseByChain(byChainJson: JSONObject?): Map<String, AccountChain> {
            val result = mutableMapOf<String, AccountChain>()
            byChainJson?.keys()?.forEach { chain ->
                val chainData = byChainJson.getJSONObject(chain)
                result[chain] = AccountChain(
                    address = chainData.getString("address"),
                    domain = chainData.optString("domain").takeIf { it.isNotEmpty() },
                    isMultisig = chainData.optBoolean("isMultisig")
                        .takeIf { chainData.has("isMultisig") },
                )
            }
            return result
        }

        fun byChainToJson(byChain: Map<String, AccountChain>): JSONObject {
            val json = JSONObject()
            byChain.forEach { (chainName, accountChain) ->
                val chain = JSONObject().apply {
                    put("address", accountChain.address)
                    accountChain.domain?.let { put("domain", it) }
                    accountChain.isMultisig?.let { put("isMultisig", it) }
                }
                json.put(chainName, chain)
            }
            return json
        }
    }

    val isHardware: Boolean
        get() {
            return accountType == AccountType.HARDWARE
        }

    val tonAddress: String?
        get() {
            return byChain["ton"]?.address
        }

    val tronAddress: String?
        get() {
            return byChain["tron"]?.address
        }

    val firstAddress: String?
        get() {
            return if (tonAddress != null)
                tonAddress
            else {
                try {
                    byChain.entries.first().value.address
                } catch (_: Exception) {
                    null
                }
            }
        }

    val isMultichain: Boolean
        get() {
            return byChain.keys.size > 1
        }

    val addressByChain: Map<String, String>
        get() = byChain.mapValues { it.value.address }

    val supportsSwap: Boolean
        get() {
            return network == MBlockchainNetwork.MAINNET && accountType == AccountType.MNEMONIC
        }

    val supportsBuyWithCard: Boolean
        get() {
            return network == MBlockchainNetwork.MAINNET && accountType != AccountType.VIEW
        }

    val supportsBuyWithCrypto: Boolean
        get() {
            return supportsSwap
        }

    val supportsCommentEncryption: Boolean
        get() {
            return accountType == AccountType.MNEMONIC
        }

    val isNew: Boolean
        get() {
            val balances = BalanceStore.getBalances(accountId) ?: return false
            return balances.size <= (DEFAULT_SHOWN_TOKENS[network]?.size ?: 0) && balances.filter {
                val token = TokenStore.getToken(it.key) ?: return@filter false
                return@filter token.priceUsd *
                    it.value.doubleAbsRepresentation(token.decimals) >= 0.01
            }.isEmpty()
        }

    val firstChain: MBlockchain?
        get() {
            return MBlockchain.supportedChains.firstOrNull { addressByChain.contains(it.name) }
        }

    val shareLink: String
        get() {
            return Uri.Builder()
                .scheme("https")
                .authority("my.tt")
                .path("view/")
                .apply {
                    sortedChains().forEach { (chain, chainAccount) ->
                        appendQueryParameter(chain, chainAccount.address)
                    }

                    if (network == MBlockchainNetwork.TESTNET) {
                        appendQueryParameter("testnet", "true")
                    }
                }
                .build()
                .toString()
        }

    fun isChainSupported(chain: String): Boolean {
        return byChain.containsKey(chain)
    }

    fun dappChain(chain: String): ApiDappSessionChain? {
        val address = byChain[chain]?.address ?: return null
        return ApiDappSessionChain(
            chain = chain,
            address = address,
            network = network.value
        )
    }

    fun sortedChains(): List<Map.Entry<String, AccountChain>> {
        val perChainBalance = BalanceStore.totalBalanceInBaseCurrencyPerChain(accountId)
        return byChain.sortedByBalance(perChainBalance)
    }
}
