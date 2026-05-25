
import WalletContext

extension ApiUpdate {
    public struct DappDisconnected: Equatable, Hashable, Codable, Sendable {
        public var type = "dappDisconnected"
        public var url: String?
    }
}
