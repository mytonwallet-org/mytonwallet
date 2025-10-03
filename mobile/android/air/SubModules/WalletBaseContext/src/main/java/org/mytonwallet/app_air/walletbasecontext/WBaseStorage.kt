package org.mytonwallet.app_air.walletbasecontext

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency

// BaseStorage is used to store common data which can be accessed/modified through the `main applications` and `widgets`.
object WBaseStorage {
    private lateinit var sharedPreferences: SharedPreferences

    private const val CACHE_PREF_NAME = "base"

    private const val CACHE_ACTIVE_LANGUAGE = "language"
    private const val CACHE_BASE_CURRENCY = "baseCurrency"
    private const val CACHE_WIDGET_CONFIG = "widgetConfig."

    var isInitialized = false
        private set

    fun init(context: Context) {
        isInitialized = true
        sharedPreferences =
            context.applicationContext.getSharedPreferences(CACHE_PREF_NAME, Context.MODE_PRIVATE)
    }

    fun getActiveLanguage(): String {
        return sharedPreferences.getString(CACHE_ACTIVE_LANGUAGE, WLanguage.ENGLISH.langCode)
            ?: WLanguage.ENGLISH.langCode
    }

    fun setActiveLanguage(value: String) {
        sharedPreferences.edit { putString(CACHE_ACTIVE_LANGUAGE, value) }
    }

    fun getBaseCurrency(): MBaseCurrency? {
        return sharedPreferences.getString(CACHE_BASE_CURRENCY, null)
            ?.let { MBaseCurrency.parse(it) }
            ?: MBaseCurrency.USD
    }

    fun setBaseCurrency(value: String) {
        sharedPreferences.edit { putString(CACHE_BASE_CURRENCY, value) }
    }

    fun getWidgetConfigurations(appWidgetId: Int?): JSONObject? {
        val jsonString = sharedPreferences.getString("$CACHE_WIDGET_CONFIG$appWidgetId", null)
        return jsonString?.let {
            try {
                JSONObject(it)
            } catch (_: Exception) {
                null
            }
        }
    }

    fun setWidgetConfigurations(appWidgetId: Int, config: JSONObject?) {
        val key = "$CACHE_WIDGET_CONFIG$appWidgetId"
        sharedPreferences.edit {
            config?.let {
                putString(key, config.toString())
            } ?: run {
                remove(key)
            }
        }
    }
}
