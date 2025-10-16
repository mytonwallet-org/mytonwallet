
import WalletContext

extension ApiUpdate {
    public struct OpenUrl: Equatable, Hashable, Codable, Sendable {
        public var type = "openUrl"
        public var url: String?
        public var isExternal: Bool?
        public var title: String?
        public var subtitle: String?
    }
}
