package org.mytonwallet.app_air.walletcore.models

import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletcore.DEFAULT_SHOWN_TOKENS
import org.mytonwallet.app_air.walletcore.MAIN_NETWORK
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class MAccount(
    var accountId: String,
    val addressByChain: Map<String, String>,
    var name: String,
    var accountType: AccountType,
    val ledger: Ledger?,
    var importedAt: Long?,
) {

    enum class AccountType(val value: String) {
        MNEMONIC("mnemonic"),
        HARDWARE("hardware"),
        VIEW("view");

        companion object {
            fun fromValue(value: String): AccountType? = entries.find { it.value == value }
        }

        val isPasscodeProtected: Boolean
            get() {
                return this == MNEMONIC
            }

        val badge: String?
            get() {
                return when (this) {
                    MNEMONIC -> null
                    HARDWARE -> "LEDGER"
                    VIEW -> "VIEW"
                }
            }
    }

    val isPasscodeProtected: Boolean
        get() {
            return accountType.isPasscodeProtected
        }

    data class Ledger(val driver: Driver, val index: Int) {
        enum class Driver(val value: String) {
            HID("HID"),
        }

        constructor(json: JSONObject) : this(
            Driver.valueOf(json.optString("driver")),
            json.optInt("index")
        )
    }

    init {
        if (name.isEmpty()) {
            name = WGlobalStorage.getAccountName(accountId) ?: ""
        }
    }

    constructor(accountId: String, globalJSON: JSONObject) : this(
        accountId,
        mapOf(
            "ton" to (globalJSON.optJSONObject("addressByChain")?.optString("ton") ?: ""),
            "tron" to (globalJSON.optJSONObject("addressByChain")?.optString("tron") ?: ""),
        ).filterValues { it.isNotEmpty() },
        globalJSON.optString("title"),
        AccountType.fromValue(globalJSON.optString("type"))!!,
        globalJSON.optJSONObject("ledger")?.let { Ledger(it) },
        globalJSON.optLong("importedAt"),
    )

    val isHardware: Boolean
        get() {
            return accountType == AccountType.HARDWARE
        }

    val tonAddress: String?
        get() {
            return addressByChain["ton"]
        }

    val tronAddress: String?
        get() {
            return addressByChain["tron"]
        }

    val firstAddress: String?
        get() {
            return if (tonAddress != null)
                tonAddress
            else {
                try {
                    addressByChain.entries.first().value
                } catch (e: Exception) {
                    null
                }
            }
        }

    val isMultichain: Boolean
        get() {
            return addressByChain.keys.size > 1 || tonAddress == null
        }

    val supportsSwap: Boolean
        get() {
            return WalletCore.activeNetwork == MAIN_NETWORK && accountType == AccountType.MNEMONIC
        }

    val supportsBuyWithCard: Boolean
        get() {
            return WalletCore.activeNetwork == MAIN_NETWORK && accountType != AccountType.VIEW
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
            return balances.size <= DEFAULT_SHOWN_TOKENS.size && balances.filter {
                val token = TokenStore.getToken(it.key) ?: return@filter false
                return@filter token.priceUsd *
                    it.value.doubleAbsRepresentation(token.decimals) >= 0.01
            }.isEmpty()
        }
}
