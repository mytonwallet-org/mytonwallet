package org.mytonwallet.app_air.walletbasecontext.utils

import android.annotation.SuppressLint
import android.icu.text.SimpleDateFormat as IcuSimpleDateFormat
import android.icu.util.ULocale
import java.text.SimpleDateFormat as JavaSimpleDateFormat
import java.util.Date
import java.util.Locale as JavaLocale
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage

class WDateFormatter private constructor(
    private val icu: IcuSimpleDateFormat?,
    private val java: JavaSimpleDateFormat?
) {
    fun format(date: Date): String = icu?.format(date)
        ?: java?.format(date)
        ?: error("WDateFormatter constructed without a formatter")

    fun format(timestamp: Long): String = format(Date(timestamp))

    companion object {
        @SuppressLint("SimpleDateFormat")
        fun of(pattern: String, langCode: String): WDateFormatter =
            if (langCode == WLanguage.PERSIAN.langCode) {
                val uLocale = ULocale("fa_IR@calendar=persian")
                WDateFormatter(icu = IcuSimpleDateFormat(pattern, uLocale), java = null)
            } else {
                WDateFormatter(
                    icu = null,
                    java = JavaSimpleDateFormat(pattern, JavaLocale(langCode))
                )
            }

        fun ofActiveLanguage(pattern: String): WDateFormatter =
            of(pattern, WBaseStorage.getActiveLanguage())

        fun isDayBeforeMonth(langCode: String): Boolean =
            langCode == WLanguage.PERSIAN.langCode || langCode == WLanguage.RUSSIAN.langCode
    }
}
