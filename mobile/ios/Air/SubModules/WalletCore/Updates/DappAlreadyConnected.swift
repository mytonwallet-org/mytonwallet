
import WalletContext

extension ApiUpdate {
    public struct DappAlreadyConnected: Equatable, Hashable, Codable, Sendable {
        public var type = "dappAlreadyConnected"
        public var url: String?
    }
}
