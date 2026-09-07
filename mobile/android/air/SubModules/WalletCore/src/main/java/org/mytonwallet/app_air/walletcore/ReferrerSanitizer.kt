package org.mytonwallet.app_air.walletcore

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcore.deeplink.Deeplink

// Keys parsed from the referrer. `r` (swap referrerId) is here only so a referrer
// carrying it parses cleanly; explicit channels use `utm_source`, inferred domains use `attribution_referrer`.
private val REFERRER_PARSE_KEYS = setOf(
    "clickId",
    "r",
    "utm_source",
    "attribution_kind",
    "utm_medium",
    "utm_campaign",
    "utm_content",
    "attribution_referrer"
)

// Input-safety guard for one decoded value. Looser than the canonical slug guard
// below: it allows the hyphen in the Play "google-play" organic marker.
private val REFERRER_VALUE_PATTERN = Regex("^[A-Za-z0-9._~-]{1,64}$")

// A canonical channel bucket slug, e.g. "wc", "tg_channel", "app_share".
private val CANONICAL_SLUG_PATTERN = Regex("^[a-z0-9_]{1,30}$")

private const val ORGANIC_UTM_SOURCE = "google-play"
private const val ORGANIC_UTM_MEDIUM = "organic"
private const val CHANNEL_ORGANIC = "organic"
private const val CHANNEL_UNKNOWN = "unknown"

/**
 * Resolve the channel from an untrusted Play Install Referrer into a canonical bucket, never null:
 * `organic` for the Google Play organic marker, the `utm_source` slug when well-formed, or
 * `unknown` when absent, empty or malformed. Enforces input safety only; the JS claim path
 * re-validates the source and preserves arbitrary well-formed slugs server-side.
 */
data class InstallAttribution(
    val channel: String,
    val referrerDomain: String? = null,
    val utmMedium: String? = null,
    val utmCampaign: String? = null,
    val utmContent: String? = null,
    val isTechnical: Boolean = false,
    val technicalKind: String? = null
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("channel", channel)
        put("attributionKind", if (referrerDomain != null) "referrer" else "utm")
        referrerDomain?.let { put("referrerDomain", it) }
        utmMedium?.let { put("utmMedium", it) }
        utmCampaign?.let { put("utmCampaign", it) }
        utmContent?.let { put("utmContent", it) }
    }
}

private val OWNED_REFERRER_ROOTS =
    listOf("mywallet.io", "mytonwallet.io", "mytonwallet.org", "mytonwallet.app", "my.tt")
private val REFERRER_DOMAIN_PATTERN =
    Regex("^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$")

fun sanitizeReferrer(raw: String?): String = sanitizeInstallAttribution(raw).channel

