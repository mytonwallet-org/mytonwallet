package org.mytonwallet.app_air.walletcontext.sdkStorage

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

object WSdkStorage {
    private lateinit var sharedPreferences: SharedPreferences

    private const val SDK_PREF_NAME = "airSdk"

    fun init(context: Context) {
        sharedPreferences = context.getSharedPreferences(SDK_PREF_NAME, Context.MODE_PRIVATE)
    }

    fun getValue(key: String): String = sharedPreferences.getString(key, null) ?: ""

    fun contains(key: String): Boolean = sharedPreferences.contains(key)

    fun setValue(key: String, value: String) {
        sharedPreferences.edit { putString(key, value) }
    }

    fun migrateValue(key: String, value: String): Boolean =
        sharedPreferences.edit().putString(key, value).commit()

    fun removeValue(key: String) {
        sharedPreferences.edit { remove(key) }
    }

    fun getKeys(): Array<String> = sharedPreferences.all.keys.toTypedArray()

    fun clearStorage() {
        sharedPreferences.edit().clear().commit()
    }
}
