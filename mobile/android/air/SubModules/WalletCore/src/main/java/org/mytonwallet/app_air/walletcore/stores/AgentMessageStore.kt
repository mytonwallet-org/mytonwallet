package org.mytonwallet.app_air.walletcore.stores

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.sqlStorage.WSQLStorage
import java.util.concurrent.Executors

object AgentMessageStore : IStore {

    private val db get() = WSQLStorage.instance
    private val executor = Executors.newSingleThreadExecutor()

    fun loadMessages(): List<StoredAgentMessage> {
        val result = mutableListOf<StoredAgentMessage>()
        val rdb = db.readableDatabase
        val cursor = rdb.query(
            WSQLStorage.TABLE_MESSAGES,
            null,
            null,
            null,
            null,
            null,
            "${WSQLStorage.COL_DATE} ASC"
        )
        cursor.use {
            while (it.moveToNext()) {
                result.add(readRow(it))
            }
        }
        return result
    }

    fun insertMessage(message: StoredAgentMessage) {
        executor.execute {
            val wdb = db.writableDatabase
            wdb.insertWithOnConflict(
                WSQLStorage.TABLE_MESSAGES,
                null,
                toContentValues(message),
                SQLiteDatabase.CONFLICT_REPLACE
            )
        }
    }

    fun clearMessages() {
        WCacheStorage.setAgentClientId(null)
        executor.execute {
            val wdb = db.writableDatabase
            wdb.delete(WSQLStorage.TABLE_MESSAGES, null, null)
        }
    }

    override fun wipeData() {
        clearMessages()
    }

    override fun clearCache() {
        clearMessages()
    }

    private fun toContentValues(msg: StoredAgentMessage): ContentValues {
        return ContentValues().apply {
            put(WSQLStorage.COL_ID, msg.id)
            put(WSQLStorage.COL_ROLE, msg.role)
            put(WSQLStorage.COL_TEXT, msg.text)
            put(WSQLStorage.COL_DATE, msg.dateMs)
            put(WSQLStorage.COL_DEEPLINKS, encodeDeeplinks(msg.deeplinks))
        }
    }

    private fun readRow(cursor: android.database.Cursor): StoredAgentMessage {
        return StoredAgentMessage(
            id = cursor.getString(cursor.getColumnIndexOrThrow(WSQLStorage.COL_ID)),
            role = cursor.getString(cursor.getColumnIndexOrThrow(WSQLStorage.COL_ROLE)),
            text = cursor.getString(cursor.getColumnIndexOrThrow(WSQLStorage.COL_TEXT)),
            dateMs = cursor.getLong(cursor.getColumnIndexOrThrow(WSQLStorage.COL_DATE)),
            deeplinks = decodeDeeplinks(
                cursor.getString(cursor.getColumnIndexOrThrow(WSQLStorage.COL_DEEPLINKS))
            )
        )
    }

    private fun encodeDeeplinks(deeplinks: List<StoredDeeplink>): String {
        val arr = JSONArray()
        for (dl in deeplinks) {
            arr.put(JSONObject().apply {
                put("title", dl.title)
                put("url", dl.url)
            })
        }
        return arr.toString()
    }

    private fun decodeDeeplinks(json: String): List<StoredDeeplink> {
        val result = mutableListOf<StoredDeeplink>()
        val arr = JSONArray(json)
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            result.add(StoredDeeplink(obj.getString("title"), obj.getString("url")))
        }
        return result
    }
}

data class StoredAgentMessage(
    val id: String,
    val role: String,
    val text: String,
    val dateMs: Long,
    val deeplinks: List<StoredDeeplink> = emptyList()
)

data class StoredDeeplink(
    val title: String,
    val url: String
)
