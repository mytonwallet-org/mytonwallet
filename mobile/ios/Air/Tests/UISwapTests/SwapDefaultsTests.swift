import Testing
@testable import UISwap
import WalletCore

@Suite("Swap defaults")
@MainActor
struct SwapDefaultsTests {
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
