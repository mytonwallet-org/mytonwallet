import Dependencies
import GRDB
import SwiftUI
import Testing
@testable import WalletCore
import WalletResources
@testable import UIComponents

@MainActor
@Suite(.serialized)
struct HomePromotionPrivacyTests {
    init() {
        _ = WalletResourcesBundle.bundle.load()
    }

    @Test func privacyMasksAmountsInVisibleAndAccessibleTextButKeepsSymbols() {
        let banner = banner(amount: "12345.67")
        for text in [banner.title, banner.description, banner.actionButton.title] {
            let hidden = banner.localized(text, isSensitiveDataHidden: true)
            #expect(!hidden.contains("12345.67"))
            #expect(hidden.contains("***"))
            #expect(hidden.contains("TON"))
            #expect(banner.localized(text, isSensitiveDataHidden: false).contains("12345.67"))
        }
        #expect(banner.textValues?["%amount%"] == "12345.67")
    }

    @Test func hiddenPromotionsRenderIdenticallyForDifferentBalances() throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        defer { SettingsStore.liveValue.clean() }
        let privacy = SensitiveData.liveValue
        let wasHidden = privacy.isHidden
        defer { privacy.isHidden = wasHidden }

        privacy.isHidden = true
        #expect(try render(amount: "12") == render(amount: "987654321"))
        privacy.isHidden = false
        #expect(try render(amount: "12") != render(amount: "987654321"))
    }

    private func render(amount: String) throws -> Data {
        let content = withDependencies {
            $0.sensitiveData = SensitiveData.liveValue
        } operation: {
            HomePromotionStack(
                promotions: [ApiPromotion(id: "foreign", infoBanner: banner(amount: amount), linkedBannerId: "home")],
                animation: nil,
                onAction: { _ in },
                onDismiss: { _ in }
            )
            .frame(width: 360)
        }
        return try #require(ImageRenderer(content: content).uiImage?.pngData())
    }

    private func banner(amount: String) -> ApiPromotion.InfoBanner {
        .init(
            title: "🔒 %amount% %symbol% locked in another staking",
            description: "%amount% %symbol%",
            actionButton: .init(title: "%amount% %symbol%", onClickAction: .unstakeForeign, chain: .ton),
            textValues: ["%amount%": amount, "%symbol%": "TON"]
        )
    }
}
