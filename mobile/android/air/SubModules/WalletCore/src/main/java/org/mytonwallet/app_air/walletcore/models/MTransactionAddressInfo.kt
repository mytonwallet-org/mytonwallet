package org.mytonwallet.app_air.walletcore.models

import org.json.JSONObject

class MApiTransactionAddressInfo(json: JSONObject?) {
    val name: String? = json?.optString("name")
    val isScam: Boolean? = json?.optBoolean("isScam")
}
