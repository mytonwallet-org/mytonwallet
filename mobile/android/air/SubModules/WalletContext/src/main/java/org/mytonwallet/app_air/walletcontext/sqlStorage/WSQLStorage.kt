package org.mytonwallet.app_air.walletcontext.sqlStorage

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class WSQLStorage private constructor(context: Context) :
    SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE_MESSAGES (
                $COL_ID TEXT PRIMARY KEY NOT NULL,
                $COL_ROLE TEXT NOT NULL,
                $COL_TEXT TEXT NOT NULL,
                $COL_DATE INTEGER NOT NULL,
                $COL_DEEPLINKS TEXT NOT NULL DEFAULT '[]'
            )
            """.trimIndent()
        )
        db.execSQL(
            "CREATE INDEX idx_messages_date ON $TABLE_MESSAGES ($COL_DATE ASC)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Future migrations go here
    }

    companion object {
        const val DB_NAME = "mtwAir"
        const val DB_VERSION = 1

        const val TABLE_MESSAGES = "messages"
        const val COL_ID = "id"
        const val COL_ROLE = "role"
        const val COL_TEXT = "text"
        const val COL_DATE = "date"
        const val COL_DEEPLINKS = "deeplinks"

        lateinit var instance: WSQLStorage
            private set

        fun init(context: Context) {
            instance = WSQLStorage(context)
        }
    }
}