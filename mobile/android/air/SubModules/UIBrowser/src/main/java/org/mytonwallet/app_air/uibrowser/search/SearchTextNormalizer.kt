package org.mytonwallet.app_air.uibrowser.search

import android.os.Build
import java.text.Normalizer
import java.util.Locale

/**
 * A single query or field term together with the alternative spellings it can match through, such
 * as a Latin transliteration of a Cyrillic word.
 */
data class NormalizedSearchTerm(val alternatives: List<String>)

data class NormalizedSearchText(
    val canonical: String,
    val transliterated: String?,
    val terms: List<NormalizedSearchTerm>
) {
    val phraseAlternatives: List<String>
        get() {
            val values = ArrayList<String>(2)
            if (canonical.isNotEmpty()) values.add(canonical)
            transliterated?.let { values.add(it) }
            return values.distinct()
        }

    val isEmpty: Boolean get() = canonical.isEmpty()
}

data class UniversalSearchQuery(val text: String) {
    val normalizedText: NormalizedSearchText = SearchTextNormalizer.normalize(text)
    val normalizedIdentifier: String = SearchTextNormalizer.normalizeIdentifier(text)

    val isEmpty: Boolean get() = normalizedText.isEmpty
    val termCount: Int get() = normalizedText.terms.size

    /**
     * Long, unbroken input is much more likely to be an address or another identifier than
     * human-language text. It may match an exact identifier field, but must not produce incidental
     * word matches from small address fragments while a query source resolves it.
     */
    val requiresExactIdentifierMatch: Boolean
        get() {
            val trimmed = text.trim()
            return trimmed.length >= MIN_IDENTIFIER_LENGTH && trimmed.none { it.isWhitespace() }
        }

    private companion object {
        const val MIN_IDENTIFIER_LENGTH = 24
    }
}

object SearchTextNormalizer {
    private val locale: Locale = Locale.US

    // Transliterator arrived in API 29; below that a query keeps only its canonical spelling.
    private val transliterator by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            runCatching {
                android.icu.text.Transliterator.getInstance("Any-Latin; Latin-ASCII")
            }.getOrNull()
        } else {
            null
        }
    }

    fun normalize(text: String): NormalizedSearchText {
        val canonical = normalizeWords(text)
        val terms = canonical
            .split(' ')
            .filter { it.isNotEmpty() }
            .map { token ->
                val alternatives = ArrayList<String>(2)
                alternatives.add(token)
                transliterate(token)?.let { transliterated ->
                    val normalized = normalizeWords(transliterated)
                    if (normalized.isNotEmpty()) alternatives.add(normalized)
                }
                NormalizedSearchTerm(alternatives.distinct())
            }
        val transliterated = transliterate(canonical)
            ?.let { normalizeWords(it) }
            ?.takeIf { it.isNotEmpty() && it != canonical }

        return NormalizedSearchText(
            canonical = canonical,
            transliterated = transliterated,
            terms = terms
        )
    }

    fun normalizeIdentifier(text: String): String = fold(text).trim()

    /** Case and diacritic insensitive prefix test that keeps [prefix].length characters aligned. */
    fun hasPrefix(text: String, prefix: String): Boolean {
        if (text.startsWith(prefix, ignoreCase = true)) return true
        val folded = fold(text)
        val foldedPrefix = fold(prefix)
        return folded.length == text.length &&
            foldedPrefix.length == prefix.length &&
            folded.startsWith(foldedPrefix)
    }

    /** Folds the text and collapses every non-alphanumeric run into a single separator. */
    private fun normalizeWords(text: String): String {
        val folded = fold(text)
        val result = StringBuilder(folded.length)
        var needsSeparator = false
        for (character in folded) {
            if (character.isLetterOrDigit()) {
                if (needsSeparator && result.isNotEmpty()) result.append(' ')
                result.append(character)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        return result.toString()
    }

    /** Case, width, and diacritic insensitive form, so `Tether` and `tèther` compare equal. */
    private fun fold(text: String): String {
        if (text.all { it.code < 128 }) return text.lowercase(locale)
        return Normalizer.normalize(text, Normalizer.Form.NFKD)
            .replace(DIACRITICS, "")
            .lowercase(locale)
    }

    /**
     * ICU transliteration is comparatively expensive. The overwhelming majority of token names,
     * symbols, slugs, URLs, and addresses are already ASCII and cannot gain another useful
     * representation from it.
     */
    private fun transliterate(text: String): String? {
        if (text.all { it.code < 128 }) return null
        return runCatching { transliterator?.transliterate(text) }.getOrNull()
    }

    private val DIACRITICS = Regex("\\p{Mn}+")
}