fun sanitizeInstallAttribution(raw: String?): InstallAttribution {
    if (raw.isNullOrEmpty()) return InstallAttribution(CHANNEL_UNKNOWN, isTechnical = true)

    var utmSource: String? = null
    var utmMedium: String? = null
    var referrerDomain: String? = null
    var attributionKind: String? = null
    val details = mutableMapOf<String, String>()
    for (pair in raw.split("&")) {
        val separator = pair.indexOf('=')
        if (separator < 0) continue
        val key = runCatching {
            URLDecoder.decode(pair.substring(0, separator), "UTF-8")
        }.getOrNull() ?: continue
        if (key !in REFERRER_PARSE_KEYS) continue
        val value = try {
            URLDecoder.decode(pair.substring(separator + 1), "UTF-8")
        } catch (_: Exception) {
            continue
        }
        if (key == "attribution_referrer") {
            val domain = value.lowercase().removeSuffix(".")
            if (domain.length <= 253 && REFERRER_DOMAIN_PATTERN.matches(domain) &&
                OWNED_REFERRER_ROOTS.none { domain == it || domain.endsWith(".$it") }
            ) {
                referrerDomain = domain
            }
            continue
        }
        if (key in setOf("utm_medium", "utm_campaign", "utm_content")) {
            val text = value.trim()
            if (text.isNotEmpty() && text.toByteArray(StandardCharsets.UTF_8).size <= 128 &&
                value.none { it.code in 0..31 || it.code in 127..159 }
            ) {
                details[key] = text
            }
        }
        if (!REFERRER_VALUE_PATTERN.matches(value.trim())) continue
        when (key) {
            "attribution_kind" -> attributionKind = value.trim().lowercase()
            "utm_source" -> utmSource = value.trim().lowercase()
            "utm_medium" -> utmMedium = value.trim().lowercase()
        }
    }

    // The organic-marker check MUST run before the canonical slug guard:
    // "google-play" passes REFERRER_VALUE_PATTERN (hyphen allowed) but fails
    // CANONICAL_SLUG_PATTERN (hyphen rejected).
    if (utmSource == ORGANIC_UTM_SOURCE && utmMedium == ORGANIC_UTM_MEDIUM) {
        return InstallAttribution(CHANNEL_ORGANIC, isTechnical = true)
    }

    if (utmSource == "referral" && attributionKind == "referral") {
        return InstallAttribution("referral", isTechnical = true, technicalKind = "referral")
    }

    val source = utmSource
    if (source != null && CANONICAL_SLUG_PATTERN.matches(source)) {
        return InstallAttribution(
            source,
            utmMedium = details["utm_medium"],
            utmCampaign = details["utm_campaign"],
            utmContent = details["utm_content"]
        )
    }
    return referrerDomain?.let { InstallAttribution("", it) }
        ?: InstallAttribution(CHANNEL_UNKNOWN, isTechnical = true)
}

data class AttributionDeeplink(
    val url: String,
    val attribution: InstallAttribution?,
    val isGet: Boolean
) {
    fun captureIfAdmitted(parsed: Deeplink?, source: DeeplinkOpenSource) {
        val snapshot = admittedAttribution(parsed, source) ?: return
        InstallAttributionDelivery.capture(snapshot)
    }

    // Admission is independent of wallet readiness: a cold install retains its source before onboarding.
    fun admittedAttribution(parsed: Deeplink?, source: DeeplinkOpenSource): InstallAttribution? {
        if (isGet) return attribution
        if (parsed == null || (parsed is Deeplink.Offramp && !source.canRouteOfframp)) return null
        return attribution
    }
}

fun splitAttributionDeeplink(value: String): AttributionDeeplink {
    val uri = try {
        URI(value)
    } catch (
        _: Exception
    ) {
        return AttributionDeeplink(value, null, false)
    }
    val isSelf = uri.scheme in setOf("mtw", "gramwallet") ||
        (
            uri.scheme in setOf("https", "http") &&
                uri.host in setOf("my.tt", "go.mytonwallet.org", "go.gramwallet.io")
            )
    if (!isSelf) return AttributionDeeplink(value, null, false)
    val query = uri.rawQuery ?: ""
    val parsed = sanitizeInstallAttribution(query)
    val attribution = parsed.takeUnless { it.isTechnical }
    val marketingKeys =
        setOf("utm_source", "utm_medium", "utm_campaign", "utm_content", "attribution_referrer")
    val businessQuery = query.split("&").filterNot { pair ->
        runCatching { URLDecoder.decode(pair.substringBefore("="), "UTF-8") }.getOrDefault("") in
            marketingKeys
    }.joinToString("&")
    val beforeQuery = value.substringBefore("#").substringBefore("?")
    val fragment = if (value.contains("#")) "#" + value.substringAfter("#") else ""
    val clean = beforeQuery + (if (businessQuery.isEmpty()) "" else "?$businessQuery") + fragment
    val path = if (uri.scheme in
        setOf("mtw", "gramwallet")
    ) {
        "/${uri.host}${uri.path ?: ""}"
    } else {
        uri.path ?: ""
    }
    return AttributionDeeplink(clean, attribution, path == "/get" || path.startsWith("/get/"))
}
