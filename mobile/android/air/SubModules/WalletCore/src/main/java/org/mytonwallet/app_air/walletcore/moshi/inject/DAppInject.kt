package org.mytonwallet.app_air.walletcore.moshi.inject

import com.squareup.moshi.JsonClass
import org.json.JSONArray

object DAppInject {
    @JsonClass(generateAdapter = true)
    data class FunctionInvoke(
        val invocationId: String,
        val name: String,
        val args: JSONArray?
    )

    @JsonClass(generateAdapter = true)
    data class FunctionInvokeInvokeResult(
        val type: String,
        val invocationId: String,
        val status: String,
        val data: Any?
    )
}
