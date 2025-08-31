package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import java.math.BigInteger

// Base wallet class
@JsonClass(generateAdapter = true)
open class MApiBaseWallet(
    open val address: String,
    open val publicKey: String,
    open val index: Int
)

// Tron wallet
@JsonClass(generateAdapter = true)
data class MApiTronWallet(
    val type: String = "tron",
    override val address: String,
    override val publicKey: String,
    override val index: Int
) : MApiBaseWallet(address, publicKey, index)

// Ton wallet
@JsonClass(generateAdapter = true)
data class MApiTonWallet(
    val type: String = "ton",
    val version: String,
    override val address: String,
    override val publicKey: String,
    override val index: Int,
    val isInitialized: Boolean? = null,
    val authToken: String? = null
) : MApiBaseWallet(address, publicKey, index)

// Bip39 account
@JsonClass(generateAdapter = true)
data class MApiBip39Account(
    val type: String = "bip39",
    val mnemonicEncrypted: String,
    val tron: MApiTronWallet,
    val ton: MApiTonWallet
)

// Ton account
@JsonClass(generateAdapter = true)
data class MApiTonAccount(
    val type: String = "ton",
    val mnemonicEncrypted: String,
    val ton: MApiTonWallet
)

// Enum for ApiLedgerDriver
@JsonClass(generateAdapter = false)
enum class MApiLedgerDriver {
    @Json(name = "HID")
    HID,

    @Json(name = "USB")
    USB
}

// Ledger account
@JsonClass(generateAdapter = true)
data class MApiLedgerAccount(
    val type: String = "ledger",
    val ton: MApiTonWallet,
    val driver: MApiLedgerDriver,
    val deviceId: String? = null,
    val deviceName: String? = null
)

@JsonClass(generateAdapter = true)
data class MLedgerWalletInfo(
    val index: Int,
    val address: String,
    val publicKey: String,
    val balance: BigInteger,
    val version: MApiTonWalletVersion,
    val driver: MApiLedgerDriver,
    val deviceId: String? = null,
    val deviceName: String? = null
)

@JsonClass(generateAdapter = true)
data class MImportedWalletResponse(
    val accountId: String,
    val address: String,
    val walletInfo: MLedgerWalletInfo,
)
