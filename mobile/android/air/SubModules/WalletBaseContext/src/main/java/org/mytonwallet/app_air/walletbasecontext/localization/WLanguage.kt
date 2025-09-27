package org.mytonwallet.app_air.walletbasecontext.localization

enum class WLanguage(val langCode: String) {
    ENGLISH("en"),
    RUSSIAN("ru");

    /*CHINESE_SIMPLIFIED("zh-Hans"),
    CHINESE_TRADITIONAL("zh-Hant"),
    ENGLISH("en"),
    GERMAN("de"),
    PERSIAN("fa"),
    POLISH("pl"),
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
                RUSSIAN -> "Russian"
                /*SPANISH -> "Spanish"
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
                RUSSIAN -> "Русский"
                /*SPANISH -> "Español"
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
