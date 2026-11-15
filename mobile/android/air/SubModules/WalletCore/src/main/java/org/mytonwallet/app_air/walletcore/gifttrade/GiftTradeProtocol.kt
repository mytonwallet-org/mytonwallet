package org.mytonwallet.app_air.walletcore.gifttrade

import java.math.BigInteger
import java.security.MessageDigest
import java.util.Collections

/** Experimental references only; this module never signs or submits transactions. */
data class GiftTradeReference(val network: String, val kind: String, val nft: String, val contract: String) {
    fun encode(): String {
        require(network == "-239" || network == "-3")
        require(kind == "sale" || kind == "offer")
        require(ADDRESS.matches(nft) && ADDRESS.matches(contract))
        return "ton-gift-trade://v1/$kind?network=$network&nft=$nft&contract=$contract"
    }

    companion object {
        private val ADDRESS = Regex("0:[0-9a-f]{64}")
        private val REFERENCE = Regex("ton-gift-trade://v1/(sale|offer)\\?network=(-239|-3)&nft=(0:[0-9a-f]{64})&contract=(0:[0-9a-f]{64})")

        fun decode(text: String, expectedNetwork: String): GiftTradeReference {
            require(text.length <= 256)
            val match = requireNotNull(REFERENCE.matchEntire(text))
            val (kind, network, nft, contract) = match.destructured
            require(network == expectedNetwork)
            return GiftTradeReference(network, kind, nft, contract)
        }
    }
}

object GiftTradeAmounts {
    private val maximum = BigInteger.ONE.shiftLeft(120).subtract(BigInteger.ONE)

    fun parseTon(text: String): String {
        require(Regex("(0|[1-9][0-9]{0,27})(\\.[0-9]{1,9})?").matches(text))
        val parts = text.split('.')
        val nano = BigInteger(parts[0]).multiply(BigInteger("1000000000"))
            .add(BigInteger(parts.getOrElse(1) { "" }.padEnd(9, '0')))
        require(nano.signum() > 0 && nano <= maximum)
        return nano.toString()
    }
}

data class GiftTradeContext(val account: String, val network: String) {
    init {
        require(Regex("0:[0-9a-f]{64}").matches(account))
        require(network == "-239" || network == "-3")
    }
}

/** UI-thread confined. Tokens reject late results and are consumed before an asynchronous recheck. */
class GiftTradeReviewScope(initial: GiftTradeContext) {
    class Token internal constructor(val generation: Long, val context: GiftTradeContext, val intent: GiftTradeBoundIntent? = null)
    private val thread = Thread.currentThread()
    private var context = initial
    private var generation = 0L
    private var active: Token? = null
    private var consumed: Token? = null

    private fun assertThread() { check(Thread.currentThread() === thread) }
    fun cancel() {
        assertThread()
        generation = Math.addExact(generation, 1L)
        active = null
        consumed = null
    }
    fun switchAccount(next: GiftTradeContext) { cancel(); context = next }
    fun begin(): Token {
        cancel()
        return Token(generation, context).also { active = it }
    }
    fun begin(intent: GiftTradeBoundIntent, now: Long): Token {
        cancel()
        require(intent.context == context)
        intent.checkTime(now)
        return Token(generation, context, intent).also { active = it }
    }
    fun isCurrent(token: Token): Boolean {
        assertThread()
        return active === token && token.generation == generation && token.context == context
    }
    fun consume(token: Token) {
        check(isCurrent(token))
        active = null
        consumed = token
    }
    fun checkAfterAwait(token: Token) {
        assertThread()
        check(consumed === token && token.generation == generation && token.context == context)
    }
    /** Trusted local validator supplies evidence; there is no signer or network operation here. */
    fun complete(token: Token, intentId: String, stateHash: String, observedAt: Long, now: Long,
                 handoff: (GiftTradeBoundIntent) -> Unit) {
        checkAfterAwait(token)
        consumed = null // Failure also consumes this attempt.
        val intent = requireNotNull(token.intent)
        intent.checkTime(now)
        require(intent.id == intentId && intent.stateHash == stateHash)
        require(observedAt >= 0L && observedAt <= now && now - observedAt <= 15L)
        handoff(intent) // synchronous, exact immutable plan; no asynchronous gap
    }
}

data class GiftTradeMessage(val to: String, val amount: String, val payload: String?, val stateInit: String?)

