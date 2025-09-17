
import WalletContext

extension ApiUpdate {
    public struct UpdateCurrencyRates: Equatable, Hashable, Sendable, Codable {
        public var type = "updateCurrencyRates"
        /// 1 USD equivalent to the amount of the other currency, e.g. 1 USD = 0.00000866 BTC
        /// Keys must be strings for because Swift decoding can't handle other types
        public var rates: [String: MDouble]
    }
}
