package org.mytonwallet.app_air.walletcontext.globalStorage

import org.json.JSONArray
import org.json.JSONObject

interface IGlobalStorageProvider {
    companion object {
        const val PERSIST_NO: Int = 0
        const val PERSIST_NORMAL: Int = 1
        const val PERSIST_INSTANT: Int = 2
    }

    var doNotSynchronize: Int

    fun contains(key: String): Boolean
    fun getInt(key: String): Int?
    fun getString(key: String): String?
    fun getBool(key: String): Boolean?
    fun getDict(key: String): JSONObject?
    fun getArray(key: String): JSONArray?

    fun set(key: String, value: Any?, persistInstantly: Int)
    fun set(items: Map<String, Any?>, persistInstantly: Int)
    fun setEmptyObject(key: String, persistInstantly: Int)
    fun setEmptyObjects(keys: Array<String>, persistInstantly: Int)

    fun remove(key: String, persistInstantly: Int)
    fun remove(keys: Array<String>, persistInstantly: Int)

    fun keysIn(key: String): Array<String>
}
