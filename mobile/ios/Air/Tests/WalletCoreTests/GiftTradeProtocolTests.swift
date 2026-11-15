import XCTest
@testable import WalletCore

final class GiftTradeProtocolTests: XCTestCase {
    func testAllActionsAndNetworksMatchSharedCorpus() throws {
        let expected = [
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
        ]
        let actions = ["list", "buy", "cancel-sale", "make-offer", "accept-offer", "cancel-offer"]
        let actual = try ["-239", "-3"].flatMap { network in
            try actions.map { action in
                let kind = action.contains("offer") ? "offer" : "sale"
                let amount = action.hasPrefix("cancel") ? "0" : "9007199254740993"
                let result = try GiftTradeBoundIntent(account: address(1), network: network,
                    reference: GiftTradeReference(network: network, kind: kind, nft: address(2), contract: address(3)),
                    action: action, counterparty: address(4), amount: amount, fee: "0", royalty: "0",
                    gasBudget: "500000001", expiresAt: 1060, feeRecipient: address(4), royaltyRecipient: address(5),
                    stateHash: String(repeating: "a", count: 64), authority: address(4), provider: "wallet-market",
                    messages: [GiftTradeMessage(to: address(3), amount: "500000001", payload: "AAAA",
                        stateInit: action == "list" ? "AQAB" : nil)])
                return result.id
            }
        }
        XCTAssertEqual(actual, expected)
    }
    func testRecoveryNeverUsesTimeoutAsDeliveryFailure() throws {
        func state(_ phase: Int, _ query: String = "7") -> GiftTradeRecoveryState {
            GiftTradeRecoveryState(phase: phase, query: query, seller: address(1), initiator: address(2),
                codeHash: String(repeating: "a", count: 64), stateHash: String(repeating: "b", count: 64), observedAt: 1000)
        }
        let codes: Set<String> = [String(repeating: "a", count: 64)]
        for phase in [4, 8] {
            let decision = try GiftTradeRecovery.decide(state(phase), account: address(1), allowedCodeHashes: codes, now: 1010)
            XCTAssertEqual(decision.action, "reconcile"); XCTAssertNil(decision.query)
        }
        XCTAssertEqual(try GiftTradeRecovery.decide(state(11), account: address(1), allowedCodeHashes: codes, now: 1010).query, "8")
        XCTAssertThrowsError(try GiftTradeRecovery.decide(state(11), account: address(9), allowedCodeHashes: codes, now: 1010))
        XCTAssertThrowsError(try GiftTradeRecovery.decide(state(5), account: address(1), allowedCodeHashes: codes, now: 1016))
        XCTAssertThrowsError(try GiftTradeRecovery.decide(state(11, "18446744073709551615"), account: address(1), allowedCodeHashes: codes, now: 1010))
    }
    private func address(_ n: Int) -> String { "0:" + String(repeating: "0", count: 63) + String(n) }
    private func intent() throws -> GiftTradeBoundIntent {
        try GiftTradeBoundIntent(account: address(1), network: "-239",
            reference: GiftTradeReference(network: "-239", kind: "sale", nft: address(2), contract: address(3)),
            action: "buy", counterparty: address(4), amount: "10000000000", fee: "0", royalty: "100000000",
            gasBudget: "500000000", expiresAt: 1060, feeRecipient: address(4), royaltyRecipient: address(5),
            stateHash: String(repeating: "a", count: 64), authority: address(4), provider: "wallet-market",
            messages: [GiftTradeMessage(to: address(3), amount: "10500000000", payload: "AAAA", stateInit: nil)])
    }
    func testSharedIntentVector() throws {
        let result = try intent()
        XCTAssertEqual(result.id, "f5b0c3fc219abc2fd8c38a5ff466a78e3a8f7eca9e69d2a6a333e5d6d023094f")
        XCTAssertThrowsError(try result.checkTime(1060))
    }
    func testBuyerTotalsAndEligibility() throws {
        let value = try intent()
        let cost = try GiftTradePurchaseCost.review(value, accountKind: "software", spendableBalance: "10500000000",
            walletFeeReserve: "0", maxGasBudget: "500000000", maxWalletFeeReserve: "50000000", now: 1000)
        XCTAssertEqual(cost.maximumDebit, "10500000000")
        XCTAssertEqual(cost.includedRoyalty, "100000000")
        for kind in ["watch-only", "unsupported"] {
            XCTAssertThrowsError(try GiftTradePurchaseCost.review(value, accountKind: kind, spendableBalance: "10500000000",
                walletFeeReserve: "0", maxGasBudget: "500000000", maxWalletFeeReserve: "50000000", now: 1000))
        }
        XCTAssertThrowsError(try GiftTradePurchaseCost.review(value, accountKind: "software", spendableBalance: "10499999999",
            walletFeeReserve: "0", maxGasBudget: "500000000", maxWalletFeeReserve: "50000000", now: 1000))
    }
    @MainActor func testFinalBoundaryAndAccountChange() throws {
        let result = try intent()
        let scope = try GiftTradeReviewScope(account: address(1), network: "-239")
        var calls = 0
        let token = try scope.begin(intent: result, now: 1000)
        try scope.consume(token)
        try scope.complete(token, intentId: result.id, stateHash: result.stateHash, observedAt: 1000, now: 1001) { value in
            XCTAssertEqual(value, result); calls += 1
        }
        XCTAssertThrowsError(try scope.complete(token, intentId: result.id, stateHash: result.stateHash, observedAt: 1000, now: 1001) { _ in calls += 1 })
        let other = try scope.begin(intent: result, now: 1000)
        try scope.consume(other)
        try scope.switchAccount(account: address(8), network: "-3")
        XCTAssertThrowsError(try scope.complete(other, intentId: result.id, stateHash: result.stateHash, observedAt: 1000, now: 1001) { _ in calls += 1 })
        XCTAssertEqual(calls, 1)
    }

