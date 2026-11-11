package org.mytonwallet.app_air.walletcontext.installationStorage

import android.content.Context
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage

object WalletAttributionMigration {
    private val lock = Any()
    private val invalidValue = Any()
    private const val SEED = "walletSourceBeforeClear"
    private const val COMPLETE = "walletSourceMigrationComplete"

    fun beforeClear() {
        runCatching {
            val context = ApplicationContextHolder.applicationContext
            val preferences = context.getSharedPreferences(
                "installAttribution",
                Context.MODE_PRIVATE
            )
            fun captured() = preferences.contains(SEED) || preferences.all[COMPLETE] == true
            if (synchronized(lock) { captured() }) return
            val sdk = context.getSharedPreferences("airSdk", Context.MODE_PRIVATE)
            fun read(key: String): Any? {
                val raw = if (sdk.contains(
                        key
                    )
                ) {
                    sdk.getString(key, null)
                } else {
                    WSecureStorage.getSecValue(key)
                }
                return raw?.takeIf { it.isNotEmpty() }?.let {
                    runCatching { attributionValueAdapter.fromJson(it) }.getOrDefault(invalidValue)
                }
            }
            val saved = read("installAttribution")
            val source = if (saved != null && saved != false && saved != 0.0 && saved != "") {
                normalizeSavedWalletSource(saved)
            } else {
                (read("attributionChannel") as? String)?.let { channel ->
                    runCatching {
                        WalletAttributionSource(channel, "utm", legacy = true)
                    }.getOrNull()
                }
            }
            synchronized(lock) {
                if (!captured()) {
                    preferences.edit().putString(
                        SEED,
                        source?.json()?.toString() ?: "null"
                    ).commit()
                }
            }
        }
    }

    fun synchronize(
        context: Context,
        seed: String?,
        commit: (String?, String?) -> JSONObject
    ): JSONObject {
        val preferences = context.getSharedPreferences("installAttribution", Context.MODE_PRIVATE)
        val (capturedSeed, pending) = synchronized(lock) {
            val selected = if (preferences.contains(
                    SEED
                )
            ) {
                preferences.all[SEED] as? String
            } else {
                seed
            }
            selected to (preferences.all["pending"] as? String)
        }
        val result = commit(capturedSeed, pending)
        synchronized(lock) {
            preferences.edit().remove(SEED).remove("pending").putBoolean(COMPLETE, true).commit()
        }
        return result
    }
}

internal fun normalizeSavedWalletSource(value: Any?): WalletAttributionSource? {
    val input = value as? Map<*, *> ?: return null
    val channel = input["channel"] as? String ?: return null
    return runCatching {
        if (input["legacy"] == true) {
            WalletAttributionSource(channel, "utm", legacy = true)
        } else if (input["attributionKind"] == "referrer") {
            require(channel == "" || channel == "web_referral")
            WalletAttributionSource(
                "",
                "referrer",
                (input["referrerDomain"] as? String)?.lowercase()?.removeSuffix(".")
            )
        } else {
            require(input["attributionKind"] == null || input["attributionKind"] == "utm")
            fun detail(key: String): String? = (input[key] as? String)?.let { raw ->
                raw.trim().takeIf { text ->
                    text.isNotEmpty() && text.toByteArray().size <= 128 &&
                        raw.none { it.code in 0..31 || it.code in 127..159 }
                }
            }
            WalletAttributionSource(
                channel.trim().lowercase(),
                "utm",
                utmMedium = detail("utmMedium"),
                utmCampaign = detail("utmCampaign"),
                utmContent = detail("utmContent")
            )
        }
    }.getOrNull()
}
