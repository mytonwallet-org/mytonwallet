package org.mytonwallet.app_air.uicomponents.emoji

import android.text.Editable
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.view.View
import java.lang.ref.WeakReference
import java.text.BreakIterator
import java.util.Locale

object EmojiHelper {

    fun replaceEmoji(text: CharSequence, view: View?): CharSequence {
        if (text.isEmpty() || !containsEmoji(text)) return text

        view?.let { EmojiProvider.init(it.context.applicationContext) }

        val spannable = when (text) {
            is SpannableStringBuilder -> text
            is Spannable -> SpannableStringBuilder(text)
            else -> SpannableStringBuilder(text)
        }

        applySpans(spannable, spannable.toString(), WeakReference(view))
        return spannable
    }

    fun replaceEmojiInPlace(editable: Editable, view: View?) {
        if (editable.isEmpty() || !containsEmoji(editable)) return

        view?.let { EmojiProvider.init(it.context.applicationContext) }
        applySpans(editable, editable.toString(), WeakReference(view))
    }

    private fun containsEmoji(text: CharSequence): Boolean {
        var i = 0
        while (i < text.length) {
            val cp = Character.codePointAt(text, i)
            if (isEmojiCodePoint(cp)) return true
            i += Character.charCount(cp)
        }
        return false
    }

    private fun applySpans(spannable: Spannable, text: String, viewRef: WeakReference<View?>) {
        val it = BreakIterator.getCharacterInstance(Locale.getDefault())
        it.setText(text)

        var start = it.first()
        var end = it.next()

        while (end != BreakIterator.DONE) {
            val cluster = text.substring(start, end)
            if (isEmojiCluster(cluster)) {
                val existing = spannable.getSpans(start, end, EmojiSpan::class.java)
                if (existing.isEmpty()) {
                    val unified = graphemeToUnified(cluster)
                    spannable.setSpan(
                        EmojiSpan(unified, viewRef),
                        start, end,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            }
            start = end
            end = it.next()
        }
    }

    private fun isEmojiCluster(cluster: String): Boolean {
        if (cluster.length == 1) {
            val ch = cluster[0]
            if (ch.isLetterOrDigit() || ch.isWhitespace() || ch in EXCLUDED_CHARS) return false
        }

        var i = 0
        while (i < cluster.length) {
            val cp = Character.codePointAt(cluster, i)
            if (isEmojiCodePoint(cp)) return true
            i += Character.charCount(cp)
        }
        return false
    }

    private fun isEmojiCodePoint(cp: Int): Boolean {
        return cp in 0x1F600..0x1F64F ||
            cp in 0x1F300..0x1F5FF ||
            cp in 0x1F680..0x1F6FF ||
            cp in 0x1F1E0..0x1F1FF ||
            cp in 0x1F900..0x1F9FF ||
            cp in 0x1FA00..0x1FA6F ||
            cp in 0x1FA70..0x1FAFF ||
            cp in 0x2600..0x26FF ||
            cp in 0x2700..0x27BF ||
            cp in 0x2300..0x23FF ||
            cp in 0x2B05..0x2B55 ||
            cp in 0x25A0..0x25FF ||
            cp in 0x1F3FB..0x1F3FF ||
            cp in 0xE0020..0xE007F ||
            cp == 0x00A9 || cp == 0x00AE ||
            cp == 0x203C || cp == 0x2049 ||
            cp == 0x2122 || cp == 0x2139 ||
            cp in 0x3030..0x303D ||
            cp in 0xFE00..0xFE0F ||
            cp == 0x200D
    }

    private fun graphemeToUnified(grapheme: String): String {
        val parts = mutableListOf<String>()
        var i = 0
        while (i < grapheme.length) {
            val cp = Character.codePointAt(grapheme, i)
            parts.add(String.format(Locale.ROOT, "%x", cp))
            i += Character.charCount(cp)
        }
        return parts.joinToString("-")
    }

    private val EXCLUDED_CHARS = charArrayOf(
        '#', '*', '(', ')', '-', '+', '=', '<', '>', '/',
        '\\', '@', '!', '?', ',', '.', ':', ';', '\'', '"',
        '[', ']', '{', '}', '|', '~', '`', '^', '&', '_',
        '$', '%'
    )
}
