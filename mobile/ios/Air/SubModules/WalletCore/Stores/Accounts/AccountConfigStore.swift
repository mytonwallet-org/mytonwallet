import Dependencies
import Foundation
import Perception
import WalletContext

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
        if DebugPromotionPreset.isEnabled || isMfaEnabledOverrideActive {
            value.refreshDebugOverrides()
        }
        return value
    }

    @MainActor public func refreshDebugOverrides() {
        for accountId in byAccountId.accountIds() {
            byAccountId.for(accountId: accountId).refreshDebugOverrides()
        }
    }

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

/// Card data exactly as the server sent it, in a type nothing outside WalletCore can build.
/// The debug promo preset has the same shape and reaches `AccountConfig.cardsInfo`, so a money
/// path that reads whichever card property is nearest to hand prices the transfer from invented
/// numbers and the backend refunds the mismatch minus the fee. Keeping the server copy in its own
/// type means the preset does not compile where an amount is computed, instead of being ruled out
/// by a comment a later refactor is free to ignore.
public struct FundableCardsInfo: Equatable, Sendable {
    public let cards: ApiCardsInfo?

    init(_ cards: ApiCardsInfo?) {
        self.cards = cards
    }

    public subscript(_ type: ApiMtwCardType) -> ApiCardInfo? {
        cards?[type]
    }
}

@MainActor
@Perceptible
public final class AccountConfig: Sendable {
    public let accountId: String
    public private(set) var cardsInfo: ApiCardsInfo?
    /// What may fund a transfer. `cardsInfo` is what the screen renders and may be the debug
    /// preset instead; see `FundableCardsInfo` for why the two are different types.
    public private(set) var fundableCardsInfo = FundableCardsInfo(nil)
    public private(set) var activePromotion: ApiPromotion?
    public private(set) var isMfaEnabled: Bool = false

    @PerceptionIgnored
    private var serverActivePromotion: ApiPromotion?
    @PerceptionIgnored
    private var serverIsMfaEnabled: Bool = false

    nonisolated init(accountId: String) {
        self.accountId = accountId
    }

    fileprivate func replace(config: ApiAccountConfig?) {
        fundableCardsInfo = FundableCardsInfo(config?.cardsInfo)
        serverActivePromotion = config?.activePromotion
        serverIsMfaEnabled = config?.isMfaEnabled ?? false
        applyResolvedConfig()
    }

    fileprivate func refreshDebugOverrides() {
        applyResolvedConfig()
    }

    private func applyResolvedConfig() {
        isMfaEnabled = serverIsMfaEnabled || isMfaEnabledOverrideActive
        cardsInfo = DebugPromotionPreset.cardsInfoOverride ?? fundableCardsInfo.cards
        activePromotion = DebugPromotionPreset.activePromotion ?? serverActivePromotion
    }
}

private var isMfaEnabledOverrideActive: Bool {
    IS_DEBUG_OR_TESTFLIGHT && DebugMfaEnabledOverride.isEnabled
}
