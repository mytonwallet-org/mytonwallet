import CoreMotion
import Testing
import UIKit
import WalletCore
@testable import UIComponents

@MainActor
struct CardMotionPresetTests {
    @Test func defaultCardsUseTheirOwnBrandProfiles() {
        let my = CardMotionPreset.home(nft: nil, artwork: .myWallet)
        let gram = CardMotionPreset.home(nft: nil, artwork: .gramWallet)
        #expect(!my.shineEnabled)
        #expect(my.materialIntensity == 0.28)
        #expect(gram.shineEnabled)
        #expect(gram.gramReflectionMode == .telegramV2)
        #expect(gram.gramV2MaxRotation == 180)
        #expect(gram.gramStarSizeIn < 1.01)
        #expect(gram.gramStarSizeOut < 0.51)
        #expect(gram.materialIntensity == 0)
        #expect(gram.materialDepth > 3)
    }

    @Test func customProfilesFollowNftMetadataInBothBrands() {
        for (type, expected) in [(ApiMtwCardType.standard, CardMotionPreset.standard),
                                 (.silver, .silver), (.gold, .gold),
                                 (.platinum, .platinum), (.black, .black)] {
            for artwork in [CardSurfaceConfiguration.DefaultArtwork.myWallet, .gramWallet] {
                for textType in [ApiMtwCardTextType.light, .dark] {
                    var nft = ApiNft.sampleMtwCard
                    nft.metadata?.mtwCardType = type
                    nft.metadata?.mtwCardTextType = textType
                    let preset = CardMotionPreset.home(nft: nft, artwork: artwork)
                    #expect(preset == expected)
                    #expect(!preset.shineEnabled)
                    #expect(preset.borderShine)
                }
            }
        }
    }

    @Test func playLockRestoresBothScrollDirectionsAndOriginalDisabledState() {
        let vertical = UIScrollView()
        let horizontal = UIScrollView()
        let disabled = UIScrollView()
        let disabledPan = UIScrollView()
        let card = UIView()
        disabled.isScrollEnabled = false
        disabledPan.panGestureRecognizer.isEnabled = false
        vertical.addSubview(horizontal)
        horizontal.addSubview(disabled)
        disabled.addSubview(disabledPan)
        disabledPan.addSubview(card)
        let lock = CardScrollLock()
        lock.lock(above: card)
        lock.lock(above: card)
        #expect(!vertical.panGestureRecognizer.isEnabled && !horizontal.panGestureRecognizer.isEnabled)
        #expect(vertical.isScrollEnabled && horizontal.isScrollEnabled)
        #expect(!disabled.isScrollEnabled)
        lock.unlock()
        lock.unlock()
        #expect(vertical.isScrollEnabled && horizontal.isScrollEnabled)
        #expect(vertical.panGestureRecognizer.isEnabled && horizontal.panGestureRecognizer.isEnabled)
        #expect(!disabled.isScrollEnabled)
        #expect(disabledPan.isScrollEnabled && !disabledPan.panGestureRecognizer.isEnabled)
    }

    @Test func shineOffStillAllowsIndependentMaterialAndTouchInput() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 215))
        let driver = CardSurfaceMotionDriver(cardView: view) { _ in }
        CardMotionPreset.myDefault.configure(driver, surface: .myWallet)
        #expect(!driver.shineEnabled)
        #expect(driver.borderShineEnabled)
        #expect(driver.touchSpotEnabled)
        #expect(driver.touchSpotGradualAppearance)
        #expect(driver.touchSpotAppearanceDelay == CardMotionPreset.myDefault.holdDelay)
    }
}
