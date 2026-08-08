package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.graphics.Color
import androidx.annotation.ColorInt
import androidx.core.graphics.ColorUtils
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.util.Currency
import java.util.Date
import java.util.Locale
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.WDateFormatter
import org.mytonwallet.app_air.walletbasecontext.utils.withLocalizedNumbers

internal object ChartFormatters {
    private val compactSuffixes = arrayOf("", "K", "M", "B", "T")
    private val dateFormatCache = mutableMapOf<Pair<String, String>, WDateFormatter>()

    val locale: Locale
        get() = WLanguage.dateLocale(WBaseStorage.getActiveLanguage())

    val screenWidthPx: Int
        get() = ApplicationContextHolder.screenWidth

    val screenHeightPx: Int
        get() = ApplicationContextHolder.applicationContext.resources.displayMetrics.heightPixels

    fun formatDate(pattern: String, date: Date): String {
        val langCode = WBaseStorage.getActiveLanguage()
        val formatter = dateFormatCache.getOrPut(pattern to langCode) {
            WDateFormatter.of(pattern, langCode)
        }
        return formatter.format(date)
    }

    fun formatDate(pattern: String, timestamp: Long): String = formatDate(pattern, Date(timestamp))

    fun formatNumber(value: Long, separator: Char = ' '): String =
        String.format(Locale.US, "%,d", value).replace(',', separator).withLocalizedNumbers

    fun formatCurrency(value: Long, code: String, locale: Locale = Locale.US): String {
        val formatter = NumberFormat.getCurrencyInstance(locale)
        formatter.currency = Currency.getInstance(code)
        return formatter.format(value.toDouble()).withLocalizedNumbers
    }

    fun compactWholeNumber(
        value: Long,
        maxFractionDigits: Int = 2,
        trimTrailingZeros: Boolean = false
    ): String {
        if (value in -9_999..9_999) {
            return value.toString().withLocalizedNumbers
        }

        var count = 0
        var num = value.toFloat()
        while (kotlin.math.abs(num) >= 1_000f && count < compactSuffixes.lastIndex) {
            num /= 1_000f
            count++
        }
        val symbols = DecimalFormatSymbols(Locale.US).apply {
            decimalSeparator = '.'
        }
        val pattern = buildString {
            append("#")
            if (maxFractionDigits > 0) {
                append('.')
                repeat(maxFractionDigits) {
                    append(if (trimTrailingZeros) '#' else '0')
                }
            }
        }
        val formatter = DecimalFormat(pattern, symbols)
        return formatter.format(num).withLocalizedNumbers + compactSuffixes[count]
    }

    @ColorInt
    fun defaultDarkLineColor(@ColorInt color: Int): Int =
        ColorUtils.blendARGB(Color.WHITE, color, 0.85f)
}
