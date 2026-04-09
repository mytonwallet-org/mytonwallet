import Dependencies
import Foundation
import Perception

public actor AccountConfigStore: WalletCoreData.EventsObserver {
    @MainActor private var byAccountId: MainActorByAccountIdStore<AccountConfig> = .init(initialValue: AccountConfig.init(accountId:))

    init() {
    }

    func use() async {
        WalletCoreData.add(eventObserver: self)
    }

    @MainActor func clean() {
        byAccountId.removeAll()
    }

    @MainActor public func `for`(accountId: String) -> AccountConfig {
        let value = byAccountId.for(accountId: accountId)
#if DEBUG
        if DebugPromotionPreset.isEnabled {
            value.refreshDebugOverrides()
        }
#endif
        return value
    }

#if DEBUG
    @MainActor public func refreshDebugOverrides() {
        for accountId in byAccountId.accountIds() {
            byAccountId.for(accountId: accountId).refreshDebugOverrides()
        }
    }
#endif

    @MainActor public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .updateAccountConfig(let update):
            `for`(accountId: update.accountId).replace(config: update.accountConfig)
        case .accountDeleted(let accountId):
            byAccountId.remove(accountId: accountId)
        case .accountsReset:
            byAccountId.removeAll()
        default:
            break
        }
    }
}

extension AccountConfigStore: DependencyKey {
    public static let liveValue: AccountConfigStore = AccountConfigStore()
}

extension DependencyValues {
    public var accountConfig: AccountConfigStore {
        self[AccountConfigStore.self]
    }
}

@MainActor
@Perceptible
public final class AccountConfig: Sendable {
    public let accountId: String
    public private(set) var cardsInfo: ApiCardsInfo?
    public private(set) var activePromotion: ApiPromotion?

    @PerceptionIgnored
    private var serverCardsInfo: ApiCardsInfo?
    @PerceptionIgnored
    private var serverActivePromotion: ApiPromotion?

    nonisolated init(accountId: String) {
        self.accountId = accountId
    }

    fileprivate func replace(config: ApiAccountConfig?) {
        serverCardsInfo = config?.cardsInfo
        serverActivePromotion = config?.activePromotion
        applyResolvedConfig()
    }

#if DEBUG
    fileprivate func refreshDebugOverrides() {
        applyResolvedConfig()
    }
#endif

    private func applyResolvedConfig() {
        cardsInfo = serverCardsInfo
#if DEBUG
        activePromotion = DebugPromotionPreset.isEnabled ? DebugPromotionPreset.airPromotion : serverActivePromotion
#else
        activePromotion = serverActivePromotion
#endif
    }
}
