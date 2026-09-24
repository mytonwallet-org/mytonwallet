package org.mytonwallet.app_air.walletcontext.models

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

enum class MAutoLockOption(val value: String, val period: Int?) {
    NEVER("never", null),
    THIRTY_SECONDS("1", 30),
    THREE_MINUTES("2", 3 * 60),
    TEN_MINUTES("3", 10 * 60);

    companion object {
        fun fromValue(value: String?): MAutoLockOption? {
            if (value == null) return NEVER
            return entries.firstOrNull { it.value == value }
        }
    }

    val displayName: String
        get() = LocaleController.getString(
            when (this) {
                NEVER -> "Disabled"
                THIRTY_SECONDS -> "30 seconds"
                THREE_MINUTES -> "3 minutes"
                TEN_MINUTES -> "10 minutes"
            }
        )

    val selectedDisplayName: String
        get() = LocaleController.getString(
            when (this) {
                NEVER -> "Disabled"
                THIRTY_SECONDS -> "If away for 30 sec"
                THREE_MINUTES -> "If away for 3 min"
                TEN_MINUTES -> "If away for 10 min"
            }
        )
}
