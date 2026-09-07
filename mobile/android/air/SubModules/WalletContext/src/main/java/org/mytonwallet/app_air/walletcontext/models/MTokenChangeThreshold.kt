package org.mytonwallet.app_air.walletcontext.models

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

enum class MTokenChangeThreshold(val value: String, val minAbsolutePercent: Double?) {
    OFF("off", null),
    HALF_PERCENT("0.5", 0.5),
    ONE_AND_HALF_PERCENT("1.5", 1.5),
    FIVE_PERCENT("5", 5.0);

    companion object {
        val DEFAULT = ONE_AND_HALF_PERCENT

        fun fromValue(value: String?): MTokenChangeThreshold =
            entries.firstOrNull { it.value == value } ?: DEFAULT
    }

    val displayName: String
        get() = when (this) {
            OFF -> LocaleController.getString("\$settings_token_change_threshold_off")
            else -> "$value%"
        }

    fun shouldShow(percentChange: Double): Boolean {
        val min = minAbsolutePercent ?: return true
        return kotlin.math.abs(percentChange) >= min
    }
}
