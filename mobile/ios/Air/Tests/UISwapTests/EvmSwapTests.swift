import Foundation
import Testing
@testable import UISwap
import WalletCore
import WalletContext

@Suite("EVM Swaps")
@MainActor
struct EvmSwapTests {
    @Test(arguments: [ApiChain.ethereum, .base, .bnb, .polygon, .arbitrum, .monad, .avalanche, .robinhood, .arc])
    func `same chain EVM pairs use DEX estimation and sell amount input`(chain: ApiChain) {
        let selling = chain.nativeToken
        let buyingSlug = "\(chain.rawValue)-0x1111111111111111111111111111111111111111"
        let swapType = getSwapType(from: selling.slug, to: buyingSlug, accountChains: [chain])

        #expect(swapType == .onChain)
        #expect(resolveBuyAmountInputMode(swapType: swapType, sellingChain: chain, isReverseProhibited: false) == .disabled)
    }

    @Test
    func `unsupported and cross chain pairs keep CEX routing`() {
        #expect(!ApiChain.hyperliquid.isOnchainSwapSupported)
        #expect(getSwapType(from: HYPERLIQUID_SLUG, to: HYPERLIQUID_USDC_MAINNET_SLUG, accountChains: [.hyperliquid]) == .crosschainInsideWallet)
        #expect(getSwapType(from: ETH_SLUG, to: BASE_SLUG, accountChains: [.ethereum, .base]) == .crosschainInsideWallet)
    }

    @Test(arguments: [true, false])
    func `Uniswap quote builds and submits with its approval requirement`(needsApprove: Bool) async throws {
        let response = try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: Data("""
        {
          "route": "dex", "chain": "ethereum", "dexRouterLabel": "uniswap",
          "from": "ethereum-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "to": "eth",
          "fromAmount": "20", "toAmount": "0.01", "toMinAmount": "0.0099",
          "slippage": 1, "impact": 0.1, "dieselStatus": "not-available",
          "networkFee": "0.0001", "realNetworkFee": "0.0001",
          "swapFee": "0", "swapFeePercent": 0, "ourFee": "0.00008", "ourFeePercent": 0.8,
          "needsApprove": \(needsApprove), "other": []
        }
        """.utf8))
        guard case .dex(let estimate) = response else {
            Issue.record("Expected Uniswap DEX quote")
            return
        }
        #expect(estimate.dexLabel == nil)
        #expect(estimate.dexRouterLabel == "uniswap")
        #expect(SwapBatchTxPolicy.isBatchTx(estimate: estimate, sellingToken: .ETH_USDC_MAINNET) == needsApprove)

        let buildResponse = try JSONDecoder().decode(ApiSwapBuildResponse.self, from: Data("""
        {
          "id": "swap-id", "chain": "ethereum", "transaction": "uniswap-payload",
          "calls": [{"to": "0x2222222222222222222222222222222222222222", "value": "0", "data": "0x1234"}],
          "isBatchTx": true
        }
        """.utf8))
        let account = SwapAccountSnapshot(
            account: MAccount(id: "test-mainnet", title: nil, type: .mnemonic, byChain: [
                .ton: AccountChain(address: "ton-history-address"),
                .ethereum: AccountChain(address: "0x3333333333333333333333333333333333333333"),
            ]),
            balances: [:]
        )
        var didSubmit = false
        let executor = OnchainSwapExecutor(
            buildTransfer: { accountId, enclaveToken, request in
                #expect(accountId == account.id)
                #expect(enclaveToken == "test-token")
                #expect(request.fromAddress == account.getAddress(chain: .ethereum))
                #expect(request.historyAddress == "ton-history-address")
                #expect(request.dexRouterLabel == "uniswap")
                #expect(request.needsApprove == needsApprove)
                #expect(request.swapMode == .exactIn)
                return buildResponse
            },
            submit: { chain, accountId, enclaveToken, transfers, history, isGasless, transaction, calls, approval in
                didSubmit = true
                #expect(chain == .ethereum)
                #expect(accountId == account.id)
                #expect(enclaveToken == "test-token")
                #expect(transfers == nil)
                #expect(history.id == "swap-id")
                #expect(isGasless == false)
                #expect(transaction == "uniswap-payload")
                #expect(calls == buildResponse.calls)
                #expect(approval == needsApprove)
                return try JSONDecoder().decode(ApiSwapSubmitResult.self, from: Data(#"{"swapId":"swap-id"}"#.utf8))
            }
        )
        let result = try await executor.performSwap(
            swapEstimate: estimate,
            swapMode: .exactIn,
            confirmation: SwapConfirmationAmounts(selling: TokenAmount(20_000_000, .ETH_USDC_MAINNET), buying: TokenAmount(10_000_000_000_000_000, .ETH)),
            maxAmount: nil,
            slippage: 1,
            account: account,
            enclaveToken: "test-token"
        )
        #expect(didSubmit)
        #expect(result.swapId == "swap-id")
    }
}
