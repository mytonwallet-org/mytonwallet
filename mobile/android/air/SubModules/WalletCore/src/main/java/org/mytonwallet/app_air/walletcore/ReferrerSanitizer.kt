package org.mytonwallet.app_air.walletcore

import android.content.Context
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.installationStorage.SourceSnapshot
import org.mytonwallet.app_air.walletcontext.installationStorage.WInstallationStorage
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

fun sanitizeInstallAttribution(raw: String?): SourceSnapshot {
    if (raw.isNullOrEmpty()) {
        return SourceSnapshot("", "direct", "empty_referrer")
    }

    var hasSource = false
    var utmSource: String? = null
    var utmMedium: String? = null
    var referrer: SourceSnapshot? = null
    var attributionKind: String? = null
    val details = mutableMapOf<String, String>()
    for (pair in raw.split("&")) {
        val separator = pair.indexOf('=')
        if (separator < 0) continue
        val key = runCatching {
            URLDecoder.decode(pair.substring(0, separator), "UTF-8")
        }.getOrNull() ?: continue
        if (key !in REFERRER_PARSE_KEYS) continue
        if (key == "utm_source" || key == "attribution_referrer") hasSource = true
        val value = try {
            URLDecoder.decode(pair.substring(separator + 1), "UTF-8")
        } catch (_: Exception) {
            continue
        }
        if (key == "attribution_referrer") {
            val domain = value.lowercase().removeSuffix(".")
            runCatching { SourceSnapshot("", "referrer", "external_referrer", domain) }
                .onSuccess { referrer = it }
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
        return SourceSnapshot("", "direct", "organic")
    }

    if (utmSource == "referral" && attributionKind == "referral") {
        return SourceSnapshot("", "referral", "referral")
    }

    val source = utmSource
    if (source != null && CANONICAL_SLUG_PATTERN.matches(source)) {
        return SourceSnapshot(
            source,
            "utm",
            "utm",
            utmMedium = details["utm_medium"],
            utmCampaign = details["utm_campaign"],
            utmContent = details["utm_content"]
        )
    }
    return referrer
        ?: SourceSnapshot(
            "",
            "direct",
            sourceOutcome = if (hasSource) "invalid_source" else "missing_source"
        )
}

data class AttributionDeeplink(
    val url: String,
    val attribution: SourceSnapshot?,
    val isGet: Boolean
) {
    fun captureIfAdmitted(context: Context, parsed: Deeplink?, source: DeeplinkOpenSource) {
        val snapshot = admittedAttribution(parsed, source) ?: return
        WInstallationStorage.captureSource(context, snapshot, InstallReferrerChannel::notifyBridges)
    }

    // Admission is independent of wallet readiness: a cold install retains its source before onboarding.
    fun admittedAttribution(parsed: Deeplink?, source: DeeplinkOpenSource): SourceSnapshot? {
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
    val attribution = parsed.takeIf { it.attributionKind in setOf("utm", "referrer") }
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
