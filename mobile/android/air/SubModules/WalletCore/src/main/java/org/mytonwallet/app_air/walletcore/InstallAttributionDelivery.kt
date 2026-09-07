package org.mytonwallet.app_air.walletcore

import android.content.Context
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

// The native journal owns a snapshot only until the SDK confirms durable storage acceptance.
class PendingInstallAttribution(
    read: () -> InstallAttribution?,
    private val write: (InstallAttribution?) -> Boolean,
    private val ready: () -> Boolean,
    private val send: (InstallAttribution, (Boolean) -> Unit) -> Unit
) {
    var pending: InstallAttribution? = read()
        private set
    private var generation = 0
    private var sendingGeneration: Int? = null

    fun capture(snapshot: InstallAttribution) {
        if (pending == null ||
            (pending?.referrerDomain != null && snapshot.referrerDomain == null)
        ) {
            if (!write(snapshot)) return
            pending = snapshot
        }
        flush()
    }

    fun bridgeReady() {
        generation++
        flush()
    }

    private fun flush() {
        val selected = pending ?: return
        if (!ready() || sendingGeneration == generation) return
        val selectedGeneration = generation
        sendingGeneration = selectedGeneration
        send(selected) { accepted ->
            if (selectedGeneration != generation) return@send
            sendingGeneration = null
            if (pending != selected) {
                flush()
            } else if (accepted && write(null)) {
                pending = null
            }
        }
    }
}

object InstallAttributionDelivery {
    private val preferences by lazy {
        ApplicationContextHolder.applicationContext.getSharedPreferences(
            "installAttribution",
            Context.MODE_PRIVATE
        )
    }
    private val journal by lazy {
        PendingInstallAttribution(
            read = {
                runCatching {
                    val value =
                        JSONObject(
                            preferences.getString("pending", null) ?: return@runCatching null
                        )
                    fun field(key: String) = value.optString(key).takeIf { it.isNotEmpty() }
                    InstallAttribution(
                        value.getString("channel"),
                        field("referrerDomain"),
                        field("utmMedium"),
                        field("utmCampaign"),
                        field("utmContent")
                    )
                }.getOrNull()
            },
            write = { snapshot ->
                val editor = preferences.edit()
                if (snapshot ==
                    null
                ) {
                    editor.remove("pending")
                } else {
                    editor.putString("pending", snapshot.toJson().toString())
                }
                editor.commit()
            },
            ready = { WalletCore.isBridgeReady },
            send = { snapshot, complete ->
                WalletCore.call(ApiMethod.Other.CaptureInstallAttribution(snapshot.toJson())) {
                        accepted,
                        error
                    ->
                    complete(error == null && accepted == true)
                }
            }
        )
    }

    fun capture(snapshot: InstallAttribution) = journal.capture(snapshot)
    fun bridgeReady() = journal.bridgeReady()
}
