import Dependencies
import Foundation
import GRDB
import Perception
import UIKit
import WalletContext

private let log = Log("AccountSettings")

public actor AccountSettingsStore: WalletCoreData.EventsObserver {
    @MainActor private var byAccountId: MainActorByAccountIdStore<AccountSettings> = .init(initialValue: AccountSettings.init(accountId:))

    private var db: (any DatabaseWriter)?

    init() {
    }

    func use(db: any DatabaseWriter) async {
        self.db = db
        await loadFromDb()
        WalletCoreData.add(eventObserver: self)
    }

    @MainActor func clean() {
        byAccountId.removeAll()
    }

    @MainActor public func `for`(accountId: String) -> AccountSettings {
        byAccountId.for(accountId: accountId)
    }

    func persist(_ row: MAccountSettings) {
        guard let db else {
            assertionFailure("database not ready")
            return
        }

        do {
            try db.write { db in
                if row.hasData {
                    try row.upsert(db)
                } else {
                    try MAccountSettings.deleteOne(db, key: row.accountId)
                }
            }
        } catch {
            log.error("persist failed accountId=\(row.accountId, .public) error=\(error, .public)")
        }
    }

    @MainActor public func walletCore(event: WalletCoreData.Event) {
        switch event {
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
                try MAccountSettings.fetchAll(db)
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
}

extension AccountSettingsStore: DependencyKey {
    public static let liveValue: AccountSettingsStore = AccountSettingsStore()
}

extension DependencyValues {
    public var accountSettings: AccountSettingsStore {
        self[AccountSettingsStore.self]
    }
}

@MainActor
@Perceptible
public final class AccountSettings: Sendable {
    public let accountId: String
    public private(set) var backgroundNft: ApiNft?
    public private(set) var accentColorNft: ApiNft?
    public private(set) var accentColorIndex: Int?
    public private(set) var isAllowSuspiciousActions = false

    nonisolated init(accountId: String) {
        self.accountId = accountId
    }

    public func setBackgroundNft(_ nft: ApiNft?) {
        backgroundNft = nft
        persist()
        WalletCoreData.notify(event: .cardBackgroundChanged(accountId, nft))
    }

    public func setAccentColorNft(_ nft: ApiNft?) {
        accentColorNft = nft
        persist()
        installAccentColorFromNft(accountId: accountId, nft: nft)
    }

    private func installAccentColorFromNft(accountId: String, nft: ApiNft?) {
        Task.detached {
            let color: Int? = if let nft {
                await getAccentColorIndexFromNft(nft: nft)
            } else {
                nil
            }
            await self.setAccentColorIndex(index: color)
        }
    }

    public func setIsAllowSuspiciousActions(_ isEnabled: Bool) {
        isAllowSuspiciousActions = isEnabled
        persist()
    }

    private func setAccentColorIndex(index newValue: Int?) {
        accentColorIndex = newValue
        @Dependency(\.accountStore) var accountStore
        if accountId == accountStore.currentAccountId {
            changeThemeColors(to: newValue)
            DispatchQueue.main.async {
                UIApplication.shared.sceneWindows.forEach { $0.updateTheme() }
            }
        }
        persist()
    }

    fileprivate func replace(row: MAccountSettings?) {
        backgroundNft = row?.cardBackgroundNft
        accentColorNft = row?.accentColorNft
        accentColorIndex = row?.accentColorIndex
        isAllowSuspiciousActions = row?.isAllowSuspiciousActions ?? false
    }

    private var row: MAccountSettings {
        MAccountSettings(
            accountId: accountId,
            cardBackgroundNft: backgroundNft,
            accentColorNft: accentColorNft,
            accentColorIndex: accentColorIndex,
            isAllowSuspiciousActions: isAllowSuspiciousActions ? true : nil
        )
    }

    private func persist() {
        @Dependency(\.accountSettings) var accountSettingsStore
        let row = self.row
        Task {
            await accountSettingsStore.persist(row)
        }
    }
}
