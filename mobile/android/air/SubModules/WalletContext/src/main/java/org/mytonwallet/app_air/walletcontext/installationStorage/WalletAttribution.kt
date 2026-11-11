package org.mytonwallet.app_air.walletcontext.installationStorage

import com.squareup.moshi.JsonClass
import org.json.JSONObject

@JsonClass(generateAdapter = true)
data class WalletAttributionSource(
    val channel: String,
    val attributionKind: String,
    val referrerDomain: String? = null,
    val utmMedium: String? = null,
    val utmCampaign: String? = null,
    val utmContent: String? = null,
    val legacy: Boolean? = null
) {
    init {
        require(legacy == null || legacy)
        if (legacy == true) {
            require(attributionKind == "utm" && Regex("[a-z0-9_]{1,64}").matches(channel))
            require(listOf(referrerDomain, utmMedium, utmCampaign, utmContent).all { it == null })
        } else {
            require(attributionKind in setOf("utm", "referrer"))
            SourceSnapshot(
                channel,
                attributionKind,
                if (attributionKind == "utm") "utm" else "external_referrer",
                referrerDomain,
                utmMedium,
                utmCampaign,
                utmContent
            )
        }
    }

    fun json() = JSONObject(walletSourceAdapter.toJson(this))
}

private val walletSourceAdapter = storageMoshi.adapter(
    WalletAttributionSource::class.java
).failOnUnknown()
internal val attributionValueAdapter = storageMoshi.adapter(Any::class.java)

fun parseWalletAttributionSource(json: String?): WalletAttributionSource? {
    val value = json?.let(attributionValueAdapter::fromJson) ?: return null
    require(value is Map<*, *>)
    require(value["channel"] is String && value["attributionKind"] is String)
    require(
        value.all { (key, field) ->
            if (key ==
                "legacy"
            ) {
                field == null || field == true
            } else {
                field == null || field is String
            }
        }
    )
    return requireNotNull(walletSourceAdapter.fromJsonValue(value))
}

internal fun SourceSnapshot.walletSource(): WalletAttributionSource? =
    if (attributionKind in setOf("utm", "referrer")) {
        WalletAttributionSource(
            channel,
            attributionKind,
            referrerDomain,
            utmMedium,
            utmCampaign,
            utmContent
        )
    } else {
        null
    }

internal fun selectWalletSource(
    previous: WalletAttributionSource?,
    candidate: WalletAttributionSource?
): WalletAttributionSource? = when {
    previous == null -> candidate
    previous.attributionKind == "referrer" && candidate?.attributionKind == "utm" -> candidate
    else -> previous
}

@JsonClass(generateAdapter = true)
data class WalletAttributionProjection(
    val initialized: Boolean,
    val source: WalletAttributionSource?
) {
    fun capture(candidate: WalletAttributionSource?) =
        copy(source = selectWalletSource(source, candidate))

    fun initialize(
        seed: WalletAttributionSource?,
        pending: WalletAttributionSource?
    ): WalletAttributionProjection {
        if (initialized) return this
        val authoritative = selectWalletSource(seed, pending)
        return copy(initialized = true, source = selectWalletSource(authoritative, source))
    }
}
