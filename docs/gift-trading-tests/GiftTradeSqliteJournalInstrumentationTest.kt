package org.mytonwallet.app_air.walletcore.gifttrade

import android.content.Context
import android.content.ContextWrapper
import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Source-prepared device checks. They must run only in an isolated test installation.
 * Uses the instrumentation APK's own unique directory, never wallet data or keys.
 */
@RunWith(AndroidJUnit4::class)
class GiftTradeSqliteJournalInstrumentationTest {
    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        val directory = File(base.cacheDir, "gift-journal-${UUID.randomUUID()}").apply { check(mkdirs()) }
        override fun getApplicationContext(): Context = this
        override fun getNoBackupFilesDir(): File = directory
    }
    private fun context() = IsolatedContext(InstrumentationRegistry.getInstrumentation().context)
    private fun row(n: Int): GiftTradePending {
        fun hash(value: Int) = value.toString(16).padStart(64, '0')
        return GiftTradePending(hash(n), GiftTradeContext("0:${hash(1)}", "-239"),
            GiftTradeReference("-239", "sale", "0:${hash(n + 100)}", "0:${hash(n + 200)}"),
            "buy", 1000, 1000, reservationId = n.toString(16).padStart(32, '0'))
    }
    private fun expectFailure(body: () -> Unit) {
        var failed = false
        try { body() } catch (_: Exception) { failed = true }
        assertTrue("Expected fail-closed storage", failed)
    }
    @Test fun persistsAcrossConnectionsAndRollsBackCallbackFailure() {
        val context = context()
        GiftTradeSqliteJournal(context).transact { records -> assertTrue(records.isEmpty()); listOf(row(1)) to Unit }
        expectFailure { GiftTradeSqliteJournal(context).transact<Unit> { throw IllegalStateException("synthetic pre-commit failure") } }
        val saved = GiftTradeSqliteJournal(context).transact { it to it }
        assertEquals(listOf(row(1)), saved)
    }
    @Test fun twoConnectionsSerializeWithoutLostUpdates() {
        val context = context()
        GiftTradeSqliteJournal(context).transact { it to Unit }
        val workers = Executors.newFixedThreadPool(2)
        try {
            val a = workers.submit { GiftTradeSqliteJournal(context).transact { (it + row(1)) to Unit } }
            val b = workers.submit { GiftTradeSqliteJournal(context).transact { (it + row(2)) to Unit } }
            a.get(5, TimeUnit.SECONDS); b.get(5, TimeUnit.SECONDS)
            assertEquals(setOf(row(1), row(2)), GiftTradeSqliteJournal(context).transact { it to it.toSet() })
        } finally { workers.shutdownNow() }
    }
    @Test fun initializedSnapshotsDoNotChangeDatabaseBytes() {
        val context = context()
        val file = File(context.directory, "gift-trading-pending-v1.db")
        GiftTradeSqliteJournal(context).transact { listOf(row(1)) to Unit }
        val before = file.readBytes()
        repeat(3) { assertEquals(listOf(row(1)), GiftTradeSqliteJournal(context).read()) }
        assertArrayEquals(before, file.readBytes())
    }
    @Test fun emptyCorruptAndFutureDatabaseNeverBecomeAnEmptyJournal() {
        for (mode in listOf("empty", "corrupt", "future", "lost-schema")) {
            val context = context()
            val file = File(context.directory, "gift-trading-pending-v1.db")
            when (mode) {
                "empty" -> file.writeBytes(byteArrayOf())
                "corrupt" -> file.writeText("synthetic corrupt SQLite")
                else -> {
                    GiftTradeSqliteJournal(context).transact { listOf(row(1)) to Unit }
                    SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                        db.version = if (mode == "future") 99 else 0
                    }
                }
            }
            val before = file.readBytes()
            expectFailure { GiftTradeSqliteJournal(context).read() }
            expectFailure { GiftTradeSqliteJournal(context).transact { it to Unit } }
            assertTrue("Corruption must not delete evidence", file.exists())
            assertArrayEquals(before, file.readBytes())
        }
    }
    @Test fun mainThreadIsRejectedBeforeAnyDatabaseIsOpened() {
        val context = context()
        val failure = AtomicReference<Throwable?>()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            try { GiftTradeSqliteJournal(context).transact { it to Unit } } catch (error: Throwable) { failure.set(error) }
        }
        assertNotNull(failure.get())
        assertFalse(File(context.directory, "gift-trading-pending-v1.db").exists())
    }
}
