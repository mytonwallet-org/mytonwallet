package org.mytonwallet.app_air.walletcore.models

import com.squareup.moshi.JsonClass
import org.json.JSONObject

@JsonClass(generateAdapter = true)
data class AccountMfa(
    val address: String,
    val user: User? = null,
) {
    @JsonClass(generateAdapter = true)
    data class User(
        val id: String? = null,
        val name: String,
        val username: String? = null,
        val avatarUrl: String? = null,
    ) {
        val jsonObject: JSONObject
            get() = JSONObject().apply {
                id?.let { put("id", it) }
                put("name", name)
                username?.let { put("username", it) }
                avatarUrl?.let { put("avatarUrl", it) }
            }

        companion object {
            fun fromJson(json: JSONObject): User {
                return User(
                    id = json.optString("id").takeIf { it.isNotEmpty() },
                    name = json.optString("name"),
                    username = json.optString("username").takeIf { it.isNotEmpty() },
                    avatarUrl = json.optString("avatarUrl").takeIf { it.isNotEmpty() },
                )
            }
        }
    }

    val jsonObject: JSONObject
        get() = JSONObject().apply {
            put("address", address)
            user?.let { put("user", it.jsonObject) }
        }

    companion object {
        fun fromJson(json: JSONObject): AccountMfa {
            return AccountMfa(
                address = json.getString("address"),
                user = json.optJSONObject("user")?.let { User.fromJson(it) },
            )
        }
    }
}
