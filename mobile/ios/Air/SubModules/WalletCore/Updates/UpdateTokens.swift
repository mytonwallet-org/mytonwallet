
import WalletContext
import WalletCoreTypes

extension ApiUpdate {
    public struct UpdateTokens: Equatable, Hashable, Codable, Sendable {
        public enum Kind: String, Equatable, Hashable, Codable, Sendable {
            case fromCache
            case full
            case partial

            public var arePricesFresh: Bool { self != .fromCache }
            public var isFull: Bool { self != .partial }
        }

        public var type = "updateTokens"
        public var kind: Kind
        public var tokens: [String: ApiToken]
        public var isIncomplete: Bool?
        public var unpricedSlugs: [String]?
        public var removedSlugs: [String]?
    }
}
