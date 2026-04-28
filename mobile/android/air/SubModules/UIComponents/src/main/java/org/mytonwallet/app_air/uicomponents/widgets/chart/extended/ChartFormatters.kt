package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.graphics.Color
import androidx.annotation.ColorInt
import androidx.core.graphics.ColorUtils
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Currency
import java.util.Date
import java.util.Locale

internal object ChartFormatters {
    private val compactSuffixes = arrayOf("", "K", "M", "B", "T")
    private val dateFormatCache = mutableMapOf<Pair<String, Locale>, SimpleDateFormat>()

    val locale: Locale
        get() = Locale(WBaseStorage.getActiveLanguage())

    val screenWidthPx: Int
        get() = ApplicationContextHolder.screenWidth

    val screenHeightPx: Int
        get() = ApplicationContextHolder.applicationContext.resources.displayMetrics.heightPixels

    fun formatDate(pattern: String, date: Date): String {
        val locale = locale
        val formatter = dateFormatCache.getOrPut(pattern to locale) {
            SimpleDateFormat(pattern, locale)
        }
        return formatter.format(date)
    }

    fun formatDate(pattern: String, timestamp: Long): String = formatDate(pattern, Date(timestamp))

    fun formatNumber(value: Long, separator: Char = ' '): String {
        return String.format(Locale.US, "%,d", value).replace(',', separator)
    }

    fun formatCurrency(value: Long, code: String, locale: Locale = Locale.US): String {
        val formatter = NumberFormat.getCurrencyInstance(locale)
        formatter.currency = Currency.getInstance(code)
        return formatter.format(value.toDouble())
    }

    fun compactWholeNumber(
        value: Long,
        maxFractionDigits: Int = 2,
        trimTrailingZeros: Boolean = false,
    ): String {
        if (value in -9_999..9_999) {
            return value.toString()
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
        return formatter.format(num) + compactSuffixes[count]
    }

    @ColorInt
    fun defaultDarkLineColor(@ColorInt color: Int): Int {
        return ColorUtils.blendARGB(Color.WHITE, color, 0.85f)
    }
}
