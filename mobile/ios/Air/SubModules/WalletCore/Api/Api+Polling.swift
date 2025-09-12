
import Foundation
import WalletContext

extension Api {
    /// update tokens and prices (on base currency change)
    public static func tryUpdateTokens() async throws {
        try await bridge.callApiVoid("tryUpdateTokens")
        try await bridge.callApiVoid("tryUpdateSwapTokens")
    }
}
