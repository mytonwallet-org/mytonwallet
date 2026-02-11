package org.mytonwallet.app_air.walletbasecontext.localization

import java.util.Locale

enum class WLanguage(val langCode: String) {
    CHINESE_SIMPLIFIED("zh-Hans"),
    CHINESE_TRADITIONAL("zh-Hant"),
    ENGLISH("en"),
    GERMAN("de"),

    //PERSIAN("fa"),
    POLISH("pl"),
    RUSSIAN("ru"),
    SPANISH("es"),
    THAI("th"),
    TURKISH("tr"),
    UKRAINIAN("uk");

    val isRTL: Boolean
        get() {
            return false // this == PERSIAN
        }

    val englishName: String
        get() {
            return when (this) {
                ENGLISH -> "English"
                RUSSIAN -> "Russian"
                SPANISH -> "Spanish"
                CHINESE_TRADITIONAL -> "Chinese (Traditional)"
                CHINESE_SIMPLIFIED -> "Chinese (Simplified)"
                TURKISH -> "Turkish"
                GERMAN -> "German"
                THAI -> "Thai"
                UKRAINIAN -> "Ukrainian"
                POLISH -> "Polish"
                //PERSIAN -> "Persian"
            }
        }

    val nativeName: String
        get() {
            return when (this) {
                ENGLISH -> "English"
                RUSSIAN -> "Русский"
                SPANISH -> "Español"
                CHINESE_TRADITIONAL -> "繁體"
                CHINESE_SIMPLIFIED -> "简体"
                TURKISH -> "Türkçe"
                GERMAN -> "Deutsch"
                THAI -> "ไทย"
                UKRAINIAN -> "Українська"
                POLISH -> "Polski"
                //PERSIAN -> "فارسی"
            }
        }

    companion object {
        fun valueOfLocale(locale: Locale): WLanguage? {
            val language = locale.language.lowercase(Locale.ROOT)

            if (language == "zh") {
                return chineseVariant(locale)
            }

            return entries.firstOrNull { it.langCode == language }
        }

        private fun chineseVariant(locale: Locale): WLanguage {
            val script = locale.script
            val country = locale.country.uppercase(Locale.ROOT)

            return when {
                script.equals("Hant", ignoreCase = true) -> CHINESE_TRADITIONAL
                script.equals("Hans", ignoreCase = true) -> CHINESE_SIMPLIFIED
                country in setOf("TW", "HK", "MO") -> CHINESE_TRADITIONAL
                else -> CHINESE_SIMPLIFIED
            }
        }
    }
}
