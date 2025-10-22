
import WalletContext

extension ApiUpdate {
    public struct DappLoading: Equatable, Hashable, Codable, Sendable {
        public var type = "dappLoading"
        public var connectionType: ApiDappConnectionType
        public var isSse: Bool?
        public var accountId: String?
    }
}
