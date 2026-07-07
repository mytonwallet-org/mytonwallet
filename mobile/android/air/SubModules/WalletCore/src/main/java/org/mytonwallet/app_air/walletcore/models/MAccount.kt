package org.mytonwallet.app_air.walletcore.models

import android.net.Uri
import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.DNSHelpers
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiDerivation
import org.mytonwallet.app_air.walletcore.moshi.inject.ApiDappSessionChain
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
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
        val derivation: ApiDerivation? = null,
        val mfa: AccountMfa? = null,
    ) {
        val jsonObject: JSONObject
            get() {
                return JSONObject().apply {
                    put("address", address)
                    put("domain", domain)
                    put("isMultisig", isMultisig)
                    derivation?.let { put("derivation", it.toJSONObject()) }
                    mfa?.let { put("mfa", it.jsonObject) }
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
        AccountType.fromValue(globalJSON.optString("type")) ?: AccountType.MNEMONIC,
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
                    derivation = chainData.optJSONObject("derivation")?.let {
                        ApiDerivation.fromJSONObject(it)
                    },
                    mfa = chainData.optJSONObject("mfa")?.let { AccountMfa.fromJson(it) },
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
                    accountChain.derivation?.let { put("derivation", it.toJSONObject()) }
                    accountChain.mfa?.let { put("mfa", it.jsonObject) }
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

    val telegramAvatarUrl: String?
        get() {
            val tonChain = byChain["ton"]
            return DNSHelpers.telegramAvatarUrl(tonChain?.domain)
                ?: DNSHelpers.telegramAvatarUrl(tonChain?.address)
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

    val isMultisig: Boolean
        get() {
            return byChain.values.any { it.isMultisig == true }
        }

    val isMainnet: Boolean
        get() {
            return network.isMainnet
        }

    val addressByChain: Map<String, String>
        get() = byChain.mapValues { it.value.address }

    val supportsReceiveScreen: Boolean
        get() {
            return true
        }

    val supportsSwap: Boolean
        get() {
            return isMainnet && accountType == AccountType.MNEMONIC
        }

    val supportsWalletConnectPay: Boolean
        get() {
            return accountType == AccountType.MNEMONIC && isMultichain
        }

    val supportsBuyWithCard: Boolean
        get() {
            return isMainnet && accountType != AccountType.VIEW
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
        get() = BalanceStore.isAccountNew(accountId)

    val firstChain: MBlockchain?
        get() {
            val firstSorted = sortedChains().firstOrNull()?.key ?: return null
            return MBlockchain.supportedChains.firstOrNull { it.name == firstSorted }
        }

    val shareLink: String
        get() {
            val sortedChains = sortedChains()
            val evmAddress = collapsedEvmAddress(sortedChains)
            var didAddEvm = false

            return Uri.Builder()
                .scheme("https")
                .authority(ApplicationContextHolder.universalShortUrlHost)
                .path("view/")
                .apply {
                    sortedChains.forEach { (chain, chainAccount) ->
                        if (evmAddress != null && MBlockchain.isEvmChain(chain)) {
                            if (!didAddEvm) {
                                appendQueryParameter(MBlockchain.VIEW_ACCOUNT_EVM_PARAM, evmAddress)
                                didAddEvm = true
                            }
                            return@forEach
                        }

                        appendQueryParameter(chain, chainAccount.address)
                    }

                    if (network.isTestnet) {
                        appendQueryParameter("testnet", "true")
                    }
                }
                .build()
                .toString()
        }

    private fun collapsedEvmAddress(sortedChains: List<Map.Entry<String, AccountChain>>): String? {
        val addressByChain = sortedChains.associate { it.key to it.value.address }
        val evmAddresses = MBlockchain.evmChains.map { addressByChain[it.name] }
        val firstAddress = evmAddresses.firstOrNull() ?: return null
        return if (evmAddresses.all { it == firstAddress }) firstAddress else null
    }

    fun isChainSupported(chain: String): Boolean {
        return byChain.containsKey(chain)
    }

    fun supports(requiredChains: List<ApiDappSessionChain>): Boolean {
        if (requiredChains.isEmpty()) return true
        return requiredChains.all { isChainSupported(it.chain) }
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
