import Foundation
import Testing
import WalletContext
@testable import UISettings
@testable import WalletCore

@MainActor
@Suite("Mint request pricing", .serialized)
struct MintCardMintRequestTests {
    private var mycoin: ApiToken {
        ApiToken(slug: MYCOIN_SLUG, name: "MyTonWallet Coin", symbol: "MY", decimals: 9, chain: .ton, tokenAddress: "mycoin-address")
    }

    private func fundable(_ cards: ApiCardsInfo?) -> FundableCardsInfo {
        FundableCardsInfo(cards)
    }

    private func onSale(price: Double, notMinted: Int = 8, all: Int = 611) -> ApiCardsInfo {
        ApiCardsInfo(byType: [.standard: ApiCardInfo(all: all, notMinted: notMinted, price: price)])
    }

    @Test
    func pricesTheTransferFromTheServerNumbers() throws {
        let request = try #require(MintCardMintRequest(cards: fundable(onSale(price: 14.99)), type: .standard, token: mycoin))
        #expect(request.amount == doubleToBigInt(14.99, decimals: 9))
        #expect(request.tokenAddress == "mycoin-address")
        #expect(request.cardType == .standard)
    }

    /// The reason `FundableCardsInfo` exists. The debug preset prices the standard card at 50 MY
    /// against a live campaign charging 14.99, and the backend refunds the difference minus the
    /// fee, so a transfer priced from the preset costs the tester real money.
    @Test
    func aWalletShowingThePresetStillPaysTheServerPrice() throws {
        let key = DebugPromotionPreset.cardMintingUserDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let store = AccountConfigStore()
        let accountId = UUID().uuidString
        store.walletCore(event: .updateAccountConfig(
            ApiUpdate.UpdateAccountConfig(accountId: accountId, accountConfig: ApiAccountConfig(cardsInfo: onSale(price: 14.99)))
        ))
        let config = store.for(accountId: accountId)

        let presetPrice = try #require(config.cardsInfo?[.standard]?.price)
        #expect(presetPrice != 14.99)

        let request = try #require(MintCardMintRequest(cards: config.fundableCardsInfo, type: .standard, token: mycoin))
        #expect(request.amount == doubleToBigInt(14.99, decimals: 9))
        #expect(request.amount != doubleToBigInt(presetPrice, decimals: 9))
    }

    @Test
    func refusesAWalletTheServerSentNoCardsFor() {
        #expect(MintCardMintRequest(cards: fundable(nil), type: .standard, token: mycoin) == nil)
        #expect(MintCardMintRequest(cards: fundable(ApiCardsInfo()), type: .standard, token: mycoin) == nil)
    }

    @Test
    func refusesATierTheCampaignIsNotSelling() {
        #expect(MintCardMintRequest(cards: fundable(onSale(price: 14.99)), type: .gold, token: mycoin) == nil)
        #expect(MintCardMintRequest(cards: fundable(onSale(price: 14.99, notMinted: 0)), type: .standard, token: mycoin) == nil)
        #expect(MintCardMintRequest(cards: fundable(onSale(price: 14.99, all: 0)), type: .standard, token: mycoin) == nil)
    }

    @Test
    func refusesAPriceThatCannotBecomeAnAmount() {
        for price in [0, -1, Double.nan, .infinity, 1e-12] {
            #expect(MintCardMintRequest(cards: fundable(onSale(price: price)), type: .standard, token: mycoin) == nil)
        }
    }

    @Test
    func refusesWithoutATokenToSend() {
        let noAddress = ApiToken(slug: MYCOIN_SLUG, name: "MyTonWallet Coin", symbol: "MY", decimals: 9, chain: .ton, tokenAddress: "")
        #expect(MintCardMintRequest(cards: fundable(onSale(price: 14.99)), type: .standard, token: nil) == nil)
        #expect(MintCardMintRequest(cards: fundable(onSale(price: 14.99)), type: .standard, token: noAddress) == nil)
    }
}
