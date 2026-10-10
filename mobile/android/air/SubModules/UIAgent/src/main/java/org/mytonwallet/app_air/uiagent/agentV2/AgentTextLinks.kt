package org.mytonwallet.app_air.uiagent.agentV2

import java.net.URL
import java.net.URLDecoder
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.walletbasecontext.APP_SCHEME
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink

/**
 * Answer links travel inside message text as private-use markers around their labels, so they survive table
 * splicing and block parsing; `resolve` turns marked labels into links and removes the markers.
 * A marker carries its URL percent-encoded to ASCII letters, digits and `%`, which Markdown parsing leaves alone.
 */
internal object AgentTextLinks {
    private const val LINK_START = ''
    private const val URL_END = ''
    private const val LINK_END = ''

    /** A marked label: group 1 is the encoded URL, group 2 the label */
    val markedLink = Regex("([A-Za-z0-9%]*)([^]*)")

    /** A marker left without its pair, such as one Markdown parsing split from it */
    private val strayMarker = Regex("[A-Za-z0-9%]*|[-]")

    private val markedLinkOrStrayMarker = Regex("${markedLink.pattern}|${strayMarker.pattern}")

    /** The deeplink commands that only open a screen, such as `settings/appearance` */
    private val appScreenPath =
        Regex("explore|market|portfolio|multisend|settings(/[a-z][a-z0-9-]*)?")

    data class Marked(val text: String, val tableOffsets: List<Int>)

    /**
     * Marks the labels of `links` in `text` as far as the text covers them, so a label is a link from its first
     * character. A link that overlaps an earlier link or contains a table stays unmarked, and one the app may not
     * open is marked without a URL, so its label still loses the server's escapes; `tableOffsets` move with the text.
     */
    fun mark(text: String, links: List<AgentV2AnswerLink>, tableOffsets: List<Int>): Marked {
        if (links.isEmpty()) return Marked(text, tableOffsets)
        val marked = StringBuilder()
        var offset = 0
        val insertions = mutableListOf<Pair<Int, Int>>()
        links.forEach { link ->
            val end = link.textOffset + link.textLength
            if (link.textOffset < offset || link.textLength < 1 || link.textOffset >= text.length ||
                tableOffsets.any { it > link.textOffset && it < end }
            ) {
                return@forEach
            }
            val visibleEnd = minOf(end, text.length)
            val encodedUrl = if (isOpenable(link.url)) encodeUrl(link.url) else ""
            val opening = "$LINK_START$encodedUrl$URL_END"
            marked.append(text, offset, link.textOffset).append(opening)
                .append(text, link.textOffset, visibleEnd).append(LINK_END)
            insertions += link.textOffset to opening.length + 1
            offset = visibleEnd
        }
        marked.append(text, offset, text.length)
        // A table at the start of a link stays before it
        return Marked(
            marked.toString(),
            tableOffsets.map { tableOffset ->
                tableOffset + insertions.filter { it.first < tableOffset }.sumOf { it.second }
            }
        )
    }

    /** Marked text with each label, without its escapes, followed by its URL, for copying */
    fun copyText(text: String): String {
        val copy = StringBuilder(text)
        val links = mutableListOf<Triple<Int, Int, String>>()
        val delete: (Int, Int) -> Unit = { start, end -> copy.delete(start, end) }
        resolve(copy, removesLabelEscapes = true, delete) { start, end, url ->
            links += Triple(start, end, url)
        }
        links.asReversed().forEach { (start, end, url) ->
            if (copy.substring(start, end) != url) copy.insert(end, " ($url)")
        }
        return copy.toString()
    }

    /** The URL of a marker, or null when it does not decode to a link the app may open */
    fun decodeUrl(encodedUrl: String): String? =
        runCatching { URLDecoder.decode(encodedUrl, "UTF-8") }.getOrNull()?.takeIf(::isOpenable)

    /**
     * Removes the markers from `text`, which `delete` edits in place, and the backslash escapes from its labels when
     * `removesLabelEscapes`; passes each label that carries a link the app may open to `link` with its range in the
     * resulting text
     */
    fun resolve(
        text: CharSequence,
        removesLabelEscapes: Boolean,
        delete: (start: Int, end: Int) -> Unit,
        link: (start: Int, end: Int, url: String) -> Unit
    ) {
        var removed = 0
        markedLinkOrStrayMarker.findAll(text.toString()).toList().forEach { match ->
            val start = match.range.first - removed
            val label = match.groups[2]?.value
            if (label == null) {
                delete(start, start + match.value.length)
                removed += match.value.length
                return@forEach
            }
            val encodedUrl = match.groupValues[1]
            delete(start, start + encodedUrl.length + 2)
            delete(start + label.length, start + label.length + 1)
            val escapes = if (removesLabelEscapes) {
                removeEscapes(text, start, start + label.length, delete)
            } else {
                0
            }
            val end = start + label.length - escapes
            removed += match.value.length - (end - start)
            val url = decodeUrl(encodedUrl)
            if (url != null && end > start) link(start, end, url)
        }
    }

    /** Whether the app opens `url` from answer text: `https` with a host and no credentials, or a screen of the app */
    fun isOpenable(url: String): Boolean = isWebLink(url) || isAppScreenLink(url)

    /** A deeplink of this app that only opens one of its screens, a settings section included */
    fun isAppScreenLink(url: String): Boolean {
        val parts = url.split("://", limit = 2)
        // The path is checked first, so a web link never reads the app scheme
        return parts.size == 2 && appScreenPath.matches(parts[1]) && parts[0] == APP_SCHEME
    }

    private fun isWebLink(url: String): Boolean =
        url.none { it.isWhitespace() || it == '\\' || it.isISOControl() } && runCatching {
            // `URL` accepts the characters a WHATWG `href` keeps as they are, such as `{`, `|` or `[`
            val parsed = URL(url)
            parsed.protocol.equals("https", ignoreCase = true) && !parsed.host.isNullOrEmpty() &&
                parsed.userInfo == null
        }.getOrDefault(false)

    /** Removes the backslash escapes in `text` between `start` and `end`; returns how many it removed */
    private fun removeEscapes(
        text: CharSequence,
        start: Int,
        end: Int,
        delete: (start: Int, end: Int) -> Unit
    ): Int {
        var removed = 0
        var index = start
        while (index < end - removed - 1) {
            if (text[index] == '\\' && text[index + 1] in MarkdownParser.ESCAPABLE_CHARACTERS) {
                delete(index, index + 1)
                removed += 1
            }
            index += 1
        }
        return removed
    }

    private fun encodeUrl(url: String): String = buildString {
        url.toByteArray(Charsets.UTF_8).forEach { byte ->
            val code = byte.toInt() and 0xFF
            val character = code.toChar()
            if (code < 0x80 && character.isLetterOrDigit()) {
                append(character)
            } else {
                append('%').append(HEX_DIGITS[code shr 4]).append(HEX_DIGITS[code and 0x0F])
            }
        }
    }

    private const val HEX_DIGITS = "0123456789ABCDEF"
}
