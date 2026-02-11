package org.mytonwallet.app_air.walletbasecontext.localization

import android.content.Context
import android.os.Build
import android.text.SpannableStringBuilder
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.utils.toHashMapStringNested
import java.io.IOException

object LocaleController {
    val PLURAL_RULES: Map<String, (Int) -> Int> = mapOf(
        WLanguage.ENGLISH.langCode to { n -> if (n == 0) 1 else if (n != 1) 6 else 2 },
        WLanguage.RUSSIAN.langCode to { n ->
            when {
                n == 0 -> 1
                n % 10 == 1 && n % 100 != 11 -> 2
                n % 10 in 2..4 && (n % 100 < 10 || n % 100 >= 20) -> 4
                else -> 5
            }
        },

        WLanguage.SPANISH.langCode to { n -> if (n == 0) 1 else if (n != 1) 6 else 2 },
        WLanguage.POLISH.langCode to { n ->
            when {
                n == 0 -> 1
                n == 1 -> 2
                n % 10 in 2..4 && (n % 100 < 10 || n % 100 >= 20) -> 4
                else -> 5
            }
        },
        WLanguage.THAI.langCode to { n -> if (n == 0) 1 else 6 },
        WLanguage.TURKISH.langCode to { n -> if (n == 0) 1 else if (n > 1) 6 else 2 },
        WLanguage.UKRAINIAN.langCode to { n ->
            when {
                n == 0 -> 1
                n % 10 == 1 && n % 100 != 11 -> 2
                n % 10 in 2..4 && (n % 100 < 10 || n % 100 >= 20) -> 4
                else -> 5
            }
        },
        WLanguage.CHINESE_SIMPLIFIED.langCode to { n -> if (n == 0) 1 else 6 },
        WLanguage.CHINESE_TRADITIONAL.langCode to { n -> if (n == 0) 1 else 6 },
        //WLanguage.PERSIAN.langCode to { n -> if (n == 0) 1 else if (n != 1) 6 else 2 },
    )

    val PLURAL_OPTIONS = listOf(
        "value",
        "zeroValue",
        "oneValue",
        "twoValue",
        "fewValue",
        "manyValue",
        "otherValue"
    )

    private var dictionary = emptyMap<String, String>()
    private var _activeLanguage: WLanguage? = null
    val activeLanguage: WLanguage get() = requireNotNull(_activeLanguage) { "LocaleController not initialized yet" }

    fun init(context: Context, langCode: String?): Boolean {
        var langCode = langCode
        val activeLanguage = WLanguage.entries.firstOrNull {
            it.langCode == langCode
        } ?: run {
            langCode = "en"
            WLanguage.ENGLISH
        }
        if (_activeLanguage == activeLanguage) {
            return false
        }
        _activeLanguage = activeLanguage

        var jsonObject: JSONObject
        try {
            val jsonString = context.assets.open("public/i18n/${langCode}.json")
                .bufferedReader()
                .use { it.readText() }
            jsonObject = JSONObject(jsonString)
        } catch (_: IOException) {
            Logger.e(Logger.LogTag.LOCALIZATION, "init: Failed to load file=$langCode.json")
            jsonObject = JSONObject()
        }

        try {
            val jsonStringAir = context.assets.open("i18n/air_${langCode}.json")
                .bufferedReader()
                .use { it.readText() }
            val jsonObjectAir = JSONObject(jsonStringAir)
            for (key in jsonObjectAir.keys()) {
                jsonObject.put(key, jsonObjectAir.get(key))
            }
        } catch (_: IOException) {
            Logger.e(Logger.LogTag.LOCALIZATION, "init: Failed to load file=air_$langCode.json")
        }

        dictionary = jsonObject.toHashMapStringNested()
        return true
    }

    fun resolveSystemLanguageCode(context: Context): String? {
        val configuration = context.resources.configuration
        val locales = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            (0 until configuration.locales.size()).map { configuration.locales[it] }
        } else {
            listOf(configuration.locale)
        }

        return locales.firstNotNullOfOrNull { locale -> WLanguage.valueOfLocale(locale)?.langCode }
    }

    fun getString(key: String): String {
        return dictionary[key] ?: key
    }

    fun getStringOrNull(key: String?): String? {
        return key?.let { getString(key) }
    }

    fun getPlural(amount: Int, key: String): String {
        return getPluralOrFormat(key, amount)
    }

    fun getPluralWord(amount: Int, key: String): String {
        return getPluralOrFormat(key, amount, "")
    }

    fun getPluralOrFormat(
        key: String,
        amount: Int,
        value: String = amount.toString(),
    ): String {
        val rule: ((Int) -> Int)? = PLURAL_RULES[activeLanguage.langCode]
        val optionIndex = rule?.invoke(amount) ?: 0
        val pluralKey = key + "." + PLURAL_OPTIONS.getOrElse(optionIndex) { PLURAL_OPTIONS[0] }
        return if (dictionary.contains(pluralKey))
            getFormattedString(
                pluralKey,
                listOf(value)
            )
        else {
            val fallbackKey = key + "." + PLURAL_OPTIONS[6]
            if (dictionary.contains(fallbackKey))
                getFormattedString(
                    fallbackKey,
                    listOf(value)
                )
            else
                getFormattedString(key, listOf(value))
        }
    }

    fun getFormattedString(key: String, values: List<String>): String {
        var result = getString(key)
        values.forEachIndexed { index, value ->
            result = result
                .replace("%${index + 1}$@", value)
                .replace("%${index + 1}\$d", value)
                .replace("%${index + 1}\$s", value)
        }
        return result
    }

    fun getStringWithKeyValues(
        key: String,
        keyValues: List<Pair<String, String>>
    ): String {
        var result = getString(key)
        keyValues.forEach { keyValue ->
            result = result.replace(keyValue.first, keyValue.second)
        }
        return result
    }

    fun getSpannableStringWithKeyValues(
        key: String,
        keyValues: List<Pair<String, CharSequence>>
    ): CharSequence {
        var result = SpannableStringBuilder(getString(key))
        keyValues.forEachIndexed { index, keyValue ->
            val toReplace = keyValue.first
            val i = result.indexOf(toReplace)
            if (i != -1) {
                result = result.replace(i, i + toReplace.length, keyValue.second)
            }
        }
        return result
    }

    fun getFormattedEnumeration(
        items: List<String>,
        joiner: String = "and"
    ): String {
        val middleJoiner = getString("\$joining_comma")
        val lastJoiner = getString(if (joiner == "and") "\$joining_and" else "\$joining_or")
        return buildString {
            items.forEachIndexed { i, item ->
                if (i > 0) {
                    append(if (i == items.lastIndex) lastJoiner else middleJoiner)
                }
                append(item)
            }
        }
    }

    val isRTL: Boolean
        get() {
            return activeLanguage.isRTL
        }
    val rtlMultiplier: Int
        get() {
            return if (isRTL) -1 else 1
        }
}
