package org.mytonwallet.app_air.walletcontext.models

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.withLocalizedNumbers

enum class MAutoExitOption(val value: String?, val failedAttempts: Int?) {
    DISABLED(null, null),
    THREE_ATTEMPTS("3", 3),
    FIVE_ATTEMPTS("5", 5),
    TEN_ATTEMPTS("10", 10),
    TWENTY_ATTEMPTS("20", 20);

    companion object {
        fun fromValue(value: String?): MAutoExitOption =
            entries.firstOrNull { it.value == value } ?: DISABLED
    }

    val displayName: String
        get() {
            val attempts = failedAttempts ?: return LocaleController.getString("Disabled")
            return LocaleController.getStringWithKeyValues(
                "%count% attempts",
                listOf("%count%" to attempts.toString().withLocalizedNumbers)
            )
        }
}
