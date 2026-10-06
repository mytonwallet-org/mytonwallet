package org.mytonwallet.app_air.uiswap.screens.tokenTrade

import java.math.BigDecimal
import java.math.BigInteger

/** Keeps edits decimal and lossless until they enter the shared quote pipeline. */
data class TokenTradeAmountInput(val text: String = "") {

    data class Edit(val input: TokenTradeAmountInput, val caret: Int)

    fun replacing(start: Int, end: Int, replacement: String, decimals: Int): Edit? {
        if (start < 0 || end < start || end > text.length) return null
        val normalizedReplacement = normalizeNumerals(replacement)
        if (!normalizedReplacement.all { it in ALLOWED_CHARACTERS }) return null
        if (normalizedReplacement == "." || normalizedReplacement == ",") {
            if (text.removeRange(start, end).contains('.')) return null
        }
        val raw = text.replaceRange(start, end, normalizedReplacement)
        val normalized = normalize(raw, preserveTrailingSeparator = true)
        val parts = normalized.split('.')
        if (parts[0].length > MAX_INTEGRAL_DIGITS) return null
        if (parts.size > 1 && (decimals <= 0 || parts[1].length > decimals)) return null

        // Map the insertion point through removed grouping characters and leading zeroes.
        val prefix = raw.substring(0, start + normalizedReplacement.length)
        val separatorIndex = raw.indexOfLast { it == '.' || it == ',' }
        var caret = prefix.count { it in '0'..'9' }
        if (separatorIndex >= 0 && separatorIndex < prefix.length) caret++
        if (raw.firstOrNull() == '.' || raw.firstOrNull() == ',') caret++
        val integral = parts[0]
        val trimmedLength = integral.trimStart('0').length
        val removedZeros = maxOf(0, integral.length - maxOf(1, trimmedLength))
        val result = normalized.drop(removedZeros)
        caret = minOf(result.length, maxOf(0, caret - removedZeros))
        return Edit(TokenTradeAmountInput(result), caret)
    }

    fun amount(decimals: Int): BigInteger {
        val parts = text.split('.')
        val integral = parts[0].ifEmpty { "0" }
        val fraction = parts.getOrNull(1).orEmpty().take(decimals).padEnd(decimals, '0')
        return (integral + fraction).toBigIntegerOrNull() ?: BigInteger.ZERO
    }

    companion object {
        private const val MAX_INTEGRAL_DIGITS = 12
        private const val GROUPING_CHARACTERS = " '   ’"
        private val ALLOWED_CHARACTERS = "0123456789.,$GROUPING_CHARACTERS".toSet()

        fun of(amount: BigInteger, decimals: Int): TokenTradeAmountInput = TokenTradeAmountInput(
            if (amount > BigInteger.ZERO) {
                BigDecimal(amount, decimals).stripTrailingZeros().toPlainString()
            } else {
                ""
            }
        )

        private fun normalizeNumerals(value: String): String = buildString {
            for (char in value) {
                append(
                    when (char) {
                        in '٠'..'٩' -> '0' + (char - '٠')
                        in '۰'..'۹' -> '0' + (char - '۰')
                        '٫' -> ','
                        else -> char
                    }
                )
            }
        }

        private fun normalize(value: String, preserveTrailingSeparator: Boolean): String {
            val string = normalizeNumerals(value).filterNot { it in GROUPING_CHARACTERS }
            val separatorIndex = string.indexOfLast { it == '.' || it == ',' }
            if (separatorIndex < 0) return string.filter { it in '0'..'9' }
            val integral = string.substring(0, separatorIndex).filter { it in '0'..'9' }
                .ifEmpty { "0" }
            val fraction = string.substring(separatorIndex + 1).filter { it in '0'..'9' }
            if (fraction.isEmpty()) return if (preserveTrailingSeparator) "$integral." else integral
            return "$integral.$fraction"
        }
    }
}
