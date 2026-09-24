package org.mytonwallet.app_air.uibrowser.search

import android.net.Uri
import java.net.URI
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

data class SearchWebsite(val url: String, val displayText: String)

object SearchWebIntent {
    private val schemeRegex = Regex("^[A-Za-z][A-Za-z0-9+.-]*://")

    fun website(rawText: String): SearchWebsite? {
        val text = rawText.trim()
        if (text.isEmpty() || text.any { it.isWhitespace() }) return null
        if (isChainDomain(text)) return null

        val candidate = if (schemeRegex.containsMatchIn(text)) text else "https://$text"
        val uri = runCatching { URI(candidate) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        if (uri.rawUserInfo != null) return null
        val host = uri.host?.trim() ?: return null
        if (!isWebHost(host)) return null
        return SearchWebsite(uri.toString(), displayText(uri))
    }

    fun isSameDestination(lhs: String, rhs: String): Boolean {
        val left = normalizedDestination(lhs) ?: return false
        val right = normalizedDestination(rhs) ?: return false
        return left == right
    }

    private fun normalizedDestination(url: String): List<String?>? {
        val uri = runCatching { URI(url) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        val host = uri.host?.lowercase() ?: return null
        val port = uri.port.takeUnless {
            it == -1 || (scheme == "https" && it == 443) || (scheme == "http" && it == 80)
        }
        val path = uri.rawPath.takeUnless { it.isNullOrEmpty() || it == "/" }
        return listOf(scheme, host, port?.toString(), path, uri.rawQuery, uri.rawFragment)
    }

    private fun isChainDomain(text: String): Boolean {
        if (MBlockchain.supportedChains.any { it.isValidDNS(text) }) return true
        val candidate = if (schemeRegex.containsMatchIn(text)) text else "https://$text"
        val host = runCatching { URI(candidate).host }.getOrNull() ?: return false
        return MBlockchain.supportedChains.any { it.isValidDNS(host) }
    }

    private fun isWebHost(rawHost: String): Boolean {
        val host = rawHost.lowercase()
        if (host.isEmpty()) return false
        if (host == "localhost") return true
        if (host.contains(":")) return true
        val parts = host.split(".")
        if (parts.size == 4 && parts.all { it.toUByteOrNull() != null }) return true
        return host.contains(".") && !host.startsWith(".") && !host.endsWith(".")
    }

    private fun displayText(uri: URI): String {
        var result = uri.toString()
        uri.scheme?.let { result = result.drop(minOf(result.length, it.length + 3)) }
        if (result.endsWith("/")) result = result.dropLast(1)
        return Uri.decode(result)
    }
}
