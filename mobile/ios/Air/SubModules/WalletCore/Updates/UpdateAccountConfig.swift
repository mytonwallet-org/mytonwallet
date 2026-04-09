import Foundation

extension ApiUpdate {
    public struct UpdateAccountConfig: Equatable, Hashable, Codable, Sendable {
        public var type = "updateAccountConfig"
        public var accountId: String
        public var accountConfig: ApiAccountConfig
    }
}
