import Testing
import UIKit
import WalletContext
import WalletCore
import WalletResources
@testable import UIComponents

@MainActor
@Suite("Home card mint action", .serialized)
struct MtwCardPromotionTests {
    init() {
        _ = WalletResourcesBundle.bundle.load()
    }

    @Test
    func mintTapTargetStaysInsideTheCardAndClearOfAddresses() {
        let content = MtwCardContentView(mode: .expanded)
        for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
            content.semanticContentAttribute = direction
            for width in [248.0, 370, 600] {
                content.frame = CGRect(x: 0, y: 0, width: width, height: width * CARD_RATIO)
                content.configure(data(promotion: DebugPromotionPreset.airPromotion, hasCardsInfo: true), cardWidth: width, animatesBalance: false)
                content.layoutIfNeeded()
                let button = content.mintButton
                #expect(!button.isHidden)
                #expect(!content.promotionButton.isHidden)
                #expect(!button.frame.intersects(content.promotionButton.frame))
                #expect(button.frame.width >= 44 && button.frame.height >= 44)
                #expect(button.frame.maxX == content.bounds.maxX)
                #expect(button.frame.maxY == content.bounds.maxY)
                #expect(!button.frame.intersects(content.accountLine.frame))
                for x in [button.frame.minX + 1, button.frame.maxX - 1] {
                    for y in [button.frame.minY + 1, button.frame.maxY - 1] {
                        #expect(content.hitTest(CGPoint(x: x, y: y), with: nil) === button)
                    }
                }
            }
        }
    }

    @Test
    func mintTintAdaptsToCustomCardsAndReuseClearsTheAction() {
        let content = MtwCardContentView(mode: .expanded)
        content.frame = CGRect(x: 0, y: 0, width: 370, height: 215)
        content.configure(data(promotion: nil, hasCardsInfo: true), cardWidth: 370, animatesBalance: false)
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        #expect(content.mintButton.tintColor.getWhite(&white, alpha: &alpha))
        #expect(abs(white - 1) < 0.001)
        #expect(alpha == 1)
        #expect(content.mintButton.accessibilityLabel == lang("Mint Cards"))

        var nft = ApiNft.sampleMtwCard
        nft.metadata?.mtwCardType = .standard
        nft.metadata?.mtwCardTextType = .dark
        content.configure(data(promotion: nil, nft: nft, hasCardsInfo: true), cardWidth: 370, animatesBalance: false)
        #expect(content.mintButton.tintColor == UIColor(hex: "2F3241"))

        content.prepareForReuse()
        #expect(content.promotionButton.isHidden)
        #expect(content.mintButton.isHidden)
        #expect(content.promotionButton.accessibilityLabel == nil)
        content.configure(data(promotion: DebugPromotionPreset.airPromotion), cardWidth: 370, animatesBalance: false)
        content.layoutIfNeeded()
        #expect(!content.promotionButton.isHidden)
        #expect(content.promotionButton.frame.minY < 0)
        #expect(content.promotionButton.accessibilityIdentifier != "MintCardsButton")
        #expect(content.mintButton.isHidden)
        content.configure(data(promotion: nil), cardWidth: 370, animatesBalance: false)
        #expect(content.promotionButton.isHidden)

        let collapsed = MtwCardContentView(mode: .collapsed)
        collapsed.configure(data(promotion: DebugPromotionPreset.cardMintingPromotion, hasCardsInfo: true), cardWidth: 370, animatesBalance: false)
        #expect(collapsed.promotionButton.isHidden)
        #expect(collapsed.mintButton.isHidden)
    }

    @Test
    func bothPromotionActionsRenderTheFoldedCornerAndClearOnReuse() {
        let artwork = MtwCardPromotionView()
        artwork.frame = CGRect(x: 0, y: 0, width: 370, height: 215)
        artwork.configure(promotion: nil, animated: false)
        let empty = snapshot(artwork)

        var overlay = DebugPromotionPreset.airPromotion.cardOverlay!
        overlay.mascotIcon = nil
        artwork.configure(promotion: ApiPromotion(id: "campaign", cardOverlay: overlay), animated: false)
        #expect(snapshot(artwork) != empty)

        artwork.configure(promotion: DebugPromotionPreset.cardMintingPromotion, animated: false)
        #expect(snapshot(artwork) != empty)
        artwork.prepareForReuse()
        #expect(snapshot(artwork) == empty)
        artwork.configure(promotion: DebugPromotionPreset.cardMintingPromotion, animated: false)
        #expect(snapshot(artwork) != empty)
        artwork.configure(promotion: ApiPromotion(id: "banner", infoBanner: .init(
            title: "Earn", description: "Earn", actionButton: .init(title: "Earn", onClickAction: .openEarn)
        )), animated: false)
        #expect(snapshot(artwork) == empty)
    }

    @Test
    func wandEligibilityIsIndependentOfPromotionAndUpdatesWithoutReuse() {
        let content = MtwCardContentView(mode: .expanded)
        let promotions: [ApiPromotion?] = [nil, DebugPromotionPreset.airPromotion, DebugPromotionPreset.cardMintingPromotion]
        for promotion in promotions {
            for hasCardsInfo in [true, false] {
                for isCardMinting in [true, false] {
                    for isView in [false, true] {
                        for isRestricted in [false, true] {
                            var fixture = data(promotion: promotion, hasCardsInfo: hasCardsInfo)
                            fixture.isCardMinting = isCardMinting
                            fixture.isNftBuyingDisabled = isRestricted
                            fixture.account.type = isView ? .view : .mnemonic
                            content.configure(fixture, cardWidth: 370, animatesBalance: false)
                            #expect(content.mintButton.isHidden == (isView || isRestricted || (!hasCardsInfo && !isCardMinting)))
                            #expect(content.promotionButton.isHidden == (promotion == nil))
                        }
                    }
                }
            }
        }
    }

    @Test
    func cornerAndWandHaveIndependentAccessibleTapTargets() {
        let content = MtwCardContentView(mode: .expanded)
        content.frame = CGRect(x: 0, y: 0, width: 370, height: 215)
        content.configure(data(promotion: DebugPromotionPreset.airPromotion, hasCardsInfo: true), cardWidth: 370, animatesBalance: false)
        content.layoutIfNeeded()
        var taps: [String] = []
        content.promotionButton.onTap = { taps.append("promotion") }
        content.mintButton.onTap = { taps.append("mint") }
        #expect(content.promotionButton.accessibilityActivate())
        #expect(taps == ["promotion"])
        #expect(content.mintButton.accessibilityActivate())
        #expect(taps == ["promotion", "mint"])
        #expect(content.mintButton.accessibilityIdentifier == "MintCardsButton")
        #expect(content.promotionButton.accessibilityLabel != content.mintButton.accessibilityLabel)
        for button in [content.promotionButton, content.mintButton] {
            let point = CGPoint(x: button.frame.midX, y: max(1, button.frame.midY))
            #expect(content.hitTest(point, with: nil) === button)
        }
    }

    private func data(promotion: ApiPromotion?, nft: ApiNft? = nil, hasCardsInfo: Bool = false) -> MtwCardContentData {
        let chain = AccountChain(address: "UQDQ7EXuEywyezyEWzfNkHZTSbe8qbPKETFYHr_KTZnnJ-xL")
        let account = MAccount(id: "0-mainnet", title: "Wallet", type: .mnemonic, byChain: [.ton: chain])
        return MtwCardContentData(
            account: account, addressLine: account.addressLine(orderedChains: [(.ton, chain)]),
            balance: .fromDouble(100, .USD), previousBalance: nil, balanceChange: nil,
            nft: nft, promotion: promotion, hasCardsInfo: hasCardsInfo
        )
    }

    private func snapshot(_ view: UIView) -> Data? {
        view.layoutIfNeeded()
        return UIGraphicsImageRenderer(size: view.bounds.size).image { context in
            view.layer.render(in: context.cgContext)
        }.pngData()
    }
}
