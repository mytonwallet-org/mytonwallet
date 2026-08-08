import GRDB

struct MAccountHiddenNft: Codable, FetchableRecord, PersistableRecord, Sendable {
    let accountId: String
    let chain: String
    let nftAddress: String

    static let databaseTableName = "account_hidden_nfts"
}
