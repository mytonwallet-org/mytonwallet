import Dependencies
import Foundation
import Testing
@testable import UISwap
import WalletCore
import WalletContext

@Suite("Swap amount precision")
@MainActor
struct SwapAmountPrecisionTests {
    @Test(arguments: [SwapSide.selling, .buying])
    func `BSC USDT quote at full balance stays spendable`(side: SwapSide) async throws {
        let selling = ApiToken.BSC_USDT_MAINNET
        let buying = ApiToken.BNB
        let balance = try #require(BigInt("3896806132893454993"))
        let output = try #require(BigInt("6000000000000001"))
        let account = MAccount(
            id: "precision-mainnet", title: nil, type: .mnemonic,
            byChain: [.bnb: AccountChain(address: "bnb-address")]
        )
        let snapshot = SwapAccountSnapshot(account: account, balances: [
            selling.slug: balance,
            buying.slug: 1_000_000_000_000_000_000,
        ])
        let response = try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: Data("""
        {
          "route": "dex", "from": "\(selling.slug)", "to": "\(buying.slug)",
          "fromAmount": "3.896806132893454993", "toAmount": "0.006000000000000001",
          "toMinAmount": "0.0059", "impact": 0, "dieselStatus": "not-available",
          "networkFee": "0.00001", "realNetworkFee": "0.00001", "swapFee": "0",
          "swapFeePercent": 0, "ourFee": "0", "ourFeePercent": 0
        }
        """.utf8))
        let isMax = side == .selling
        let input = SwapEstimateInput(
            accountId: account.id, selling: TokenAmount(balance, selling), buying: TokenAmount(output, buying),
            inputSource: side, isMaxAmount: isMax, maxAmount: balance, slippage: 5
        )
        let flow = OnchainSwapFlow(
            validator: OnchainSwapValidator(),
            estimateEngine: OnchainSwapEstimateEngine(fetchEstimate: { _, request in
                if isMax {
                    #expect(request.fromAmount?.stringValue == "3.896806132893454993")
                }
                return response
            })
        )
        let update = try await flow.estimate(input, changedFrom: side, swapType: .onChain, account: snapshot)
        let model = withDependencies {
            $0[_TokenStore.self] = TokenStore
            $0[_BalancesStore.self] = .liveValue
        } operation: {
            SwapInputModel(
                sellingTokenSlug: selling.slug, buyingTokenSlug: buying.slug, tokenBalance: balance,
                accountContext: AccountContext(source: .constant(account))
            )
        }
        model.sellingAmount = isMax ? balance : nil
        model.buyingAmount = isMax ? nil : output
        model.isUsingMax = isMax
        update.apply(to: model)

        #expect(model.sellingAmount == balance)
        #expect(model.buyingAmount == output)
        if isMax {
            #expect(update.backendMaxAmount == balance)
            #expect(model.maxAmount == balance)
        }

        let validator = OnchainSwapValidator()
        let estimate = try #require(update.stateUpdate?.dexEstimate)
        func validationInput(amount: BigInt?) -> SwapValidationInput {
            SwapValidationInput(
                sellingToken: selling, buyingToken: buying, sellingAmount: amount,
                maxAmount: model.maxAmount, swapType: .onChain
            )
        }
        #expect(validator.validationIssue(
            input: validationInput(amount: model.sellingAmount), swapEstimate: estimate, account: snapshot
        ) == nil)
        #expect(validator.validationIssue(
            input: validationInput(amount: balance + 1), swapEstimate: estimate, account: snapshot
        ) == .insufficientBalance)
    }
}