/** Immutable, platform-independent confirmation binding. Does not decode BOCs or authenticate chain proofs. */
class GiftTradeBoundIntent(
    val context: GiftTradeContext, val reference: GiftTradeReference, val action: String,
    val counterparty: String, val amount: String, val fee: String, val royalty: String,
    val gasBudget: String, val expiresAt: Long, val feeRecipient: String, val royaltyRecipient: String,
    val stateHash: String, val authority: String, val provider: String, messages: List<GiftTradeMessage>
) {
    val messages: List<GiftTradeMessage> = Collections.unmodifiableList(messages.toList())
    val id: String
    init {
        require(action in listOf("list", "buy", "cancel-sale", "make-offer", "accept-offer", "cancel-offer"))
        require(reference.network == context.network)
        require(reference.kind == if (action in listOf("list", "buy", "cancel-sale")) "sale" else "offer")
        for (a in listOf(counterparty, feeRecipient, royaltyRecipient, authority)) require(Regex("0:[0-9a-f]{64}").matches(a))
        val price = coins(amount, !action.startsWith("cancel"))
        val fees = coins(fee) + coins(royalty)
        coins(gasBudget)
        require(action.startsWith("cancel") || fees < price)
        require(expiresAt in 0L..0xffffffffL)
        require(Regex("[a-f0-9]{64}").matches(stateHash) && Regex("[a-z][a-z0-9-]{0,31}").matches(provider))
        require(this.messages.size in 1..4)
        var total = BigInteger.ZERO
        for (m in this.messages) {
            require(Regex("0:[0-9a-f]{64}").matches(m.to)); total += coins(m.amount, true)
            for (cell in listOf(m.payload, m.stateInit)) if (cell != null) require(cell.isNotEmpty() && cell.length <= 65536 && cell.length % 4 == 0 && Regex("[A-Za-z0-9+/]+={0,2}").matches(cell))
        }
        coins(total.toString(), true)
        val fields = listOf("wallet-gift-intent-v2", action, context.account, context.network, reference.encode(),
            counterparty, amount, fee, royalty, gasBudget, expiresAt.toString(), feeRecipient, royaltyRecipient,
            stateHash, authority, provider, context.account, context.network, expiresAt.toString(), this.messages.size.toString()) +
            this.messages.flatMap { listOf(it.to, it.amount, it.payload ?: "-", it.stateInit ?: "-") }
        require(fields.all { f -> f.all { it.code in 32..126 } })
        val wire = fields.joinToString("") { "${it.length}:$it" }.toByteArray(Charsets.UTF_8)
        id = MessageDigest.getInstance("SHA-256").digest(wire).joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    fun checkTime(now: Long) { require(now in 0L..0xffffffffL && expiresAt > now && expiresAt - now <= 300L) }
    private fun coins(value: String, positive: Boolean = false): BigInteger {
        require(Regex("0|[1-9][0-9]{0,36}").matches(value))
        val result = BigInteger(value)
        require(result < BigInteger.ONE.shiftLeft(120) && (!positive || result.signum() > 0))
        return result
    }
}

/** Buyer display/eligibility checks only. Not a hardware/software signer or an account-state reader. */
data class GiftTradePurchaseCost(val price: String, val includedFee: String, val includedRoyalty: String,
                                 val gasBudget: String, val walletFeeReserve: String, val maximumDebit: String) {
    companion object {
        fun review(intent: GiftTradeBoundIntent, accountKind: String, spendableBalance: String,
                   walletFeeReserve: String, maxGasBudget: String, maxWalletFeeReserve: String, now: Long): GiftTradePurchaseCost {
            intent.checkTime(now)
            require(intent.action == "buy" && accountKind in listOf("software", "hardware"))
            fun nano(value: String): BigInteger {
                require(Regex("0|[1-9][0-9]{0,36}").matches(value))
                return BigInteger(value).also { require(it < BigInteger.ONE.shiftLeft(120)) }
            }
            val price = nano(intent.amount); val gas = nano(intent.gasBudget); val walletFee = nano(walletFeeReserve)
            val sent = intent.messages.fold(BigInteger.ZERO) { total, m -> total + nano(m.amount) }
            require(sent >= price && sent - price + walletFee == gas)
            require(gas <= nano(maxGasBudget) && walletFee <= nano(maxWalletFeeReserve))
            val total = nano((sent + walletFee).toString()); require(total <= nano(spendableBalance))
            return GiftTradePurchaseCost(intent.amount, intent.fee, intent.royalty, intent.gasBudget, walletFeeReserve, total.toString())
        }
    }
}

data class GiftTradeRecoveryState(val phase: Int, val query: String, val seller: String,
    val initiator: String, val codeHash: String, val stateHash: String, val observedAt: Long)
data class GiftTradeRecoveryDecision(val action: String, val query: String?)
/** Requires independently authenticated state. Never authorizes a timeout refund or sends a message. */
object GiftTradeRecovery {
    fun decide(state: GiftTradeRecoveryState, account: String, allowedCodeHashes: Set<String>, now: Long): GiftTradeRecoveryDecision {
        require(listOf(account, state.seller, state.initiator).all { Regex("0:[a-f0-9]{64}").matches(it) })
        require(listOf(state.codeHash, state.stateHash).all { Regex("[a-f0-9]{64}").matches(it) })
        require(state.codeHash in allowedCodeHashes && state.phase in 0..11)
        require(now in 0L..0xffffffffL && state.observedAt in 0L..now && now - state.observedAt <= 15L)
        require(Regex("0|[1-9][0-9]{0,19}").matches(state.query))
        val query = BigInteger(state.query); val maximum = BigInteger.ONE.shiftLeft(64) - BigInteger.ONE
        require(query <= maximum)
        return when (state.phase) {
            4, 8 -> GiftTradeRecoveryDecision("reconcile", null)
            3, 5, 6, 7 -> GiftTradeRecoveryDecision("drive", state.query)
            11 -> {
                require(account == state.seller || account == state.initiator)
                require(query < maximum)
                GiftTradeRecoveryDecision("retry-return", (query + BigInteger.ONE).toString())
            }
            else -> GiftTradeRecoveryDecision("none", null)
        }
    }
}
