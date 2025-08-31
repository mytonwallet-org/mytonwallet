
import Foundation
import WalletContext

extension Api {
    /// update tokens and prices (on base currency change)
    public static func tryUpdateTokenPrices() {
        Task {
            do {
                try await bridge.callApiVoid("tryUpdatePrices")
                try await bridge.callApiVoid("tryUpdateTokens")
                try await bridge.callApiVoid("tryUpdateSwapTokens")
            } catch {
            }
        }
    }
}
