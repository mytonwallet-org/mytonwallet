package org.mytonwallet.app_air.walletcontext.utils

import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import org.mytonwallet.app_air.walletcontext.theme.WColorGradients

val String.gradientColors: IntArray
    get() {
        var combinedValue = 0u
        for (scalar in this) {
            combinedValue += scalar.code.toUInt()
        }
        val a = combinedValue.toInt() % WColorGradients.size
        return WColorGradients[combinedValue.toInt() % WColorGradients.size]
    }

val String.shortChars: String
    get() {
        val splitted = this.split(" ")
        var shortText = ""
        for (i in 0 until minOf(2, splitted.size)) {
            val char = splitted[i].firstOrNull()
            if (char != null) {
                shortText += char
            }
        }
        return shortText
    }

fun String.formatStartEndAddress(prefix: Int = 4, suffix: Int = 4): String {
    if (length < prefix + suffix + 3) {
        return this
    }
    val start = this.take(prefix)
    val end = this.takeLast(suffix)
    return "$start···$end"
}

fun String.insertGroupingSeparator(separator: Char = ' ', everyNthPosition: Int = 3): String {
    var result = StringBuilder()
    var count = 0
    var hasDot = this.contains(".")

    for (char in this.reversed()) {
        if (hasDot) {
            result.insert(0, char)
            if (char == '.') {
                hasDot = false
            }
            continue
        }
        if (count != 0 && count % everyNthPosition == 0) {
            result.insert(0, separator)
        }
        result.insert(0, char)
        count += 1
    }

    return result.toString()
}

val String.breakToTwoLines: String
    get() {
        val length = length
        val halfLength = length / 2

        // Handle the case where the length is odd
        val adjustedHalfLength = if (length % 2 == 0) halfLength else halfLength + 1

        // Split the string
        val firstLine = substring(0, adjustedHalfLength)
        val secondLine = substring(adjustedHalfLength)

        return "$firstLine\n$secondLine"
    }

/*private val numerals = listOf(
    Triple("0", "٠", "۰"),
    Triple("1", "١", "۱"),
    Triple("2", "٢", "۲"),
    Triple("3", "٣", "۳"),
    Triple("4", "٤", "۴"),
    Triple("5", "٥", "۵"),
    Triple("6", "٦", "۶"),
    Triple("7", "٧", "۷"),
    Triple("8", "٨", "۸"),
    Triple("9", "٩", "۹"),
    Triple(",", "٫", "٫")
)

val String.normalizeArabicPersianNumeralStringToWestern: String
    get() {
        var string = this

        for ((western, arabic, persian) in numerals) {
            string = string.replace(arabic, western)
            string = string.replace(persian, western)
        }

        return string
    }

val String.withLocalizedNumbers: String
    get() {
        var string = this

        for ((western, arabic, persian) in numerals) {
            when (LocaleController.activeLanguage.langCode) {
                "fa" -> {
                    string = string.replace(western, persian)
                    string = string.replace(arabic, persian)
                }

                else -> {
                    string = string.replace(arabic, western)
                    string = string.replace(persian, western)
                }
            }
        }

        return string
    }*/

fun String.isNumeric(): Boolean {
    return this.matches(Regex("[0-9.]+"))
}

fun String.boldSubstring(target: String): SpannableString {
    val spannable = SpannableString(this)
    val start = indexOf(target)
    if (start != -1) {
        val end = start + target.length
        spannable.setSpan(
            StyleSpan(Typeface.BOLD),
            start,
            end,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }
    return spannable
}

fun CharSequence.toProcessedSpannableStringBuilder(): SpannableStringBuilder {
    val spannable = SpannableStringBuilder(this)

    val pattern = Regex("\\*\\*(.+?)\\*\\*")
    val matches = pattern.findAll(spannable)

    for (match in matches.toList().asReversed()) {
        val fullMatchStart = match.range.first
        val fullMatchEnd = match.range.last + 1

        val boldTextStart = fullMatchStart + 2
        val boldTextEnd = fullMatchEnd - 2

        spannable.setSpan(
            StyleSpan(Typeface.BOLD),
            boldTextStart,
            boldTextEnd,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )

        spannable.delete(boldTextEnd, boldTextEnd + 2)
        spannable.delete(fullMatchStart, fullMatchStart + 2)
    }

    return spannable
}

fun String.toBoldSpannableStringBuilder(): SpannableStringBuilder {
    val spannable = SpannableStringBuilder(this)
    spannable.setSpan(
        StyleSpan(Typeface.BOLD),
        0,
        spannable.length,
        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
    )

    return spannable
}
