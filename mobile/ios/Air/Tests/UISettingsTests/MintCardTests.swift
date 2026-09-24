import CoreText
import Testing
import UIKit
import WalletContext
import WalletCore
import WalletResources
@testable import UISettings

@MainActor
@Suite("Mint card sheet", .serialized)
struct MintCardTests {
    init() {
        _ = WalletResourcesBundle.bundle.load()
        for font in ["SFCompactRoundedBold", "SFCompactDisplayMedium"] {
            if let url = WalletResourcesBundle.bundle.url(forResource: font, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    private var token: ApiToken {
        ApiToken(slug: "test-mycoin", name: "MyTonWallet Coin", symbol: "MY", decimals: 9, chain: .ton, tokenAddress: "test-address")
    }

    @Test
    func swipeRequiresIntentAndSupportsFlicksAndRTL() {
        for rtl in [false, true] {
            let forward = rtl ? -1 : 1
            #expect(MintCardPagingGesture.selectionOffset(translation: -30, velocity: 0, width: 400, isRTL: rtl) == 0)
            #expect(MintCardPagingGesture.selectionOffset(translation: -80, velocity: 0, width: 400, isRTL: rtl) == forward)
            #expect(MintCardPagingGesture.selectionOffset(translation: -20, velocity: -500, width: 400, isRTL: rtl) == forward)
            #expect(MintCardPagingGesture.selectionOffset(translation: 80, velocity: 0, width: 400, isRTL: rtl) == -forward)
            #expect(MintCardPagingGesture.selectionOffset(translation: -800, velocity: -2000, width: 400, isRTL: rtl) == forward)
            #expect(MintCardPagingGesture.selectionOffset(translation: -80, velocity: 0, width: 0, isRTL: rtl) == 0)
        }
    }

    @Test
    func changingCardsKeepsContentAndFooterStationary() {
        for width in [320.0, 402, 600] {
            let view = MintCardView(frame: CGRect(x: 0, y: 0, width: width, height: 500))
            view.configure(cardsInfo: DebugPromotionPreset.cardMintingCardsInfo, token: token)
            view.layoutIfNeeded()
            let benefits = view.benefits
            let button = view.upgradeButton
            let benefitsFrame = benefits.frame
            let buttonFrame = button.frame
            view.scrollView.contentOffset.y = 20
            for _ in 0..<10 {
                view.select(offset: 1, animated: false)
                view.layoutIfNeeded()
                #expect(view.benefits === benefits)
                #expect(view.upgradeButton === button)
                #expect(benefits.frame == benefitsFrame)
                #expect(button.frame == buttonFrame)
                #expect(benefits.transform == .identity)
                #expect(view.scrollView.contentOffset == CGPoint(x: 0, y: 20))
                #expect(view.backgroundColor == MintCardTypeInfo.at(page: view.selectedPage).surfaceColor)
                #expect(button.superview === view)
            }
            #expect(view.selectedPage == 0)
            view.select(offset: -1, animated: false)
            #expect(MintCardTypeInfo.at(page: view.selectedPage).type == .black)
        }
    }

    @Test
    func purchaseTracksSelectionAndCannotRepeatWhileSubmitting() {
        let view = MintCardView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        var purchases: [ApiMtwCardType] = []
        view.onUpgrade = { purchases.append($0) }
        #expect(!view.upgradeButton.isEnabled)
        view.configure(cardsInfo: DebugPromotionPreset.cardMintingCardsInfo, token: token)
        #expect(view.upgradeButton.isEnabled)
        view.select(offset: 2, animated: false)
        view.upgradeButton.sendActions(for: .touchUpInside)
        #expect(purchases == [.gold])
        view.isSubmitting = true
        view.select(offset: 1, animated: false)
        view.upgradeButton.sendActions(for: .touchUpInside)
        #expect(view.selectedPage == 2)
        #expect(!view.upgradeButton.isEnabled)
        #expect(purchases == [.gold])
        view.isSubmitting = false
        var soldOut = DebugPromotionPreset.cardMintingCardsInfo
        soldOut.byType[.gold]?.notMinted = 0
        view.configure(cardsInfo: soldOut, token: token)
        view.upgradeButton.sendActions(for: .touchUpInside)
        #expect(!view.upgradeButton.isEnabled)
        #expect(purchases == [.gold])
    }

    @Test
    func openingBeforePricingArrivesKeepsSelectionAndEnablesPurchaseWhenReady() {
        let view = MintCardView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        view.configure(cardsInfo: nil, token: token)
        view.select(offset: 2, animated: false)
        var purchases: [ApiMtwCardType] = []
        view.onUpgrade = { purchases.append($0) }
        #expect(!view.upgradeButton.isEnabled)
        view.upgradeButton.sendActions(for: .touchUpInside)
        #expect(purchases.isEmpty)

        view.configure(cardsInfo: DebugPromotionPreset.cardMintingCardsInfo, token: token)
        #expect(view.selectedPage == 2)
        #expect(view.upgradeButton.isEnabled)
        view.upgradeButton.sendActions(for: .touchUpInside)
        #expect(purchases == [.gold])
    }

    @Test
    func unavailablePricesAndTokenMetadataDisablePurchase() throws {
        var card = try #require(DebugPromotionPreset.cardMintingCardsInfo[.standard])
        #expect(MintCardPurchaseState(cardInfo: card, token: token).isEnabled)
        for price in [0, -1, Double.nan, Double.infinity, 0.00000000001] {
            card.price = price
            #expect(!MintCardPurchaseState(cardInfo: card, token: token).isEnabled)
        }
        card.price = 10
        var missingAddress = token
        missingAddress.tokenAddress = ""
        #expect(!MintCardPurchaseState(cardInfo: card, token: missingAddress).isEnabled)
        #expect(!MintCardPurchaseState(cardInfo: card, token: nil).isEnabled)
        #expect(!MintCardPurchaseState(cardInfo: nil, token: token).isEnabled)
        card.all = 0
        #expect(!MintCardPurchaseState(cardInfo: card, token: token).isEnabled)
    }

    @Test
    func countdownDecodesUTCAndNeverWrapsOrGoesNegative() throws {
        let card = try JSONDecoder().decode(ApiCardInfo.self, from: Data(
            #"{"all":10,"notMinted":0,"price":100,"startsAt":"2027-01-15T08:00:00Z"}"#.utf8
        ))
        let start = try #require(card.mintCountdownDate)
        #expect(start.timeIntervalSince1970 == 1_800_000_000)
        for (seconds, expected) in [(85_512.0, "23:45:12"), (90_061, "25:01:01"), (0.1, "00:00:01"), (0, "00:00:00"), (-10, "00:00:00")] {
            let purchase = MintCardPurchaseState(cardInfo: card, token: token, now: start.addingTimeInterval(-seconds))
            #expect(purchase.title == L10n.mintStartsInTime(time: expected))
            #expect(!purchase.isEnabled)
        }
        let legacyCard = try JSONDecoder().decode(ApiCardInfo.self, from: Data(
            #"{"all":10,"notMinted":0,"price":100}"#.utf8
        ))
        #expect(legacyCard.startsAt == nil)
        #expect(MintCardPurchaseState(cardInfo: legacyCard, token: token).title == lang("This card has been sold out"))
    }

    @Test
    func countdownParsesFractionalSecondsAndOffsetsAndIgnoresInvalidDates() throws {
        var card = try #require(DebugPromotionPreset.cardMintingCardsInfo[.standard])
        card.notMinted = 0
        for (startsAt, expected) in [
            ("2027-01-15T08:00:00.125Z", 1_800_000_000.125),
            ("2027-01-15T10:00:00+02:00", 1_800_000_000.0),
            ("2027-01-15T10:00:00.125+02:00", 1_800_000_000.125),
        ] {
            card.startsAt = startsAt
            #expect(card.mintCountdownDate?.timeIntervalSince1970 == expected)
            let decoded = try JSONDecoder().decode(ApiCardInfo.self, from: JSONEncoder().encode(card))
            #expect(decoded.startsAt == startsAt)
            #expect(decoded.mintCountdownDate == card.mintCountdownDate)
        }
        for startsAt in ["", "invalid-date"] {
            card.startsAt = startsAt
            #expect(card.mintCountdownDate == nil)
            #expect(MintCardPurchaseState(cardInfo: card, token: token).title == lang("This card has been sold out"))
        }
    }

    @Test
    func countdownRequiresExactlyZeroAvailableCards() throws {
        var card = try #require(DebugPromotionPreset.cardMintingCardsInfo[.standard])
        card.startsAt = Date.now.addingTimeInterval(3600).formatted(.iso8601)
        for available in [-1, 1, 10] {
            card.notMinted = available
            #expect(card.mintCountdownDate == nil)
            let purchase = MintCardPurchaseState(cardInfo: card, token: token)
            #expect(purchase.isEnabled == (available > 0))
        }
        card.notMinted = 0
        #expect(card.mintCountdownDate != nil)
        #expect(!MintCardPurchaseState(cardInfo: card, token: token).isEnabled)
        card.startsAt = nil
        #expect(card.mintCountdownDate == nil)
    }

    @Test
    func openSheetTracksCountdownStockAndStartTimeChanges() throws {
        let view = MintCardView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        var cards = DebugPromotionPreset.cardMintingCardsInfo
        view.select(offset: 2, animated: false)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        cards.byType[.gold]?.notMinted = 0
        cards.byType[.gold]?.startsAt = "2027-01-15T08:00:05Z"
        view.configure(cardsInfo: cards, token: token)
        view.refreshCountdown(now: now)
        #expect(view.upgradeButton.accessibilityLabel == L10n.mintStartsInTime(time: "00:00:05"))
        #expect(!view.upgradeButton.isEnabled)
        let availability = try #require(view.hero.accessibilityElements?.compactMap { $0 as? MintCardAvailabilityView }.first)
        #expect(availability.accessibilityLabel == L10n.amountUniqueCardsTotal(amount: cards[.gold]!.all))

        cards.byType[.gold]?.startsAt = "2027-01-15T08:00:10Z"
        view.configure(cardsInfo: cards, token: token)
        view.refreshCountdown(now: now)
        #expect(view.upgradeButton.accessibilityLabel == L10n.mintStartsInTime(time: "00:00:10"))
        view.refreshCountdown(now: now.addingTimeInterval(20))
        #expect(view.upgradeButton.accessibilityLabel == L10n.mintStartsInTime(time: "00:00:00"))
        #expect(!view.upgradeButton.isEnabled)

        cards.byType[.gold]?.notMinted = 1
        view.configure(cardsInfo: cards, token: token)
        #expect(view.upgradeButton.isEnabled)
        #expect(availability.accessibilityLabel?.contains(L10n.amountLeft(amount: localizedIntegerString(1))) == true)
        cards.byType[.gold]?.notMinted = 0
        cards.byType[.gold]?.startsAt = nil
        view.configure(cardsInfo: cards, token: token)
        #expect(view.upgradeButton.accessibilityLabel == lang("This card has been sold out"))
        #expect(availability.accessibilityLabel == lang("This card has been sold out"))
        #expect(view.selectedPage == 2)
    }

    @Test
    func visibleCountdownTicksAndRefreshesAfterResuming() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let view = MintCardView(frame: window.bounds)
        window.addSubview(view)
        var cards = DebugPromotionPreset.cardMintingCardsInfo
        cards.byType[.standard]?.notMinted = 0
        cards.byType[.standard]?.startsAt = Date.now.addingTimeInterval(30).formatted(.iso8601)
        view.configure(cardsInfo: cards, token: token)
        view.setPlaybackActive(true)
        let initialTitle = view.upgradeButton.accessibilityLabel
        try await Task.sleep(for: .milliseconds(1200))
        #expect(view.upgradeButton.accessibilityLabel != initialTitle)

        view.setPlaybackActive(false)
        let pausedTitle = view.upgradeButton.accessibilityLabel
        try await Task.sleep(for: .milliseconds(1200))
        #expect(view.upgradeButton.accessibilityLabel == pausedTitle)
        view.setPlaybackActive(true)
        #expect(view.upgradeButton.accessibilityLabel != pausedTitle)
        view.removeFromSuperview()
        let detachedTitle = view.upgradeButton.accessibilityLabel
        try await Task.sleep(for: .milliseconds(1200))
        #expect(view.upgradeButton.accessibilityLabel == detachedTitle)
    }

    @Test
    func voiceOverCanCycleCardsWithoutHijackingVerticalScrolling() {
        let view = MintCardView(frame: .zero)
        #expect(!view.accessibilityScroll(.up))
        #expect(view.accessibilityScroll(.next))
        #expect(view.selectedPage == 1)
        #expect(view.accessibilityScroll(.previous))
        #expect(view.selectedPage == 0)
        view.semanticContentAttribute = .forceRightToLeft
        #expect(view.accessibilityScroll(.right))
        #expect(view.selectedPage == 1)
    }
}
