import WalletContext

extension ApiUpdate {
    public struct UpdateAccountDomainData: Equatable, Hashable, Codable, Sendable {
        public var type = "updateAccountDomainData"
        public var accountId: String
        public var expirationByAddress: [String: Int]
        public var linkedAddressByAddress: [String: String]
        public var nfts: [String: ApiNft]
    }
}