    func testCanonicalReferenceAndTampering() throws {
        for network in ["-239", "-3"] {
            for kind in ["sale", "offer"] {
                let ref = try GiftTradeReference(network: network, kind: kind, nft: address(1), contract: address(2))
                XCTAssertEqual(try GiftTradeReference.decode(ref.encoded, expectedNetwork: network), ref)
                for bad in [ref.encoded + "&price=1", ref.encoded + "#", ref.encoded + "\n", ref.encoded.replacingOccurrences(of: "nft=0:", with: "nft=0%3A")] {
                    XCTAssertThrowsError(try GiftTradeReference.decode(bad, expectedNetwork: network))
                }
                XCTAssertThrowsError(try GiftTradeReference.decode(ref.encoded, expectedNetwork: network == "-3" ? "-239" : "-3"))
            }
        }
    }
    func testExactAmounts() throws {
        XCTAssertEqual(try GiftTradeAmounts.parseTon("9007199254740993.000000001"), "9007199254740993000000001")
        XCTAssertEqual(try GiftTradeAmounts.parseTon("0.000000001"), "1")
        for bad in ["0", "01", "-1", "1e3", "1,1", "1.0000000001", "1\n", "9999999999999999999999999999"] {
            XCTAssertThrowsError(try GiftTradeAmounts.parseTon(bad))
        }
    }
    @MainActor func testCancellationAndSingleUse() throws {
        let scope = try GiftTradeReviewScope(account: address(1), network: "-239")
        let first = scope.begin()
        let second = scope.begin()
        XCTAssertFalse(scope.isCurrent(first))
        XCTAssertThrowsError(try scope.consume(first))
        XCTAssertThrowsError(try scope.checkAfterAwait(second))
        try scope.consume(second)
        XCTAssertThrowsError(try scope.consume(second))
        try scope.checkAfterAwait(second)
        try scope.switchAccount(account: address(2), network: "-3")
        XCTAssertThrowsError(try scope.checkAfterAwait(second))
    }
}
