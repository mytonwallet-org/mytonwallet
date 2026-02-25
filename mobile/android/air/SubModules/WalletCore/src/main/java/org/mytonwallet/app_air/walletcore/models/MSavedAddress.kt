package org.mytonwallet.app_air.walletcore.models

import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.WalletCore

@JsonClass(generateAdapter = true)
data class MSavedAddress(
    val address: String,
    var name: String,
    val chain: String,
    val domain: String? = null,
    @Transient val accountId: String? = null
) {

    companion object {
        fun fromJson(jsonObject: JSONObject): MSavedAddress? {
            val adapter = WalletCore.moshi.adapter(MSavedAddress::class.java)
            return adapter.fromJson(jsonObject.toString())
        }
    }

    fun toDictionary(): JSONObject {
        val adapter = WalletCore.moshi.adapter(MSavedAddress::class.java)
        return JSONObject(adapter.toJson(this))
    }

    val isAccountAddress: Boolean
        get() {
            return accountId != null
        }
}
