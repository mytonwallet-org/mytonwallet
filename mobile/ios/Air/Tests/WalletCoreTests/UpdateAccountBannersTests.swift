import Foundation
import Testing
@testable import WalletCore

struct UpdateAccountBannersTests {
    @Test func skipsInvalidElementsInEachBannerArray() throws {
        let data = Data("""
        {
            "accountId": "account",
            "homeBanners": [
                {
                    "id": "invalid-home",
                    "kind": "infoBanner",
                    "infoBanner": {
                        "title": "Title",
                        "description": "Body",
                        "actionButton": { "title": "Swap", "onClickAction": "openSwap" }
                    }
                },
                {
                    "id": "valid-home",
                    "kind": "infoBanner",
                    "infoBanner": {
                        "title": "Title",
                        "description": "Body",
                        "actionButton": { "title": "Earn", "onClickAction": "openEarn" }
                    }
                }
            ],
            "stakingBanners": [
                {
                    "id": "valid-staking",
                    "kind": "foreignStaking",
                    "linkedBannerId": "valid-home",
                    "infoBanner": {
                        "title": "Title",
                        "description": "Body",
                        "actionButton": { "title": "Unstake", "onClickAction": "unstakeForeign" }
                    }
                },
                {
                    "id": "invalid-staking",
                    "kind": "infoBanner",
                    "infoBanner": {
                        "title": "Title",
                        "description": "Body",
                        "actionButton": { "title": "Swap", "onClickAction": "openSwap" }
                    }
                }
            ]
        }
        """.utf8)

        let update = try JSONDecoder().decode(ApiUpdate.UpdateAccountBanners.self, from: data)

        #expect(update.accountId == "account")
        #expect(update.homeBanners.map(\.id) == ["valid-home"])
        #expect(update.stakingBanners.map(\.id) == ["valid-staking"])
    }
}
