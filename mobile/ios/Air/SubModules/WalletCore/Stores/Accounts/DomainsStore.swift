import Dependencies
import Foundation
import GRDB
import Perception
import WalletContext

private let log = Log("DomainsStore")

public actor DomainsStore: WalletCoreData.EventsObserver {
    @MainActor private var byAccountId: MainActorByAccountIdStore<Domains> = .init(initialValue: Domains.init(accountId:))
    
    private var db: (any DatabaseWriter)?
    
    private init() {
    }
    
    func use(db: any DatabaseWriter) async {
        self.db = db
        await loadFromDb()
        WalletCoreData.add(eventObserver: self)
    }
    
    @MainActor func clean() {
        byAccountId.removeAll()
    }
    
    @MainActor public func `for`(accountId: String) -> Domains {
        byAccountId.for(accountId: accountId)
    }
    
    func persist(_ row: MAccountDomains) {
        guard let db else {
            assertionFailure("database not ready")
            return
        }
        do {
            try db.write { db in
                if row.hasData {
                    try row.upsert(db)
                } else {
                    try MAccountDomains.deleteOne(db, key: row.accountId)
                }
            }
        } catch {
            log.error("persist failed accountId=\(row.accountId, .public) error=\(error, .public)")
        }
    }
    
    @MainActor public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .updateAccountDomainData(let update):
            Task {
                await handleUpdate(update)
            }
        case .accountDeleted(let accountId):
            byAccountId.remove(accountId: accountId)
        case .accountsReset:
            byAccountId.removeAll()
        default:
            break
        }
    }
    
    private func loadFromDb() async {
        do {
            guard let db else {
                assertionFailure("database not ready")
                return
            }
            let rows = try await db.read { db in
                try MAccountDomains.fetchAll(db)
            }
            await MainActor.run {
                for row in rows {
                    `for`(accountId: row.accountId).replace(row: row)
                }
            }
        } catch {
            log.error("initial load failed: \(error, .public)")
        }
    }
    
    @MainActor private func handleUpdate(_ update: ApiUpdate.UpdateAccountDomainData) async {
        let store = self.for(accountId: update.accountId)
        let data = store.data
        let currentRow = MAccountDomains(accountId: update.accountId, data: data)
        let nextRow = currentRow.applying(update: update)
        guard nextRow != currentRow else { return }
        store.replace(row: nextRow)
        await persist(nextRow)
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

@MainActor
@Perceptible
public final class Domains: Sendable {
    public let accountId: String
    public private(set) var data: AccountDomainData = .empty

    nonisolated init(accountId: String) {
        self.accountId = accountId
    }

    public var expirationByAddress: [String: Int] { data.expirationByAddress }
    public var linkedAddressByAddress: [String: String] { data.linkedAddressByAddress }
    public var nftsByAddress: [String: ApiNft] { data.nftsByAddress }
    public var orderedAddresses: [String] { data.orderedAddresses }

    fileprivate func replace(row: MAccountDomains?) {
        data = row?.data ?? .empty
    }
}

public struct AccountDomainData: Equatable, Hashable, Sendable {
    public var expirationByAddress: [String: Int]
    public var linkedAddressByAddress: [String: String]
    public var nftsByAddress: [String: ApiNft]
    public var orderedAddresses: [String]

    public static let empty = AccountDomainData(
        expirationByAddress: [:],
        linkedAddressByAddress: [:],
        nftsByAddress: [:],
        orderedAddresses: []
    )
}

public extension Domains {
    static let tonDnsRenewalNftWarningDays = 30
    static let tonDnsRenewalWarningDays = 14

    func expirationDays(for nft: ApiNft, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard nft.isTonDns, let expirationMs = expirationByAddress[nft.address] else {
            return nil
        }

        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: Date(unixMs: expirationMs))
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    func expirationWarningDays(for nft: ApiNft, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let expirationDays = expirationDays(for: nft, now: now, calendar: calendar),
              expirationDays <= Self.tonDnsRenewalNftWarningDays else {
            return nil
        }

        return expirationDays
    }

    func renewalWarningExpirationDays(for nft: ApiNft, now: Date = Date()) -> Int? {
        guard let expirationMs = expirationByAddress[nft.address] else {
            return nil
        }

        return Self.renewalWarningDaysUntilExpiration(expirationMs: expirationMs, now: now)
    }

    func renewalWarningExpirationDays(for nfts: [ApiNft], now: Date = Date()) -> Int? {
        let earliestExpiration = nfts.compactMap { expirationByAddress[$0.address] }.min()
        return earliestExpiration.map { Self.renewalWarningDaysUntilExpiration(expirationMs: $0, now: now) }
    }

    func expiringForRenewalWarning(ignoredAddresses: Set<String> = [], now: Date = Date()) -> [ApiNft] {
        orderedAddresses.compactMap { address in
            guard !ignoredAddresses.contains(address),
                  let nft = nftsByAddress[address],
                  let expirationDays = renewalWarningExpirationDays(for: nft, now: now),
                  expirationDays <= Self.tonDnsRenewalWarningDays else {
                return nil
            }

            return nft
        }
    }

    func expiredForRenewalWarning(in nfts: [ApiNft], now: Date = Date()) -> [ApiNft] {
        let nowMs = Int(now.timeIntervalSince1970 * 1000)
        return nfts.filter { nft in
            guard let expirationMs = expirationByAddress[nft.address] else {
                return false
            }
            return expirationMs < nowMs
        }
    }

    private static func renewalWarningDaysUntilExpiration(expirationMs: Int, now: Date) -> Int {
        let remainingMs = Double(expirationMs) - now.timeIntervalSince1970 * 1000
        return Int(ceil(remainingMs / 86_400_000))
    }
}
