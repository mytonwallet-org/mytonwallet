package org.mytonwallet.app_air.walletcore.gifttrade

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class GiftTradeJournalTest {
    /** Transaction/codec fixture, not Android SQLite or a process-restart test. */
    private class Store : GiftTradeJournalStore {
        var bytes = GiftTradeJournalCodec.encode(emptyList())
        var failCommit = false
        var failAfterCommit = false
        @Synchronized override fun <T> transact(update: (List<GiftTradePending>) -> Pair<List<GiftTradePending>, T>): T {
            val (next, result) = update(GiftTradeJournalCodec.decode(bytes))
            val encoded = GiftTradeJournalCodec.encode(next)
            check(!failCommit) { "Simulated storage failure" }
            bytes = encoded
            check(!failAfterCommit) { "Simulated lost commit response" }
            return result
        }
    }
    private fun address(n: Int) = "0:" + n.toString(16).padStart(64, '0')
    private fun intent(nft: Int = 2, account: Int = 1, chain: String = "-239", contract: Int = 3) = GiftTradeBoundIntent(
        GiftTradeContext(address(account), chain), GiftTradeReference(chain, "sale", address(nft), address(contract)), "buy",
        address(4), "10000000000", "0", "100000000", "500000000", 1060L, address(4), address(5),
        "a".repeat(64), address(4), "wallet-market", listOf(GiftTradeMessage(address(contract), "10500000000", "AAAA", null)))
    private val messageHash = "b".repeat(64)
    @Test fun listUsesSnapshotWithoutRequestingWrite() {
        val i = intent()
        val backing = Store()
        GiftTradeJournal(backing).reserve(i, 1000)
        val readOnly = object : GiftTradeJournalStore {
            override fun <T> transact(update: (List<GiftTradePending>) -> Pair<List<GiftTradePending>, T>): T =
                error("List must not request a write")
            override fun read() = GiftTradeJournalCodec.decode(backing.bytes)
        }
        assertEquals("uncertain", GiftTradeJournal(readOnly).list(i.context).single().state)
        assertTrue(GiftTradeJournal(readOnly).list(intent(account = 8).context).isEmpty())
    }
    private fun reject(block: () -> Unit) {
        try { block() } catch (_: IllegalArgumentException) { return } catch (_: IllegalStateException) { return }
        fail("Expected rejection")
    }

    @Test fun restartViewKeepsClaimAndBlocksDifferentContractForSameNft() {
        val store = Store(); val i = intent()
        GiftTradeJournal(store).reserve(i, 1000)
        val restarted = GiftTradeJournal(store)
        assertEquals("uncertain", restarted.list(i.context).single().state)
        reject { restarted.reserve(i, 1001) }
        reject { restarted.reserve(intent(contract = 8), 1001) }
        assertEquals(1, restarted.list(i.context).size)
        // Reading late does not change unknown into failed, nor authorize an automatic retry.
        assertEquals("uncertain", GiftTradeJournal(store).list(i.context).single().state)
    }

    @Test fun concurrentInstancesReserveOnlyOnce() {
        val store = Store(); val start = CountDownLatch(1); val successes = AtomicInteger(); val failures = AtomicInteger()
        val workers = (1..12).map {
            Thread {
                start.await()
                try { GiftTradeJournal(store).reserve(intent(), 1000); successes.incrementAndGet() }
                catch (_: IllegalStateException) { failures.incrementAndGet() }
            }.apply { start() }
        }
        start.countDown(); workers.forEach { it.join() }
        assertEquals(1, successes.get()); assertEquals(11, failures.get())
        assertEquals(1, GiftTradeJournal(store).list(intent().context).size)
    }

    @Test fun storageFailureDoesNotReturnSuccessOrLoseExistingClaim() {
        val store = Store(); val journal = GiftTradeJournal(store); val i = intent()
        journal.reserve(i, 1000); val saved = store.bytes.clone(); store.failCommit = true
        reject { journal.reserve(intent(nft = 9), 1001) }
        reject { journal.reconcile(i.context, i.id, "settled", messageHash, 1002) }
        assertArrayEquals(saved, store.bytes)
        val uncertain = Store(); uncertain.failAfterCommit = true
        reject { GiftTradeJournal(uncertain).reserve(i, 1000) }
        uncertain.failAfterCommit = false
        assertEquals("uncertain", GiftTradeJournal(uncertain).list(i.context).single().state)
        reject { GiftTradeJournal(uncertain).reserve(i, 1001) }
    }

    @Test fun contextAndReceiptIdentityCannotBeReplaced() {
        val store = Store(); val journal = GiftTradeJournal(store); val i = intent()
        for (item in listOf(i, intent(account = 8), intent(chain = "-3"))) journal.reserve(item, 1000)
        assertEquals(1, journal.list(i.context).size)
        reject { journal.reconcile(intent(account = 8).context, i.id, "settled", messageHash, 1001) }
        reject { journal.reconcile(i.context, i.id, "failed", "invalid", 1001) }
        reject { journal.reconcile(i.context, i.id, "settled", messageHash, 999) }
        journal.reconcile(i.context, i.id, "submitted", messageHash, 1002)
        reject { journal.reconcile(i.context, i.id, "settled", "c".repeat(64), 1003) }
        journal.reconcile(i.context, i.id, "settled", messageHash, 1003)
        reject { journal.reconcile(i.context, i.id, "failed", messageHash, 1004) }
        assertEquals("uncertain", journal.list(intent(account = 8).context).single().state)
    }

    @Test fun terminalHistoryCannotExhaustCapacityOrEvictUnresolved() {
        val store = Store(); val journal = GiftTradeJournal(store); val pending = intent(nft = 900)
        journal.reserve(pending, 1000)
        for (n in 10..110) {
            val i = intent(nft = n); journal.reserve(i, 1000)
            journal.reconcile(i.context, i.id, "settled", messageHash, 1001)
        }
        assertEquals(100, journal.list(pending.context).size)
        assertEquals("uncertain", journal.list(pending.context).single { it.intentId == pending.id }.state)
        val full = Store(); val fullJournal = GiftTradeJournal(full)
        for (n in 10..109) fullJournal.reserve(intent(nft = n), 1000)
        val before = full.bytes.clone()
        reject { fullJournal.reserve(intent(nft = 200), 1000) }
        assertArrayEquals(before, full.bytes)
    }

    @Test fun codecIsBoundedAndStoresOnlyWhitelistedIdentity() {
        val store = Store(); val i = intent(); val row = GiftTradeJournal(store).reserve(i, 1000)
        assertEquals(listOf(row), GiftTradeJournalCodec.decode(store.bytes))
        val text = store.bytes.toString(Charsets.US_ASCII)
        assertFalse(text.contains("AAAA")); assertFalse(text.contains("10500000000"))
        assertFalse(text.contains("wallet-market")); assertFalse(text.contains("stateInit"))
        val bad = listOf(ByteArray(GiftTradeJournalCodec.MAX_BYTES + 1), store.bytes + 0.toByte(),
            text.replace("pending-v2", "pending-v3").toByteArray(),
            text.replace("\t1000\t", "\t01000\t").toByteArray(),
            text.dropLast(1).toByteArray(), (text + text.substringAfter('\n')).toByteArray(),
            text.replace("uncertain", "settled").toByteArray(),
            text.replace("\tbuy\t", "\taccept-offer\t").toByteArray())
        for (bytes in bad) reject { GiftTradeJournalCodec.decode(bytes) }
        reject { GiftTradeJournalCodec.encode(listOf(row, row.copy(intentId = "d".repeat(64)))) }
        store.bytes = "corrupt".toByteArray()
        reject { GiftTradeJournal(store).reserve(i, 1000) }
        assertEquals("corrupt", store.bytes.toString(Charsets.US_ASCII))
    }

    @Test fun reservationRejectsExpiryBeforeStorageCallback() {
        val store = Store(); val bytes = store.bytes.clone()
        reject { GiftTradeJournal(store).reserve(intent(), 1060) }
        reject { GiftTradeJournal(store).reserve(intent(), -1) }
        assertArrayEquals(bytes, store.bytes)
    }

    private fun evidence(i: GiftTradeBoundIntent) = GiftTradeHandoffEvidence(
        i.context, i.id, i.stateHash, 1000L, "software", allowed = true, cancelled = false)

    @Test fun cancellationReleasesOnlyNeverHandedOffClaim() {
        val store = Store(); val journal = GiftTradeJournal(store); val i = intent()
        // Old reserve API still has no release authority; persisted rows never recreate a handle.
        journal.reserve(i, 1000)
        reject { GiftTradeJournal(store).prepare(i, 1000) }
        val clean = Store(); val j = GiftTradeJournal(clean); val handle = j.prepare(i, 1000)
        assertTrue(handle.cancelBeforeHandoff()); assertFalse(handle.cancelBeforeHandoff())
        var calls = 0
        reject { handle.handoff({ 1000 }, ::evidence) { calls++ } }
        assertTrue(j.list(i.context).isEmpty())
        val fresh = j.prepare(i, 1000)
        assertEquals("ok", fresh.handoff({ 1001 }, ::evidence) { exact ->
            assertSame(i, exact); calls++; "ok"
        })
        assertFalse(fresh.cancelBeforeHandoff())
        reject { fresh.handoff({ 1001 }, ::evidence) { calls++ } }
        assertEquals(1, calls); assertEquals("uncertain", j.list(i.context).single().state)
    }

    @Test fun failedRecheckReleasesClaimWithoutExecution() {
        val i = intent()
        val invalid = listOf(
            evidence(i).copy(context = intent(account = 8).context),
            evidence(i).copy(context = intent(chain = "-3").context),
            evidence(i).copy(intentId = "d".repeat(64)), evidence(i).copy(stateHash = "d".repeat(64)),
            evidence(i).copy(observedAt = 984), evidence(i).copy(observedAt = 1001),
            evidence(i).copy(accountKind = "watch"), evidence(i).copy(allowed = false),
            evidence(i).copy(cancelled = true))
        var calls = 0
        for (bad in invalid) {
            val store = Store(); val journal = GiftTradeJournal(store); val h = journal.prepare(i, 1000)
            reject { h.handoff({ 1000 }, { bad }) { calls++ } }
            assertTrue(journal.list(i.context).isEmpty())
            reject { h.handoff({ 1000 }, ::evidence) { calls++ } }
        }
        val journal = GiftTradeJournal(Store()); val h = journal.prepare(i, 1000)
        reject { h.handoff({ 1060 }, ::evidence) { calls++ } }
        assertTrue(journal.list(i.context).isEmpty()); assertEquals(0, calls)
    }

    @Test fun reentrantCancellationAndHandoffCannotEscapeOneShotGate() {
        val journal = GiftTradeJournal(Store()); val i = intent(); var calls = 0
        val cancelled = journal.prepare(i, 1000)
        reject { cancelled.handoff({ 1000 }, { exact ->
            assertTrue(cancelled.cancelBeforeHandoff()); evidence(exact)
        }) { calls++ } }
        assertTrue(journal.list(i.context).isEmpty())
        val h = journal.prepare(i, 1000)
        h.handoff({ 1000 }, { exact ->
            reject { h.handoff({ 1000 }, ::evidence) { calls++ } }; evidence(exact)
        }) {
            assertFalse(h.cancelBeforeHandoff())
            reject { h.handoff({ 1000 }, ::evidence) { calls++ } }
            calls++
        }
        assertEquals(1, calls); assertEquals(1, journal.list(i.context).size)
    }

    @Test fun cancellationStorageErrorsCloseHandleAndPreserveUncertainty() {
        val i = intent(); var calls = 0
        for (afterCommit in listOf(false, true)) {
            val store = Store(); val journal = GiftTradeJournal(store); val h = journal.prepare(i, 1000)
            store.failCommit = !afterCommit; store.failAfterCommit = afterCommit
            reject { h.cancelBeforeHandoff() }
            store.failCommit = false; store.failAfterCommit = false
            reject { h.handoff({ 1000 }, ::evidence) { calls++ } }
            assertEquals(if (afterCommit) 0 else 1, journal.list(i.context).size)
        }
        val lost = Store(); lost.failAfterCommit = true
        reject { GiftTradeJournal(lost).prepare(i, 1000) }
        lost.failAfterCommit = false
        reject { GiftTradeJournal(lost).prepare(i, 1000) }
        assertEquals(0, calls)
    }

    @Test fun executorFailureNeverReleasesOrRetries() {
        val store = Store(); val journal = GiftTradeJournal(store); val i = intent()
        val h = journal.prepare(i, 1000); var calls = 0
        reject { h.handoff({ 1000 }, ::evidence) { calls++; error("Lost executor reply") } }
        assertFalse(h.cancelBeforeHandoff())
        reject { h.handoff({ 1000 }, ::evidence) { calls++ } }
        reject { GiftTradeJournal(store).prepare(i, 1001) }
        assertEquals(1, calls); assertEquals("uncertain", journal.list(i.context).single().state)
    }

    @Test fun competingCancellationAndHandoffHaveOnlyOneWinner() {
        val store = Store(); val journal = GiftTradeJournal(store); val i = intent()
        val h = journal.prepare(i, 1000); val start = CountDownLatch(1)
        val sends = AtomicInteger(); val cancels = AtomicInteger(); val unexpected = AtomicInteger()
        val workers = (1..12).map { n -> Thread {
            start.await()
            try {
                if (n % 2 == 0) { if (h.cancelBeforeHandoff()) cancels.incrementAndGet() }
                else h.handoff({ 1000 }, ::evidence) { sends.incrementAndGet() }
            } catch (_: IllegalStateException) { } catch (_: Throwable) { unexpected.incrementAndGet() }
        }.apply { start() } }
        start.countDown(); workers.forEach { it.join() }
        assertEquals(0, unexpected.get()); assertEquals(1, sends.get() + cancels.get())
        assertEquals(sends.get(), journal.list(i.context).size)
    }

    @Test fun staleCapabilityCannotRemoveRecreatedOrReconciledRow() {
        val store = Store(); val journal = GiftTradeJournal(store); val i = intent()
        val old = journal.prepare(i, 1000); val original = journal.list(i.context).single()
        // Simulate a terminal record evicted and an identical intent reserved in the same second.
        val replacement = original.copy(reservationId = "e".repeat(32))
        store.bytes = GiftTradeJournalCodec.encode(listOf(replacement))
        reject { old.cancelBeforeHandoff() }
        assertEquals(replacement, journal.list(i.context).single())
        val isolated = Store(); val j = GiftTradeJournal(isolated); val h = j.prepare(i, 1000)
        j.reserve(intent(account = 8), 1000)
        j.reconcile(i.context, i.id, "submitted", messageHash, 1001)
        reject { h.cancelBeforeHandoff() }
        assertEquals("submitted", j.list(i.context).single().state)
        assertEquals(1, j.list(intent(account = 8).context).size)
    }

    @Test fun legacyCodecPreservesUnresolvedRowsWithoutReleaseCapability() {
        val store = Store(); val i = intent(); GiftTradeJournal(store).reserve(i, 1000)
        val text = store.bytes.toString(Charsets.US_ASCII)
        val legacy = "wallet-gift-pending-v1\n" + text.substringAfter('\n').trimEnd()
            .split('\t').dropLast(1).joinToString("\t") + "\n"
        store.bytes = legacy.toByteArray(Charsets.US_ASCII)
        val journal = GiftTradeJournal(store)
        assertNull(journal.list(i.context).single().reservationId)
        reject { journal.prepare(i, 1000) }
        assertEquals("uncertain", journal.list(i.context).single().state)
        assertTrue(store.bytes.toString(Charsets.US_ASCII).startsWith("wallet-gift-pending-v2\n"))
        reject { GiftTradeJournalCodec.decode(text.replace(Regex("[a-f0-9]{32}\\n$"), "INVALID\n").toByteArray()) }
    }

    @Test fun recheckCanWaitForCancellationOnAnotherThreadWithoutHandoff() {
        val journal = GiftTradeJournal(Store()); val i = intent(); val h = journal.prepare(i, 1000)
        val worker = Executors.newSingleThreadExecutor(); var sends = 0
        try {
            reject { h.handoff({ 1000 }, {
                assertTrue(worker.submit<Boolean> { h.cancelBeforeHandoff() }.get(2, TimeUnit.SECONDS))
                evidence(it)
            }) { sends++ } }
        } finally { worker.shutdownNow() }
        assertEquals(0, sends); assertTrue(journal.list(i.context).isEmpty())
    }

    @Test fun executorCanWaitForAnotherThreadWithoutHoldingReservationMonitor() {
        val journal = GiftTradeJournal(Store()); val i = intent(); val h = journal.prepare(i, 1000)
        val worker = Executors.newSingleThreadExecutor()
        try {
            h.handoff({ 1000 }, ::evidence) {
                // The old synchronized callback deadlocked until this bounded wait expired.
                assertFalse(worker.submit<Boolean> { h.cancelBeforeHandoff() }.get(2, TimeUnit.SECONDS))
            }
        } finally { worker.shutdownNow() }
        assertEquals("uncertain", journal.list(i.context).single().state)
    }
}
