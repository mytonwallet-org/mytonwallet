import Foundation
import GRDB
import OrderedCollections
import WalletContext

public struct MAccountDomains: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public let accountId: String
    public var expirationByAddress: [String: Int]
    public var linkedAddressByAddress: [String: String]
    public var nftsByAddress: [String: ApiNft]
    public var orderedAddresses: [String]

    public init(
        accountId: String,
        expirationByAddress: [String: Int] = [:],
        linkedAddressByAddress: [String: String] = [:],
        nftsByAddress: [String: ApiNft] = [:],
        orderedAddresses: [String] = []
    ) {
        self.accountId = accountId
        self.expirationByAddress = expirationByAddress
        self.linkedAddressByAddress = linkedAddressByAddress
        self.nftsByAddress = nftsByAddress
        self.orderedAddresses = orderedAddresses
    }

    public init(accountId: String, data: AccountDomainData) {
        self.init(
            accountId: accountId,
            expirationByAddress: data.expirationByAddress,
            linkedAddressByAddress: data.linkedAddressByAddress,
            nftsByAddress: data.nftsByAddress,
            orderedAddresses: data.orderedAddresses
        )
    }

    public static let databaseTableName: String = "account_domains"
}

public extension MAccountDomains {
    var hasData: Bool {
        !expirationByAddress.isEmpty
            || !linkedAddressByAddress.isEmpty
            || !nftsByAddress.isEmpty
            || !orderedAddresses.isEmpty
    }

    var data: AccountDomainData {
        AccountDomainData(
            expirationByAddress: expirationByAddress,
            linkedAddressByAddress: linkedAddressByAddress,
            nftsByAddress: nftsByAddress,
            orderedAddresses: orderedAddresses
        )
    }

    func applying(update: ApiUpdate.UpdateAccountDomainData) -> MAccountDomains {
        var merged = self
        merged.expirationByAddress = update.expirationByAddress
        merged.linkedAddressByAddress = update.linkedAddressByAddress
        for (address, nft) in update.nfts {
            merged.nftsByAddress[address] = nft
        }
        if !update.nfts.isEmpty {
            let orderedSet = OrderedSet(merged.orderedAddresses)
            let newAddresses = update.nfts.keys.filter { !orderedSet.contains($0) }.sorted()
            merged.orderedAddresses.append(contentsOf: newAddresses)
        }
        return merged
    }
}
