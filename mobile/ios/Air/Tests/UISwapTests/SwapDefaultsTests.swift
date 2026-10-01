import Dependencies
import Testing
@testable import UISwap
import WalletCore

@Suite("Swap defaults")
@MainActor
struct SwapDefaultsTests {
    @Test
    func `Mint buy amount stays authoritative without focusing either field`() throws {
        try withDependencies {
            $0[_TokenStore.self] = TokenStore
            $0[_BalancesStore.self] = .liveValue
        } operation: {
            let delegate = Delegate()
            let model = SwapModel(
                delegate: delegate,
                defaults: .init(tokenIn: .TONCOIN, tokenOut: .MYCOIN),
                defaultSellingAmount: nil,
                defaultBuyingAmount: 1_312.5,
                accountContext: AccountContext(source: .constant(MAccount(
                    id: "mint-prefill-mainnet", title: nil, type: .mnemonic,
                    byChain: [.ton: .init(address: "sender")]
                )))
            )
            model.setStage(.confirming)
            let input = model.input
            input.focusInitialInput()
            #expect(!input.sellingFocused)
            #expect(!input.buyingFocused)
            #expect(input.inputSource == .buying)
            let request = try #require(SwapEstimateRequest.derive(
                accountId: "mint-prefill-mainnet", input: input, isValidPair: true, slippage: 5
            ))
            #expect(request.side == .buying)
            #expect(request.amount == .exact(1_312_500_000_000))

            input.updateWithEstimate(.init(changedFrom: .buying, fromAmount: 10, toAmount: 1_312.5))
            #expect(input.sellingAmount == 10_000_000_000)
            #expect(input.buyingAmount == 1_312_500_000_000)
            #expect(SwapEstimateRequest.derive(
                accountId: "mint-prefill-mainnet", input: input, isValidPair: true, slippage: 5
            ) == request)

            input.userEditedAmount(20_000_000_000, side: .selling)
            #expect(input.inputSource == .selling)
            input.focusInitialInput()
            #expect(input.sellingFocused)
            #expect(!input.buyingFocused)
        }
    }

    @Test
    func `a missing token disables the action even if a ready state is requested`() {
        for defaults in [
            ApiSwapDefaults(tokenIn: nil, tokenOut: ApiChain.ethereum.nativeToken),
            ApiSwapDefaults(tokenIn: ApiChain.solana.nativeToken, tokenOut: nil)
        ] {
            let configuration = SwapButtonModel().configuration(
                for: .readyToSwap, sellingToken: defaults.tokenIn, buyingToken: defaults.tokenOut
            )
            #expect(!configuration.isEnabled)
        }
    }
}

@MainActor private final class Delegate: SwapModelDelegate {
    func executeSwapCommand(_ command: SwapCommand) {}
}
