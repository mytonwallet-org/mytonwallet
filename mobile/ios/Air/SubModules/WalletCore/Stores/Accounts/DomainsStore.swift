import Foundation
import Dependencies
import Perception
import WalletContext
import OrderedCollections

private let log = Log("DomainsStore")

@Perceptible
public final class DomainsStore: WalletCoreData.EventsObserver {
    
    private var _byAccountId: UnfairLock<[String: Domains]> = .init(initialState: [:])
    
    private init() {
        WalletCoreData.add(eventObserver: self)
    }
    
    public func `for`(accountId: String) -> Domains {
        access(keyPath: \.__byAccountId)
        return _byAccountId.withLock { _byAccountId in
            if let domains = _byAccountId[accountId] {
                return domains
            }
            let domains = Domains(accountId: accountId)
            _byAccountId[accountId] = domains
            return domains
        }
    }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .updateAccountDomainData(let update):
            let domains = self.for(accountId: update.accountId)
            domains.apply(update: update)
        default:
            break
        }
    }
}

extension DomainsStore: DependencyKey {
    public static let liveValue: DomainsStore = DomainsStore()
}

extension DependencyValues {
    public var domains: DomainsStore {
        self[DomainsStore.self]
    }
}

@Perceptible
public final class Domains {
    
    public let accountId: String
    
    init(accountId: String) {
        self.accountId = accountId
    }

    public var data: AccountDomainData {
        access(keyPath: \.data)
        return AccountDomainData(
            expirationByAddress: decode([String: Int].self, forKey: dnsExpirationKey) ?? [:],
            linkedAddressByAddress: decode([String: String].self, forKey: linkedAddressByAddressKey) ?? [:],
            nftsByAddress: decode([String: ApiNft].self, forKey: nftsByAddressKey) ?? [:],
            orderedAddresses: decode([String].self, forKey: orderedAddressesKey) ?? []
        )
    }
    
    public var expirationByAddress: [String: Int] { data.expirationByAddress }
    public var linkedAddressByAddress: [String: String] { data.linkedAddressByAddress }
    public var nftsByAddress: [String: ApiNft] { data.nftsByAddress }
    public var orderedAddresses: [String] { data.orderedAddresses }
    
    public func apply(update: ApiUpdate.UpdateAccountDomainData) {
        let existingData = data
        var mergedNftsByAddress = existingData.nftsByAddress
        for (address, nft) in update.nfts {
            mergedNftsByAddress[address] = nft
        }
        var mergedOrderedAddresses = existingData.orderedAddresses
        if !update.nfts.isEmpty {
            let orderedSet = OrderedSet(mergedOrderedAddresses)
            let newAddresses = update.nfts.keys.filter { !orderedSet.contains($0) }.sorted()
            mergedOrderedAddresses.append(contentsOf: newAddresses)
        }
        let nftsObject = try? JSONSerialization.encode(mergedNftsByAddress)
        if nftsObject == nil && !mergedNftsByAddress.isEmpty {
            log.error("failed to encode domain nfts for \(accountId, .public)")
        }
        withMutation(keyPath: \.data) {
            GlobalStorage.update { dict in
                dict[dnsExpirationKey] = update.expirationByAddress
                dict[linkedAddressByAddressKey] = update.linkedAddressByAddress
                if let nftsObject {
                    dict[nftsByAddressKey] = nftsObject
                    dict[orderedAddressesKey] = mergedOrderedAddresses
                }
            }
            Task { try? await GlobalStorage.syncronize() }
        }
    }
    
    private var nftsKey: String { "byAccountId.\(accountId).nfts" }
    private var dnsExpirationKey: String { "\(nftsKey).dnsExpiration" }
    private var linkedAddressByAddressKey: String { "\(nftsKey).linkedAddressByAddress" }
    private var nftsByAddressKey: String { "\(nftsKey).byAddress" }
    private var orderedAddressesKey: String { "\(nftsKey).orderedAddresses" }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let value = GlobalStorage[key] else { return nil }
        return try? JSONSerialization.decode(type, from: value)
    }
}

public struct AccountDomainData: Equatable, Hashable, Sendable {
    public var expirationByAddress: [String: Int]
    public var linkedAddressByAddress: [String: String]
    public var nftsByAddress: [String: ApiNft]
    public var orderedAddresses: [String]
}
