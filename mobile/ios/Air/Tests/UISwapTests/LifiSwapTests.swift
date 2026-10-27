import Foundation
import Testing
@testable import UISwap
import WalletCore
import WalletContext

@Suite("EVM swap build requests")
@MainActor
struct LifiSwapTests {
    @Test(arguments: [false, true])
    func `submit forwards the built EVM request and batch requirement`(needsBatch: Bool) async throws {
        var quote = try estimate()
        quote.needsBatch = !needsBatch
        let build = try JSONDecoder().decode(ApiSwapBuildResponse.self, from: Data("""
        {
          "id": "lifi-swap", "chain": "ethereum", "needsBatch": \(needsBatch),
          "transactionRequest": {
            "from": "0xsender", "to": "0xrouter", "chainId": 1, "data": "0x1234",
            "value": "0x123456789abcdef", "gasLimit": "123456", "gasPrice": "9007199254740993",
            "maxFeePerGas": "9007199254740995", "maxPriorityFeePerGas": "1234567890"
          }
        }
        """.utf8))

        var submitted = false
        let executor = OnchainSwapExecutor(
            buildTransfer: { _, _, request in
                #expect(request.toAddress == "0xrecipient")
                #expect(request.needsBatch == !needsBatch)
                return build
            },
            submit: { _, _, _, _, _, _, transaction, _, transactionRequest, batch in
                submitted = true
                #expect(transaction == nil)
                #expect(transactionRequest?.to == "0xrouter")
                #expect(transactionRequest?.chainId == 1)
                #expect(transactionRequest?.value == "0x123456789abcdef")
                #expect(transactionRequest?.gasPrice == "9007199254740993")
                #expect(batch == needsBatch)
                return try JSONDecoder().decode(ApiSwapSubmitResult.self, from: Data(#"{"swapId":"lifi-swap"}"#.utf8))
            }
        )
        let result = try await executor.performSwap(
            swapEstimate: quote, swapMode: .exactIn,
            confirmation: .init(selling: TokenAmount.fromDouble(1, .ETH), buying: TokenAmount.fromDouble(0.99, ApiChain.base.nativeToken)),
            maxAmount: nil, slippage: 1, account: account(), enclaveToken: "test-token"
        )
        #expect(submitted)
        #expect(result.swapId == "lifi-swap")
    }

    private func estimate() throws -> ApiSwapDexEstimateResponse {
        try JSONDecoder().decode(ApiSwapDexEstimateResponse.self, from: Data("""
        {
          "route":"dex", "chain":"ethereum", "dexRouterLabel":"lifi",
          "from":"eth", "to":"\(BASE_SLUG)", "fromAmount":"1", "toAmount":"0.99", "toMinAmount":"0.98",
          "impact":0.1, "dieselStatus":"not-available", "networkFee":"0.01", "realNetworkFee":"0.005",
          "swapFee":"0", "swapFeePercent":0, "ourFee":"0", "ourFeePercent":0, "needsApprove":true
        }
        """.utf8))
    }

    private func account() -> SwapAccountSnapshot {
        SwapAccountSnapshot(
            account: MAccount(id: "test-mainnet", title: nil, type: .mnemonic, byChain: [
                .ton: AccountChain(address: "ton-history"),
                .ethereum: AccountChain(address: "0xsender"),
                .base: AccountChain(address: "0xrecipient"),
            ]),
            balances: [ETH_SLUG: TokenAmount.fromDouble(1, .ETH).amount]
        )
    }
}
