package org.mytonwallet.app_air.walletcore.models

import org.json.JSONObject
import java.math.BigInteger

class MApiTransactionDraft(json: JSONObject) {
    val fee: BigInteger? = json.optString("fee")?.let {
        BigInteger(it.substringAfter("bigint:"))
    }
    val addressName: String? = json.optString("addressName", null)
    val isScam: Boolean? = json.optBoolean("isScam", false).takeIf { it != false }
    val resolvedAddress: String? = json.optString("resolvedAddress", null)
    val isToAddressNew: String? = json.optString("isToAddressNew", null)
    val isBounceable: Boolean? = json.optBoolean("isBounceable", false).takeIf { it != false }

}
