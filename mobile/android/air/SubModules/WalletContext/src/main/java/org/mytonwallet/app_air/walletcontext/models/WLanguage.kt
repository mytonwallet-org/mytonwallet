package org.mytonwallet.app_air.walletcontext.models

enum class WLanguage(val langCode: String) {
    ENGLISH("en");

    /*CHINESE_SIMPLIFIED("zh-Hans"),
    CHINESE_TRADITIONAL("zh-Hant"),
    ENGLISH("en"),
    GERMAN("de"),
    PERSIAN("fa"),
    POLISH("pl"),
    RUSSIAN("ru"),
    SPANISH("es"),
    THAI("th"),
    TURKISH("tr"),
    UKRAINIAN("uk");*/

    val isRTL: Boolean
        get() {
            return false // this == PERSIAN
        }

    val englishName: String
        get() {
            return when (this) {
                ENGLISH -> "English"
                /*SPANISH -> "Spanish"
                RUSSIAN -> "Russian"
                CHINESE_TRADITIONAL -> "Chinese (Traditional)"
                CHINESE_SIMPLIFIED -> "Chinese (Simplified)"
                TURKISH -> "Turkish"
                GERMAN -> "German"
                THAI -> "Thai"
                UKRAINIAN -> "Ukrainian"
                POLISH -> "Polish"
                PERSIAN -> "Persian"*/
            }
        }

    val nativeName: String
        get() {
            return when (this) {
                ENGLISH -> "English"
                /*SPANISH -> "Español"
                RUSSIAN -> "Русский"
                CHINESE_TRADITIONAL -> "繁體"
                CHINESE_SIMPLIFIED -> "简体"
                TURKISH -> "Türkçe"
                GERMAN -> "Deutsch"
                THAI -> "ไทย"
                UKRAINIAN -> "Українська"
                POLISH -> "Polski"
                PERSIAN -> "فارسی"*/
            }
        }
}
