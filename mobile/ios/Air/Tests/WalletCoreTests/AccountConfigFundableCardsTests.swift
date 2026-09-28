import Foundation
import Testing
@testable import WalletCore

@MainActor
@Suite("Account config fundable cards", .serialized)
struct AccountConfigFundableCardsTests {
    private let serverCards = ApiCardsInfo(byType: [
        .standard: ApiCardInfo(all: 611, notMinted: 8, price: 14.99),
    ])

    private func withCardMintingPreset<T>(_ enabled: Bool, _ body: () throws -> T) rethrows -> T {
        let key = DebugPromotionPreset.cardMintingUserDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(enabled, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        return try body()
    }

    private func config(withServerCards cards: ApiCardsInfo?) -> AccountConfig {
        let store = AccountConfigStore()
        let accountId = UUID().uuidString
        store.walletCore(event: .updateAccountConfig(
            ApiUpdate.UpdateAccountConfig(accountId: accountId, accountConfig: ApiAccountConfig(cardsInfo: cards))
        ))
        store.refreshDebugOverrides()
        return store.for(accountId: accountId)
    }

    @Test
    func debugPresetRendersItsOwnCardsWhileTheFundableCopyStaysOnTheServerPayload() {
        let withoutPreset = withCardMintingPreset(false) { config(withServerCards: serverCards) }
        #expect(withoutPreset.cardsInfo == serverCards)
        #expect(withoutPreset.fundableCardsInfo.cards == serverCards)

        let withPreset = withCardMintingPreset(true) { config(withServerCards: serverCards) }
        #expect(withPreset.cardsInfo == DebugPromotionPreset.cardMintingCardsInfo)
        #expect(withPreset.fundableCardsInfo.cards == serverCards)
        #expect(withPreset.fundableCardsInfo[.standard]?.price == 14.99)
    }

    @Test
    func aWalletWithoutServerCardsKeepsAnEmptyFundableCopyUnderThePreset() {
        let config = withCardMintingPreset(true) { config(withServerCards: nil) }
        #expect(config.cardsInfo == DebugPromotionPreset.cardMintingCardsInfo)
        #expect(config.fundableCardsInfo.cards == nil)
        #expect(config.fundableCardsInfo[.standard] == nil)
    }

    @Test
    func aLaterServerPayloadReplacesTheFundableCopyWhileThePresetKeepsRendering() {
        withCardMintingPreset(true) {
            let store = AccountConfigStore()
            let accountId = UUID().uuidString
            store.walletCore(event: .updateAccountConfig(
                ApiUpdate.UpdateAccountConfig(accountId: accountId, accountConfig: ApiAccountConfig(cardsInfo: serverCards))
            ))
            let soldOut = ApiCardsInfo(byType: [.standard: ApiCardInfo(all: 611, notMinted: 0, price: 14.99)])
            store.walletCore(event: .updateAccountConfig(
                ApiUpdate.UpdateAccountConfig(accountId: accountId, accountConfig: ApiAccountConfig(cardsInfo: soldOut))
            ))
            let config = store.for(accountId: accountId)
            #expect(config.fundableCardsInfo.cards == soldOut)
            #expect(config.cardsInfo == DebugPromotionPreset.cardMintingCardsInfo)
        }
    }
}
