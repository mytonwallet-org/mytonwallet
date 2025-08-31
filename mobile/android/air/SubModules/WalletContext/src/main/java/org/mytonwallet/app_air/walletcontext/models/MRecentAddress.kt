package org.mytonwallet.app_air.walletcontext.models

import org.json.JSONObject
import java.util.Date

class MRecentAddress(val address: String, val addressAlias: String, val dt: Date = Date()) :
    WStoringObject() {

    constructor(jsonObject: JSONObject) :
        this(
            jsonObject.optString(KEY_ADDRESS),
            jsonObject.optString(KEY_ADDRESS_ALIAS),
            Date(jsonObject.optLong(KEY_TIMESTAMP))
        )

    companion object {
        private const val KEY_ADDRESS = "address"
        private const val KEY_ADDRESS_ALIAS = "addressAlias"
        private const val KEY_TIMESTAMP = "timestamp"
    }

    override fun toJSONObject(): JSONObject {
        return JSONObject().apply {
            put(KEY_ADDRESS, address)
            put(KEY_ADDRESS_ALIAS, addressAlias)
            put(KEY_TIMESTAMP, dt.time)
        }
    }
}
