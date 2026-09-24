import Foundation
import Testing
@testable import WalletCore

struct ApiPromotionTests {
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
