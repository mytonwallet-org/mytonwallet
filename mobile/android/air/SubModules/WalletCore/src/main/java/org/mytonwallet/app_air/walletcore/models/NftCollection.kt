package org.mytonwallet.app_air.walletcore.models

import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.WalletCore

@JsonClass(generateAdapter = true)
data class NftCollection(
    val address: String,
    val name: String
) {
    companion object {
        const val TELEGRAM_GIFTS_SUPER_COLLECTION = "super:telegram-gifts"

        fun fromJson(jsonObject: JSONObject): NftCollection? {
            val adapter = WalletCore.moshi.adapter(NftCollection::class.java)
            return adapter.fromJson(jsonObject.toString())
        }
    }

    fun toDictionary(): JSONObject {
        val adapter = WalletCore.moshi.adapter(NftCollection::class.java)
        return JSONObject(adapter.toJson(this))
    }
}
