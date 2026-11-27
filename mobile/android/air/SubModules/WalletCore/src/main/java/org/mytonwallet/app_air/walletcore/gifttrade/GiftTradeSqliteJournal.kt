package org.mytonwallet.app_air.walletcore.gifttrade

import android.content.Context
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import android.os.Looper
import java.io.File

/** App-private, excluded from Android Auto Backup. The database never touches wallet secret storage.
 * No default DatabaseErrorHandler: Android's default corruption recovery may delete pending claims.
 * A storage error blocks handoff; it must never become an empty journal or an automatic retry.
 * Call on an IO executor. Native trade UI/signing integration is deliberately not enabled here.
 */
class GiftTradeSqliteJournal(context: Context) : GiftTradeJournalStore {
    private val database = File(context.applicationContext.noBackupFilesDir, "gift-trading-pending-v1.db")
    private val preserveCorruption = DatabaseErrorHandler { throw SQLiteException("Pending journal is corrupt; preserved for reconciliation") }

    override fun read(): List<GiftTradePending> {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Journal requires an IO executor" }
        if (!database.exists()) return transact { it to it }
        check(database.length() > 0L) { "Existing pending journal is empty; reconcile storage loss" }
        SQLiteDatabase.openDatabase(database.absolutePath, null,
            SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS, preserveCorruption).use { db ->
            check(db.version == 1) { "Unsupported pending journal version" }
            return readSnapshot(db)
        }
    }

    private fun readSnapshot(db: SQLiteDatabase): List<GiftTradePending> =
        db.rawQuery("SELECT id, CASE WHEN typeof(payload)='blob' AND length(payload) BETWEEN 1 AND 131072 THEN payload END FROM pending LIMIT 2", null).use { cursor ->
            check(cursor.moveToFirst() && cursor.getInt(0) == 1 && !cursor.isNull(1)) { "Invalid journal row" }
            val records = GiftTradeJournalCodec.decode(cursor.getBlob(1))
            check(!cursor.moveToNext()) { "Invalid journal row count" }
            records
        }

    override fun <T> transact(update: (List<GiftTradePending>) -> Pair<List<GiftTradePending>, T>): T {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Journal requires an IO executor" }
        val existed = database.exists()
        check(!existed || database.length() > 0L) { "Existing pending journal is empty; reconcile storage loss" }
        SQLiteDatabase.openDatabase(database.absolutePath, null,
            SQLiteDatabase.CREATE_IF_NECESSARY or SQLiteDatabase.NO_LOCALIZED_COLLATORS, preserveCorruption).use { db ->
            // Each connection uses FULL durability. SQLite serializes separate connections/processes.
            db.execSQL("PRAGMA synchronous=FULL")
            db.beginTransaction()
            try {
                when (db.version) {
                    0 -> {
                        check(!existed) { "Existing pending journal has lost its schema; reconcile storage loss" }
                        // Version 0 is only accepted for a genuinely uninitialized SQLite schema.
                        db.rawQuery("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'", null).use { c ->
                            check(c.moveToFirst() && c.getLong(0) == 0L) { "Unknown journal schema" }
                        }
                        db.execSQL("CREATE TABLE pending (id INTEGER PRIMARY KEY CHECK (id=1), payload BLOB NOT NULL CHECK (length(payload)<=131072))")
                        db.execSQL("INSERT INTO pending (id,payload) VALUES (1,?)", arrayOf(GiftTradeJournalCodec.encode(emptyList())))
                        db.version = 1
                    }
                    1 -> Unit
                    else -> error("Unsupported pending journal version")
                }
                val current = readSnapshot(db)
                val (next, result) = update(current)
                db.execSQL("UPDATE pending SET payload=? WHERE id=1", arrayOf(GiftTradeJournalCodec.encode(next)))
                db.setTransactionSuccessful()
                // Commit completes before the caller can proceed to a confirmation handoff.
                db.endTransaction()
                return result
            } finally {
                if (db.inTransaction()) db.endTransaction()
            }
        }
    }
}
