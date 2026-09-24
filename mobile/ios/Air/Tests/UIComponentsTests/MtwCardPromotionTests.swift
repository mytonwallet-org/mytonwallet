import CoreText
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
        for font in ["SFCompactRoundedBold", "SFCompactDisplayMedium"] {
            if let url = WalletResourcesBundle.bundle.url(forResource: font, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    @Test
    func mintTapTargetStaysInsideTheCardAndClearOfAddresses() {
        let content = MtwCardContentView(mode: .expanded)
        for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
            content.semanticContentAttribute = direction
            for width in [248.0, 370, 600] {
                content.frame = CGRect(x: 0, y: 0, width: width, height: width * CARD_RATIO)
                content.configure(data(promotion: DebugPromotionPreset.cardMintingPromotion), cardWidth: width, animatesBalance: false)
                content.layoutIfNeeded()
                let button = content.promotionButton
                #expect(!button.isHidden)
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
        content.configure(data(promotion: DebugPromotionPreset.cardMintingPromotion), cardWidth: 370, animatesBalance: false)
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        #expect(content.promotionButton.tintColor.getWhite(&white, alpha: &alpha))
        #expect(abs(white - 1) < 0.001)
        #expect(alpha == 1)
        #expect(content.promotionButton.accessibilityLabel == lang("Mint Cards"))

        var nft = ApiNft.sampleMtwCard
        nft.metadata?.mtwCardType = .standard
        nft.metadata?.mtwCardTextType = .dark
        content.configure(data(promotion: DebugPromotionPreset.cardMintingPromotion, nft: nft), cardWidth: 370, animatesBalance: false)
        #expect(content.promotionButton.tintColor == UIColor(hex: "2F3241"))

        content.prepareForReuse()
        #expect(content.promotionButton.isHidden)
        #expect(content.promotionButton.accessibilityLabel == nil)
        content.configure(data(promotion: DebugPromotionPreset.airPromotion), cardWidth: 370, animatesBalance: false)
        content.layoutIfNeeded()
        #expect(!content.promotionButton.isHidden)
        #expect(content.promotionButton.frame.minY < 0)
        #expect(content.promotionButton.accessibilityIdentifier != "MintCardsButton")
        content.configure(data(promotion: nil), cardWidth: 370, animatesBalance: false)
        #expect(content.promotionButton.isHidden)

        let collapsed = MtwCardContentView(mode: .collapsed)
        collapsed.configure(data(promotion: DebugPromotionPreset.cardMintingPromotion), cardWidth: 370, animatesBalance: false)
        #expect(collapsed.promotionButton.isHidden)
    }

    @Test
    func mintPromotionDoesNotRenderTheFoldedCornerEvenAfterCampaignReuse() {
        let artwork = MtwCardPromotionView()
        artwork.frame = CGRect(x: 0, y: 0, width: 370, height: 215)
        artwork.configure(promotion: nil, animated: false)
        let empty = snapshot(artwork)

        var overlay = DebugPromotionPreset.airPromotion.cardOverlay!
        overlay.mascotIcon = nil
        artwork.configure(promotion: ApiPromotion(id: "campaign", cardOverlay: overlay), animated: false)
        #expect(snapshot(artwork) != empty)

        artwork.configure(promotion: DebugPromotionPreset.cardMintingPromotion, animated: false)
        #expect(snapshot(artwork) == empty)
        artwork.prepareForReuse()
        artwork.configure(promotion: DebugPromotionPreset.cardMintingPromotion, animated: false)
        #expect(snapshot(artwork) == empty)
    }

    private func data(promotion: ApiPromotion?, nft: ApiNft? = nil) -> MtwCardContentData {
        let chain = AccountChain(address: "UQDQ7EXuEywyezyEWzfNkHZTSbe8qbPKETFYHr_KTZnnJ-xL")
        let account = MAccount(id: "0-mainnet", title: "Wallet", type: .mnemonic, byChain: [.ton: chain])
        return MtwCardContentData(
            account: account, addressLine: account.addressLine(orderedChains: [(.ton, chain)]),
            balance: .fromDouble(100, .USD), previousBalance: nil, balanceChange: nil,
            nft: nft, promotion: promotion
        )
    }

    private func snapshot(_ view: UIView) -> Data? {
        view.layoutIfNeeded()
        return UIGraphicsImageRenderer(size: view.bounds.size).image { context in
            view.layer.render(in: context.cgContext)
        }.pngData()
    }
}
