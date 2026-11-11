package org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers

import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import java.util.Locale
import kotlin.math.abs
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uifutures.viewControllers.futures.FuturesChangeArrowDrawable
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletbasecontext.utils.withLocalizedNumbers
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsAssetContext

internal fun Double.toUsdString(showPositiveSign: Boolean = false, decimals: Int = 2): String {
    val formatted = abs(this).toString(
        decimals = USD_PRECISION_DECIMALS,
        currency = "$",
        currencyDecimals = decimals,
        smartDecimals = false
    ).orEmpty()
    return when {
        formatted.none { it in '1'..'9' } -> formatted
        this < 0 -> "-$formatted"
        showPositiveSign -> "+$formatted"
        else -> formatted
    }
}

/** A price with the decimals a low price needs, as iOS shows it. */
internal fun Double.toPriceString(): String =
    toString(USD_PRECISION_DECIMALS, "$", 2, smartDecimals = true).orEmpty()

internal fun pnlColor(value: Double): Int = if (value < 0) WColor.Red.color else WColor.Green.color

internal fun Double.toPercentString(shouldUseLatinDigits: Boolean = false): String {
    val value = abs(this).toString(1, "", 1, smartDecimals = true).orEmpty()
    return "${value.withLocalizedNumbers(!shouldUseLatinDigits)}%"
}

internal fun formatPnlChange(pnl: Double, pnlPercent: Double): String {
    val sign = when {
        pnl > 0 -> "+$signSpace"
        pnl < 0 -> "-$signSpace"
        else -> ""
    }
    return "\u202D$sign${pnlPercent.toPercentString()} · ${abs(pnl).toUsdString()}"
}

internal fun wrapLtrInRtl(text: String): String =
    if (LocaleController.isRTL) "\u200F\u202D$text\u202C\u200F" else text

/** `isAfterKnown` is false where the SDK may not estimate the new value, shown as unknown. */
internal fun formatFuturesChange(
    before: String?,
    after: String?,
    isAfterKnown: Boolean = true,
    isPrice: Boolean = false
): CharSequence {
    val format = { value: Double ->
        if (isPrice) value.toPriceString() else value.toUsdString()
    }
    val beforeText = before?.toDoubleOrNull()?.let(format)
        ?: return after?.toDoubleOrNull()?.let(format) ?: "—"
    val afterText = after?.toDoubleOrNull()?.let(format)
        ?: if (isAfterKnown) return beforeText else "—"
    val arrow = FuturesChangeArrowDrawable().apply {
        setBounds(0, 0, intrinsicWidth, intrinsicHeight)
    }
    return SpannableStringBuilder(beforeText).apply {
        setSpan(
            ForegroundColorSpan(WColor.SecondaryText.color),
            0,
            beforeText.length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        append(
            "→",
            VerticalImageSpan(arrow, 6.dp, 4.dp),
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        append(afterText)
    }
}

private const val USD_PRECISION_DECIMALS = 6

internal fun MApiPerpsAssetContext.fundingText(): String? {
    val percent = fundingPercent?.toDoubleOrNull() ?: return null
    val rate = "${percent.toString(6, "", 6, smartDecimals = true).orEmpty()}%"
    val hours = fundingIntervalHours ?: return rate
    return "$rate · ${formatFuturesDuration(hours = hours.toLong(), shouldUseLatinDigits = true)}"
}

internal fun formatFuturesDuration(
    days: Long = 0,
    hours: Long = 0,
    minutes: Long = 0,
    shouldUseLatinDigits: Boolean = false
): String {
    val measures = listOf(
        days to MeasureUnit.DAY,
        hours to MeasureUnit.HOUR,
        minutes to MeasureUnit.MINUTE
    ).filter { it.first > 0 }.map { Measure(it.first, it.second) }
    return MeasureFormat.getInstance(
        Locale.forLanguageTag(
            LocaleController.activeLanguage.langCode +
                if (shouldUseLatinDigits) "-u-nu-latn" else ""
        ),
        MeasureFormat.FormatWidth.NARROW
    ).formatMeasures(*measures.toTypedArray())
}
