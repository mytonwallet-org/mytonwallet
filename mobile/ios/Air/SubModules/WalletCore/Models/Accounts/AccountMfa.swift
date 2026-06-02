import Foundation

public struct AccountMfa: Equatable, Hashable, Sendable, Codable {
    public struct User: Equatable, Hashable, Sendable, Codable {
        public var id: String?
        public var name: String
        public var username: String?
        public var avatarUrl: String?

        public init(
            id: String? = nil,
            name: String,
            username: String? = nil,
            avatarUrl: String? = nil
        ) {
            self.id = id
            self.name = name
            self.username = username
            self.avatarUrl = avatarUrl
        }
    }

    public var address: String
    public var user: User?

    public init(address: String, user: User? = nil) {
        self.address = address
        self.user = user
    }
}
