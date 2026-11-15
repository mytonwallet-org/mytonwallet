package org.mytonwallet.app_air.walletcore.gifttrade

import java.util.Collections
import java.util.UUID

/** Only public transaction identity is retained. No BOC, signature, key or NFT metadata. */
data class GiftTradePending(
    val intentId: String, val context: GiftTradeContext, val reference: GiftTradeReference,
    val action: String, val createdAt: Long, val updatedAt: Long,
    val state: String = "uncertain", val messageHash: String? = null,
    val reservationId: String? = null
)

/** Must execute once under an atomic durable read/write transaction, including across processes.
 * Return only after the commit. Throw on unavailable/corrupt storage; never substitute an empty list.
 */
interface GiftTradeJournalStore {
    fun <T> transact(update: (List<GiftTradePending>) -> Pair<List<GiftTradePending>, T>): T
    fun read(): List<GiftTradePending> = transact { it to it }
}

/** Supplied by the caller's trusted local revalidator, not by a provider response or persisted JSON.
 * Does not authenticate chain proofs. Native account, policy and cancellation integration is required.
 */
data class GiftTradeHandoffEvidence(
    val context: GiftTradeContext, val intentId: String, val stateHash: String,
    val observedAt: Long, val accountKind: String, val allowed: Boolean, val cancelled: Boolean
)

/** Process-local capability. Never persist/reconstruct it or hand messages to an executor another way.
 * After handoff begins, even an exception must be reconciled; cancellation cannot release that claim.
 */
interface GiftTradeReservation {
    fun cancelBeforeHandoff(): Boolean
    fun <T> handoff(clock: () -> Long, recheck: (GiftTradeBoundIntent) -> GiftTradeHandoffEvidence,
                    execute: (GiftTradeBoundIntent) -> T): T
}

object GiftTradeJournalCodec {
    const val CAPACITY = 100
    const val MAX_BYTES = 131072
    private const val HEADER = "wallet-gift-pending-v2\n"
    private const val LEGACY_HEADER = "wallet-gift-pending-v1\n"
    private val hash = Regex("[a-f0-9]{64}")
    private val time = Regex("0|[1-9][0-9]{0,9}")
    private val actions = setOf("list", "buy", "cancel-sale", "make-offer", "accept-offer", "cancel-offer")
    fun checkTime(value: Long) { require(value in 0L..0xffffffffL) }

    fun validate(records: List<GiftTradePending>): List<GiftTradePending> {
        require(records.size <= CAPACITY)
        val ids = HashSet<String>()
        val pending = HashSet<Triple<String, String, String>>()
        for (r in records) {
            require(hash.matches(r.intentId) && ids.add(r.intentId))
            GiftTradeContext(r.context.account, r.context.network)
            GiftTradeReference.decode(r.reference.encode(), r.context.network)
            require(r.action in actions)
            require(r.reference.kind == if (r.action in setOf("list", "buy", "cancel-sale")) "sale" else "offer")
            checkTime(r.createdAt); checkTime(r.updatedAt)
            require(r.updatedAt >= r.createdAt)
            require(r.state in setOf("uncertain", "submitted", "settled", "failed"))
            require(r.messageHash == null || hash.matches(r.messageHash))
            require(r.reservationId == null || Regex("[a-f0-9]{32}").matches(r.reservationId))
            require(r.state == "uncertain" || r.messageHash != null)
            if (r.state == "uncertain" || r.state == "submitted") {
                require(pending.add(Triple(r.context.account, r.context.network, r.reference.nft)))
            }
        }
        return Collections.unmodifiableList(records.toList())
    }

    fun encode(records: List<GiftTradePending>): ByteArray {
        val text = HEADER + validate(records).joinToString("") { r ->
            listOf(r.intentId, r.context.account, r.context.network, r.reference.encode(), r.action,
                r.createdAt.toString(), r.updatedAt.toString(), r.state, r.messageHash ?: "-",
                r.reservationId ?: "-").joinToString("\t") + "\n"
        }
        return text.toByteArray(Charsets.US_ASCII).also { require(it.size <= MAX_BYTES) }
    }

    fun decode(bytes: ByteArray): List<GiftTradePending> {
        require(bytes.size in HEADER.length..MAX_BYTES)
        require(bytes.all { it == 9.toByte() || it == 10.toByte() || it.toInt() in 32..126 })
        val text = bytes.toString(Charsets.US_ASCII)
        val legacy = text.startsWith(LEGACY_HEADER)
        require((legacy || text.startsWith(HEADER)) && text.endsWith("\n"))
        val body = text.substring(HEADER.length)
        if (body.isEmpty()) return emptyList()
        val lines = body.dropLast(1).split('\n')
        require(lines.size <= CAPACITY)
        return validate(lines.map { line ->
            val f = line.split('\t')
            require(f.size == (if (legacy) 9 else 10) && time.matches(f[5]) && time.matches(f[6]))
            val context = GiftTradeContext(f[1], f[2])
            GiftTradePending(f[0], context, GiftTradeReference.decode(f[3], context.network), f[4],
                f[5].toLong(), f[6].toLong(), f[7], f[8].takeUnless { it == "-" },
                if (legacy) null else f[9].takeUnless { it == "-" })
        })
    }
}

