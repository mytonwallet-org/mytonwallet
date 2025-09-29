package org.mytonwallet.app_air.walletbasecontext.utils

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

enum class MHistoryTimePeriod(val value: String) {
    DAY("1D"),
    WEEK("7D"),
    MONTH("1M"),
    THREE_MONTHS("3M"),
    YEAR("1Y"),
    ALL("ALL");

    val localized: String
        get() = when (this) {
            DAY -> LocaleController.getString("D")
            WEEK -> LocaleController.getString("W")
            MONTH -> LocaleController.getString("M")
            THREE_MONTHS -> LocaleController.getString("3M")
            YEAR -> LocaleController.getString("Y")
            ALL -> LocaleController.getString("All")
        }

    val localizedLong: String
        get() = when (this) {
            DAY -> LocaleController.getString("\$period_day")
            WEEK -> LocaleController.getString("\$period_week")
            MONTH -> LocaleController.getString("\$period_month")
            THREE_MONTHS -> LocaleController.getString("\$period_3months")
            YEAR -> LocaleController.getString("\$period_year")
            ALL -> LocaleController.getString("\$period_all")
        }

    companion object {
        val allPeriods = arrayOf(
            ALL,
            YEAR,
            THREE_MONTHS,
            MONTH,
            WEEK,
            DAY
        )

        fun fromValue(value: String?): MHistoryTimePeriod? =
            allPeriods.find { it.value == value }
    }
}
