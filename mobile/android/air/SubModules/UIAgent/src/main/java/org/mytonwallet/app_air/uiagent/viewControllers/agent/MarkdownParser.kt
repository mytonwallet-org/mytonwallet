package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.util.Patterns
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan

object MarkdownParser {

    private val urlPattern: Regex = Patterns.WEB_URL.toRegex()

    fun parse(text: String, codeColor: Int, onUrlClick: ((String) -> Unit)? = null): SpannableStringBuilder {
        val result = SpannableStringBuilder()
        var i = 0
        val len = text.length

        while (i < len) {
            when {
                // Code block: ```...```
                text.startsWith("```", i) -> {
                    val contentStart = run {
                        val afterTicks = i + 3
                        val lineEnd = text.indexOf('\n', afterTicks)
                        if (lineEnd >= 0) lineEnd + 1 else afterTicks
                    }
                    val end = text.indexOf("```", contentStart)
                    if (end >= 0) {
                        val code = text.substring(contentStart, end).trimEnd('\n')
                        val spanStart = result.length
                        result.append(code)
                        applyCodeSpan(result, spanStart, result.length, codeColor)
                        i = end + 3
                        if (i < len && text[i] == '\n') i++
                    } else {
                        result.append("```")
                        i += 3
                    }
                }

                // Inline code: `...`
                text[i] == '`' -> {
                    val end = text.indexOf('`', i + 1)
                    if (end >= 0 && !text.substring(i + 1, end).contains('\n')) {
                        val spanStart = result.length
                        result.append(text.substring(i + 1, end))
                        applyCodeSpan(result, spanStart, result.length, codeColor)
                        i = end + 1
                    } else {
                        result.append('`')
                        i++
                    }
                }

                // Bold: **...**
                text.startsWith("**", i) -> {
                    val end = text.indexOf("**", i + 2)
                    if (end >= 0) {
                        val spanStart = result.length
                        result.append(parseInline(text.substring(i + 2, end), codeColor))
                        result.setSpan(
                            StyleSpan(Typeface.BOLD),
                            spanStart, result.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                        i = end + 2
                    } else {
                        result.append("**")
                        i += 2
                    }
                }

                // Italic: *...*
                text[i] == '*' && i + 1 < len && text[i + 1] != ' ' -> {
                    val end = text.indexOf('*', i + 1)
                    if (end >= 0 && !text.substring(i + 1, end).contains('\n')) {
                        val spanStart = result.length
                        result.append(parseInline(text.substring(i + 1, end), codeColor))
                        result.setSpan(
                            StyleSpan(Typeface.ITALIC),
                            spanStart, result.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                        i = end + 1
                    } else {
                        result.append('*')
                        i++
                    }
                }

                else -> {
                    result.append(text[i])
                    i++
                }
            }
        }

        if (onUrlClick != null) {
            applyUrlSpans(result, onUrlClick)
        }

        return result
    }

    private fun applyUrlSpans(sb: SpannableStringBuilder, onClick: (String) -> Unit) {
        val text = sb.toString()
        for (match in urlPattern.findAll(text)) {
            val matchStart = match.range.first
            val matchEnd = match.range.last + 1

            val isInsideCode = sb.getSpans(matchStart, matchEnd, TypefaceSpan::class.java)
                .any { it.family == "monospace" }
            if (isInsideCode) continue

            var url = match.value
            if (!url.startsWith("http://", ignoreCase = true) &&
                !url.startsWith("https://", ignoreCase = true)
            ) {
                url = "https://$url"
            }
            sb.setSpan(
                WClickableSpan(url, onClick),
                matchStart, matchEnd,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    private fun parseInline(text: String, codeColor: Int): SpannableStringBuilder {
        val result = SpannableStringBuilder()
        var i = 0
        val len = text.length

        while (i < len) {
            if (text[i] == '`') {
                val end = text.indexOf('`', i + 1)
                if (end >= 0) {
                    val spanStart = result.length
                    result.append(text.substring(i + 1, end))
                    applyCodeSpan(result, spanStart, result.length, codeColor)
                    i = end + 1
                } else {
                    result.append('`')
                    i++
                }
            } else {
                result.append(text[i])
                i++
            }
        }

        return result
    }

    private fun applyCodeSpan(sb: SpannableStringBuilder, start: Int, end: Int, color: Int) {
        sb.setSpan(
            TypefaceSpan("monospace"),
            start, end,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        sb.setSpan(
            RelativeSizeSpan(0.9f),
            start, end,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        sb.setSpan(
            ForegroundColorSpan(color),
            start, end,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }
}
