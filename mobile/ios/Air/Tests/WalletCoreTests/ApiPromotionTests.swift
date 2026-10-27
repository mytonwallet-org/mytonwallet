import Foundation
import Testing
@testable import WalletCore

struct ApiPromotionTests {
    @Test func decodesAccountBannerSnapshotAndForeignAction() throws {
        let json = #"""
        {"type":"updateAccountBanners","accountId":"0-mainnet","homeBanners":[],"stakingBanners":[{
          "id":"foreign-staking:ton:tonstakers","kind":"foreignStaking","linkedBannerId":"foreign-staking:ton",
          "foreignStaking":{"chain":"ton","providerName":"tonstakers","amount":"12","symbol":"TON","apy":3,"stakingApy":5},
          "infoBanner":{"title":"🔒 %amount% %symbol% locked in another staking","textValues":{"%amount%":"12","%symbol%":"TON"},
          "description":"Unstake them to restake with **higher returns**.","actionButton":{"title":"Unstake","onClickAction":"unstakeForeign","chain":"ton","providerName":"tonstakers"}}
        }]}
        """#
        let update = try JSONDecoder().decode(ApiUpdate.UpdateAccountBanners.self, from: Data(json.utf8))
        let promotion = try #require(update.stakingBanners.first)
        #expect(promotion.kind == .foreignStaking)
        #expect(promotion.linkedBannerId == "foreign-staking:ton")
        #expect(promotion.infoBanner?.textValues?["%amount%"] == "12")
        #expect(promotion.infoBanner?.actionButton.onClickAction == .unstakeForeign)
        #expect(promotion.infoBanner?.actionButton.chain == .ton)
        #expect(promotion.infoBanner?.actionButton.providerName == "tonstakers")
        #expect(try JSONDecoder().decode(ApiUpdate.UpdateAccountBanners.self, from: JSONEncoder().encode(update)) == update)
    }

    @Test func foreignUnstakeDraftPreservesExactAmountsAndPayloadForSubmission() throws {
        let json = #"{"amountNative":"bigint:12345678901234567890","transfers":[{"toAddress":"wallet","amount":"bigint:1050000000","payload":"te6ccg=="}],"fee":"bigint:10","realFee":"bigint:100","isInstant":true}"#
        let draft = try JSONDecoder().decode(ApiForeignUnstakeDraft.self, from: Data(json.utf8))
        #expect(draft.amountNative.description == "12345678901234567890")
        #expect(draft.transfers.first?.payload == "te6ccg==")
        #expect(draft.isInstant)
        #expect(try JSONDecoder().decode(ApiForeignUnstakeDraft.self, from: JSONEncoder().encode(draft)) == draft)
    }

    @Test func decodesExistingCardOverlay() throws {
        let json = #"{"id":"card","kind":"cardOverlay","cardOverlay":{"onClickAction":"openMintCardModal"}}"#
        let promotion = try JSONDecoder().decode(ApiPromotion.self, from: Data(json.utf8))
        #expect(promotion.kind == .cardOverlay)
        #expect(promotion.cardOverlay?.onClickAction == .openMintCardModal)
        #expect(promotion.infoBanner == nil)
        #expect(try JSONDecoder().decode(ApiPromotion.self, from: JSONEncoder().encode(promotion)) == promotion)
    }

    @Test func decodesInfoBannerWithoutCardOverlay() throws {
        let json = #"{"id":"staking","kind":"infoBanner","infoBanner":{"title":"Staking available","description":"Tap **Earn**.","actionButton":{"title":"Restake Now","onClickAction":"openEarn"}}}"#
        let promotion = try JSONDecoder().decode(ApiPromotion.self, from: Data(json.utf8))
        #expect(promotion.kind == .infoBanner)
        #expect(promotion.infoBanner?.description == "Tap **Earn**.")
        #expect(promotion.infoBanner?.actionButton.onClickAction == .openEarn)
        #expect(promotion.cardOverlay == nil)
        #expect(try JSONDecoder().decode(ApiPromotion.self, from: JSONEncoder().encode(promotion)) == promotion)
    }

    @Test func rejectsMissingPayloadWithoutDiscardingAccountConfig() throws {
        let json = #"{"activePromotion":{"id":"incomplete","kind":"infoBanner"},"isMfaEnabled":true}"#
        let config = try JSONDecoder().decode(ApiAccountConfig.self, from: Data(json.utf8))
        #expect(config.activePromotion == nil)
        #expect(config.isMfaEnabled == true)
    }
}
