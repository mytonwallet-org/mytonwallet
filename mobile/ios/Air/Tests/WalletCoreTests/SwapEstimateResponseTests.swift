import Foundation
import Testing
@testable import WalletCore

@Suite("Swap Estimate Response")
struct SwapEstimateResponseTests {
    @Test
    func `decodes DEX route`() throws {
        let response = try decodeResponse("""
        {
          "route": "dex",
          "from": "TON",
          "to": "USDT",
          "fromAmount": "1",
          "toAmount": "2",
          "toMinAmount": "1.9",
          "impact": 0.1,
          "dexLabel": "dedust",
          "dieselStatus": "not-available",
          "networkFee": "0.01",
          "realNetworkFee": "0.005",
          "swapFee": "0",
          "swapFeePercent": 0,
          "ourFee": "0",
          "ourFeePercent": 0
        }
        """)

        guard case .dex(let estimate) = response else {
            Issue.record("Expected DEX estimate")
            return
        }
        #expect(estimate.fromAmount == 1)
        #expect(estimate.toAmount == 2)
        #expect(estimate.dexLabel == .dedust)
    }

    @Test
    func `decodes router DEX route without venue label`() throws {
        let response = try decodeResponse("""
        {
          "route": "dex",
          "chain": "ton",
          "dexRouterLabel": "dedust-router-v2",
          "from": "MY",
          "to": "USDT",
          "fromAmount": "50",
          "toAmount": "2.09749",
          "toMinAmount": "1.992615",
          "impact": 0.21,
          "dieselStatus": "not-available",
          "networkFee": "0.315",
          "realNetworkFee": "0.03",
          "swapFee": "0",
          "swapFeePercent": 0,
          "ourFee": "0",
          "ourFeePercent": 0,
          "hint": { "type": "betterRate", "additionalAmount": "0.01", "symbol": "GRAM" }
        }
        """)

        guard case .dex(let estimate) = response else {
            Issue.record("Expected DEX estimate")
            return
        }
        #expect(estimate.dexLabel == nil)
        #expect(estimate.dexRouterLabel == "dedust-router-v2")
        #expect(estimate.hint?.type == "betterRate")
        #expect(estimate.hint?.additionalAmount == "0.01")
        #expect(estimate.hint?.symbol == "GRAM")
    }

    @Test
    func `decodes CEX route`() throws {
        let response = try decodeResponse("""
        {
          "route": "cex",
          "cexLabel": "near-intents",
          "from": "ETH",
          "fromAmount": "1",
          "to": "TON",
          "toAmount": "100",
          "swapFee": "0.1",
          "fromMin": "0.01",
          "fromMax": "10",
          "hint": { "type": "oneToOne", "minimumAmount": "30" }
        }
        """)

        guard case .cex(let estimate) = response else {
            Issue.record("Expected CEX estimate")
            return
        }
        #expect(estimate.cexLabel == .nearIntents)
        #expect(estimate.fromMin == 0.01)
        #expect(estimate.fromMax == 10)
        #expect(estimate.hint?.minimumAmount == "30")
    }

    @Test
    func `rejects response without route`() {
        #expect(throws: DecodingError.self) {
            try decodeResponse("""
            {
              "from": "TON",
              "to": "USDT"
            }
            """)
        }
    }
}

private func decodeResponse(_ json: String) throws -> ApiSwapEstimateResponse {
    try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: Data(json.utf8))
}
