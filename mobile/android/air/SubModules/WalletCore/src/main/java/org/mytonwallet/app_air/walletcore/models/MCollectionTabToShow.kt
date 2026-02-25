package org.mytonwallet.app_air.walletcore.models

import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.models.ICollectionTab
import org.mytonwallet.app_air.walletcore.WalletCore

@JsonClass(generateAdapter = true)
data class MCollectionTabToShow(
    override val chain: String = "ton",
    override val address: String,
    val name: String
) : ICollectionTab {

    companion object {
        fun fromJson(jsonObject: JSONObject): MCollectionTabToShow? {
            val adapter = WalletCore.moshi.adapter(MCollectionTabToShow::class.java)
            return adapter.fromJson(jsonObject.toString())
        }
    }

    fun toDictionary(): JSONObject {
        val adapter = WalletCore.moshi.adapter(MCollectionTabToShow::class.java)
        return JSONObject(adapter.toJson(this))
    }
}
