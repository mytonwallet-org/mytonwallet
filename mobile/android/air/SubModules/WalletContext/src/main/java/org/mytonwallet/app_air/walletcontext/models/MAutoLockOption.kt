package org.mytonwallet.app_air.walletcontext.models

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

enum class MAutoLockOption(val value: String, val period: Int?) {
    NEVER("never", null),
    THIRTY_SECONDS("1", 30),
    THREE_MINUTES("2", 3 * 60),
    TEN_MINUTES("3", 10 * 60);

    companion object {
        fun fromValue(value: String?): MAutoLockOption? {
            if (value == null)
                return NEVER
            return entries.firstOrNull { it.value == value }
        }
    }

    val displayName: String
        get() {
            return when (this) {
                NEVER -> {
                    LocaleController.getString("Never")
                }

                THIRTY_SECONDS -> {
                    LocaleController.getFormattedString("%1$@ seconds", listOf("30"))
                }

                THREE_MINUTES -> {
                    LocaleController.getFormattedString("%1$@ minutes", listOf("3"))
                }

                TEN_MINUTES -> {
                    LocaleController.getFormattedString("%1$@ minutes", listOf("10"))
                }
            }
        }
}
