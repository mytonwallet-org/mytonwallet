package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.models.MAccount.AccountChain
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class ApiDerivation(
    val path: String,
    val index: Int,
    val label: String? = null
) {
    fun toJSONObject(): JSONObject = JSONObject().apply {
        put("path", path)
        put("index", index)
        label?.let { put("label", it) }
    }

    companion object {
        fun fromJSONObject(json: JSONObject): ApiDerivation? {
            val path = json.optString("path").takeIf { it.isNotEmpty() } ?: return null
            val index = json.optInt("index", -1).takeIf { it >= 0 } ?: return null
            val label = json.optString("label").takeIf { it.isNotEmpty() }
            return ApiDerivation(path = path, index = index, label = label)
        }
    }
}

@JsonClass(generateAdapter = true)
data class ApiSubWallet(
    val address: String,
    val publicKey: String? = null,
    val version: String? = null,
    val isInitialized: Boolean? = null,
    val derivation: ApiDerivation? = null
)

@JsonClass(generateAdapter = true)
data class ApiWalletVariantMetadata(
    val type: String,
    val version: String? = null,
    val path: String? = null,
    val label: String? = null
)

@JsonClass(generateAdapter = true)
data class ApiWalletVariant(
    val chain: String,
    val wallet: ApiSubWallet,
    val balance: BigInteger,
    val metadata: ApiWalletVariantMetadata
)

@JsonClass(generateAdapter = true)
data class ApiGroupedWalletVariantEntry(
    val wallet: ApiSubWallet,
    val balance: BigInteger,
    val hasDerivation: Boolean
)

@JsonClass(generateAdapter = true)
data class ApiGroupedWalletVariant(
    val index: Int,
    val totalBalance: BigInteger,
    val byChain: Map<String, ApiGroupedWalletVariantEntry>
)

@JsonClass(generateAdapter = true)
data class ApiCreateSubWalletResult(
    val isNew: Boolean,
    val accountId: String,
    val address: String? = null,
    val byChain: Map<String, AccountChain>? = null
)

@JsonClass(generateAdapter = true)
data class ApiAddSubWalletResult(
    val address: String?,
    val accountId: String? = null,
    val byChain: Map<String, AccountChain>? = null
)
