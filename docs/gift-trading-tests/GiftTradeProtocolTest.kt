package org.mytonwallet.app_air.walletcore.gifttrade

import org.junit.Assert.*
import org.junit.Test

class GiftTradeProtocolTest {
    @Test fun allActionsAndNetworksMatchSharedCorpus() {
        val expected = listOf(
            "3304be0d83e0f7f91b1760c53e48cf0bdd7138b1ac5623fa165a671e55586299",
            "c3e54c9ec3b2a8841e31e667d74bcfada8f2919004def3b19ef2f76fb0181f64",
            "d49a52e6cf94c7ae7fa47d9df5d92a00ec956c348a250b356ad5c7cad8b855ef",
            "7108c7387779c38ebd5ea82ad094168f0fd3564aa6f98ecd0406cef869698989",
            "2454c341ad6cba554ec8fef0131297324927cfbe381afac4a22b4b08e5b82a6e",
            "d03d929fe625a750d43835e7502056ab13123688e679effc30259cd2cc2e2632",
            "6d7f8ee1693bae5771661104102a1bda8e2f848927be14f2ad8d785f587c18c5",
            "12cf0710ccfee663a0f292a704d4247a7f2456085aadcafa4fd76ce8ea374d68",
            "04250890712033e25a5dcca8c8eaae844053286432c02f94de42eafdd3cdfc53",
            "a02b89ea08fa430e616b4666b7ba1656c89599c814a80e561e7f53f6fa10d3d3",
            "71c3e27f21093fca547091939b61d38192136e2697fc29821e11cbef3675f91f",
            "719042900cc3c53d47b5c0e865df5673130b480e3f10bbe86e42ec4756c7199f"
        )
        val actions = listOf("list", "buy", "cancel-sale", "make-offer", "accept-offer", "cancel-offer")
        val actual = listOf("-239", "-3").flatMap { network ->
            actions.map { action ->
                val kind = if ("offer" in action) "offer" else "sale"
                val amount = if (action.startsWith("cancel")) "0" else "9007199254740993"
                val init = if (action == "list") "AQAB" else null
                GiftTradeBoundIntent(GiftTradeContext(address(1), network),
                    GiftTradeReference(network, kind, address(2), address(3)), action,
                    address(4), amount, "0", "0", "500000001", 1060L, address(4), address(5),
                    "a".repeat(64), address(4), "wallet-market",
                    listOf(GiftTradeMessage(address(3), "500000001", "AAAA", init))).id
            }
        }
        assertEquals(expected, actual)
    }
    @Test fun recoveryDoesNotGuessFromTimeOrRepeatDelivery() {
        val state = GiftTradeRecoveryState(4, "7", address(1), address(2), "a".repeat(64), "b".repeat(64), 1000)
        for (phase in listOf(4, 8)) assertEquals(GiftTradeRecoveryDecision("reconcile", null), GiftTradeRecovery.decide(state.copy(phase = phase), address(1), setOf(state.codeHash), 1010))
        for (phase in listOf(3, 5, 6, 7)) assertEquals(GiftTradeRecoveryDecision("drive", "7"), GiftTradeRecovery.decide(state.copy(phase = phase), address(9), setOf(state.codeHash), 1010))
        assertEquals("8", GiftTradeRecovery.decide(state.copy(phase = 11), address(1), setOf(state.codeHash), 1010).query)
        reject { GiftTradeRecovery.decide(state.copy(phase = 11), address(9), setOf(state.codeHash), 1010) }
        reject { GiftTradeRecovery.decide(state, address(1), emptySet(), 1010) }
        reject { GiftTradeRecovery.decide(state, address(1), setOf(state.codeHash), 1016) }
        reject { GiftTradeRecovery.decide(state.copy(phase = 11, query = "18446744073709551615"), address(1), setOf(state.codeHash), 1010) }
    }
    private fun intent(messages: List<GiftTradeMessage> = listOf(GiftTradeMessage(address(3), "10500000000", "AAAA", null))) = GiftTradeBoundIntent(
        GiftTradeContext(address(1), "-239"), GiftTradeReference("-239", "sale", address(2), address(3)), "buy",
        address(4), "10000000000", "0", "100000000", "500000000", 1060L, address(4), address(5),
        "a".repeat(64), address(4), "wallet-market", messages)
    private fun address(n: Int) = "0:" + n.toString(16).padStart(64, '0')
    private fun reject(block: () -> Unit) {
        try { block() } catch (_: IllegalArgumentException) { return } catch (_: IllegalStateException) { return }
        fail("Expected rejection")
    }
    @Test fun canonicalReferenceAndTampering() {
        for (network in listOf("-239", "-3")) for (kind in listOf("sale", "offer")) {
            val ref = GiftTradeReference(network, kind, address(1), address(2))
            assertEquals(ref, GiftTradeReference.decode(ref.encode(), network))
            for (bad in listOf(ref.encode()+"&price=1", ref.encode()+"#", ref.encode()+"\n", ref.encode().replace("nft=0:", "nft=0%3A"))) {
                reject { GiftTradeReference.decode(bad, network) }
            }
            reject { GiftTradeReference.decode(ref.encode(), if (network == "-3") "-239" else "-3") }
        }
    }
    @Test fun exactAmounts() {
        assertEquals("9007199254740993000000001", GiftTradeAmounts.parseTon("9007199254740993.000000001"))
        assertEquals("1", GiftTradeAmounts.parseTon("0.000000001"))
        for (bad in listOf("0", "01", "-1", "1e3", "1,1", "1.0000000001", "1\n", "9999999999999999999999999999")) reject { GiftTradeAmounts.parseTon(bad) }
    }
    @Test fun cancellationAndSingleUse() {
        val scope = GiftTradeReviewScope(GiftTradeContext(address(1), "-239"))
        val first = scope.begin()
        val second = scope.begin()
        assertFalse(scope.isCurrent(first))
        reject { scope.consume(first) }
        reject { scope.checkAfterAwait(second) }
        scope.consume(second)
        reject { scope.consume(second) }
        scope.checkAfterAwait(second)
        scope.switchAccount(GiftTradeContext(address(2), "-3"))
        reject { scope.checkAfterAwait(second) }
    }
    @Test fun intentMatchesSharedVectorAndCopiesMessages() {
        val source = mutableListOf(GiftTradeMessage(address(3), "10500000000", "AAAA", null))
        val result = intent(source)
        assertEquals("f5b0c3fc219abc2fd8c38a5ff466a78e3a8f7eca9e69d2a6a333e5d6d023094f", result.id)
        source[0] = source[0].copy(to = address(9))
        assertEquals(address(3), result.messages[0].to)
        assertNotEquals(result.id, intent(source).id)
        reject { intent(listOf(GiftTradeMessage(address(3), "1", "!!!!", null))) }
        reject { result.checkTime(1060L) }
    }
    @Test fun finalBoundaryBindsIntentStateAndConsumesAttempt() {
        val result = intent()
        val scope = GiftTradeReviewScope(result.context)
        var calls = 0
        val token = scope.begin(result, 1000L); scope.consume(token)
        scope.complete(token, result.id, result.stateHash, 1000L, 1001L) { assertSame(result, it); calls++ }
        reject { scope.complete(token, result.id, result.stateHash, 1000L, 1001L) { calls++ } }
        for (bad in listOf("identity", "state", "age", "expiry", "account")) {
            val scope2 = GiftTradeReviewScope(result.context)
            val t = scope2.begin(result, 1000L); scope2.consume(t)
            if (bad == "account") scope2.switchAccount(GiftTradeContext(address(8), "-3"))
            reject { scope2.complete(t, if (bad == "identity") "b".repeat(64) else result.id,
                if (bad == "state") "b".repeat(64) else result.stateHash,
                if (bad == "age") 900L else 1000L, if (bad == "expiry") 1060L else 1001L) { calls++ } }
        }
        assertEquals(1, calls)
    }
    @Test fun scopeRejectsWrongThread() {
        val scope = GiftTradeReviewScope(GiftTradeContext(address(1), "-239"))
        var rejected = false
        val worker = Thread { try { scope.begin() } catch (_: IllegalStateException) { rejected = true } }
        worker.start(); worker.join(); assertTrue(rejected)
    }
    @Test fun buyerTotalsAndEligibility() {
        val result = intent()
        val cost = GiftTradePurchaseCost.review(result, "software", "10500000000", "0", "500000000", "50000000", 1000L)
        assertEquals("10500000000", cost.maximumDebit)
        assertEquals("100000000", cost.includedRoyalty) // included in price, not charged twice
        for (kind in listOf("watch-only", "unsupported")) reject { GiftTradePurchaseCost.review(result, kind, "10500000000", "0", "500000000", "50000000", 1000L) }
        reject { GiftTradePurchaseCost.review(result, "software", "10499999999", "0", "500000000", "50000000", 1000L) }
        reject { GiftTradePurchaseCost.review(result, "software", "20000000000", "1", "500000000", "50000000", 1000L) }
    }
}