/** Synchronous storage work belongs on an IO executor, never the Android UI thread.
 * After reserving, the caller must recheck cancellation/account/policy/expiry before handoff.
 * This bounded journal is not a permanent replay ledger and cannot authenticate chain receipts.
 */
class GiftTradeJournal(private val store: GiftTradeJournalStore) {
    /** A lost commit response returns no capability: the persisted uncertain claim stays locked. */
    fun prepare(intent: GiftTradeBoundIntent, now: Long): GiftTradeReservation =
        Reservation(intent, reserve(intent, now))

    private inner class Reservation(
        private val intent: GiftTradeBoundIntent, private val original: GiftTradePending
    ) : GiftTradeReservation {
        // All paths share this monitor. CHECKING rejects reentrant handoff from validator callbacks.
        private var phase = "ready"

        private fun release() {
            store.transact { records ->
                val clean = GiftTradeJournalCodec.validate(records)
                check(clean.singleOrNull { it.intentId == original.intentId } == original) {
                    "Reservation changed; reconcile instead of deleting"
                }
                clean.filterNot { it.intentId == original.intentId } to Unit
            }
        }

        override fun cancelBeforeHandoff(): Boolean {
            synchronized(this) {
                if (phase != "ready" && phase != "checking") return false
                phase = "closed" // Consume BEFORE storage: failed/lost commit must never permit execution.
            }
            release()
            return true
        }

        override fun <T> handoff(
            clock: () -> Long, recheck: (GiftTradeBoundIntent) -> GiftTradeHandoffEvidence,
            execute: (GiftTradeBoundIntent) -> T
        ): T {
            synchronized(this) {
                check(phase == "ready") { "Reservation already consumed" }
                phase = "checking"
            }
            try {
                // Perform storage IO before the final recheck, never between recheck and execution.
                store.transact { records ->
                    val clean = GiftTradeJournalCodec.validate(records)
                    check(clean.singleOrNull { it.intentId == original.intentId } == original)
                    clean to Unit
                }
                val evidence = recheck(intent)
                val now = clock()
                synchronized(this) {
                check(phase == "checking") { "Reservation cancelled during recheck" }
                intent.checkTime(now)
                require(evidence.context == intent.context && evidence.intentId == intent.id)
                require(evidence.stateHash == intent.stateHash)
                require(evidence.accountKind in setOf("software", "hardware"))
                require(evidence.allowed && !evidence.cancelled)
                require(evidence.observedAt in 0L..now && now - evidence.observedAt <= 15L)
                phase = "handed-off" // Irreversible locally, including executor failure or lost reply.
                }
            } catch (error: Throwable) {
                val shouldRelease = synchronized(this) {
                    if (phase == "checking") { phase = "closed"; true } else false
                }
                if (shouldRelease) {
                    try { release() } catch (storageError: Throwable) {
                        if (storageError !== error) error.addSuppressed(storageError)
                    }
                }
                throw error
            }
            // Do not hold our monitor while invoking external code. It may wait for cancellation
            // or completion callbacks on another thread. Cancellation now returns false immediately.
            return execute(intent)
        }
    }

    fun reserve(intent: GiftTradeBoundIntent, now: Long): GiftTradePending {
        intent.checkTime(now)
        val row = GiftTradePending(intent.id, intent.context, intent.reference, intent.action, now, now,
            reservationId = UUID.randomUUID().toString().replace("-", ""))
        GiftTradeJournalCodec.validate(listOf(row))
        return store.transact { records ->
            val clean = GiftTradeJournalCodec.validate(records).toMutableList()
            check(clean.none { it.intentId == row.intentId || (it.context == row.context &&
                it.reference.nft == row.reference.nft && it.state in setOf("uncertain", "submitted")) }) {
                "Reconcile the previous operation first"
            }
            if (clean.size == GiftTradeJournalCodec.CAPACITY) {
                val oldest = clean.filter { it.state in setOf("settled", "failed") }.minByOrNull { it.updatedAt }
                check(oldest != null) { "Pending journal capacity reached" }
                clean.remove(oldest)
            }
            clean.add(row)
            GiftTradeJournalCodec.validate(clean) to row
        }
    }

    fun list(context: GiftTradeContext): List<GiftTradePending> =
        Collections.unmodifiableList(GiftTradeJournalCodec.validate(store.read()).filter { it.context == context })

    /** Only call after independent receipt verification; timeouts and absence of a receipt are not failure. */
    fun reconcile(context: GiftTradeContext, id: String, next: String, messageHash: String, now: Long) {
        GiftTradeJournalCodec.checkTime(now)
        require(next in setOf("submitted", "settled", "failed") && Regex("[a-f0-9]{64}").matches(messageHash))
        store.transact { records ->
            val clean = GiftTradeJournalCodec.validate(records)
            val previous = clean.singleOrNull { it.intentId == id && it.context == context }
            check(previous != null) { "No pending operation in this account" }
            check(previous.state in setOf("uncertain", "submitted") && now >= previous.updatedAt)
            check(previous.messageHash == null || previous.messageHash == messageHash)
            val updated = clean.map { if (it === previous) it.copy(state = next, messageHash = messageHash, updatedAt = now) else it }
            GiftTradeJournalCodec.validate(updated) to Unit
        }
    }
}
