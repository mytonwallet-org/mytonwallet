import CoreText
import os
import Perception
import Testing
import UIKit
import WalletCore
import WalletResources
@testable import UIComponents

@MainActor
@Suite("UIKit home card balance", .serialized)
struct MtwCardBalanceLabelTests {
    init() {
        _ = WalletResourcesBundle.bundle.load()
        for font in ["SFCompactRoundedBold", "SFCompactDisplayMedium"] {
            if let url = WalletResourcesBundle.bundle.url(forResource: font, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    @Test
    func renderingDoesNotSubscribeItsCallerToLabelState() {
        let view = MtwCardBalanceLabelView()
        let invalidations = OSAllocatedUnfairLock(initialState: 0)
        withPerceptionTracking {
            configure(view, amount: 100)
            _ = view.lineHeight
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }

        configure(view, amount: 200, style: .homeCollaped)

        #expect(invalidations.withLock { $0 } == 0)
    }

    @Test
    func swipingAnUnchangedBalanceDoesNotRebuildTheSwiftUIHost() {
        let view = MtwCardBalanceLabelView()
        configure(view, amount: 100)
        let initialUpdates = view.hostingConfigurationUpdateCount
        for _ in 0..<4 {
            configure(view, amount: 100, scrolling: true)
            configure(view, amount: 100)
        }
        #expect(view.hostingConfigurationUpdateCount == initialUpdates)

        configure(view, amount: 120)
        #expect(view.numericTransitionCount == 1)
        let animatedUpdates = view.hostingConfigurationUpdateCount
        configure(view, amount: 130, scrolling: true)
        #expect(view.hostingConfigurationUpdateCount == animatedUpdates + 1)
        #expect(view.displayedBalance == .fromDouble(120, .USD))
        configure(view, amount: 150, scrolling: true)
        #expect(view.hostingConfigurationUpdateCount == animatedUpdates + 1)
        configure(view, amount: 150)
        #expect(view.displayedBalance == .fromDouble(150, .USD))
        #expect(view.numericTransitionCount == 2)
    }

    @Test
    func reuseBuildsOnlyTheIncomingLabel() {
        let view = MtwCardBalanceLabelView()
        configure(view, amount: 100)
        let initialUpdates = view.hostingConfigurationUpdateCount
        view.prepareForReuse()
        view.prepareForReuse()
        #expect(view.displayedBalance == nil)
        #expect(view.hostingConfigurationUpdateCount == initialUpdates)
        configure(view, amount: 200)
        #expect(view.hostingConfigurationUpdateCount == initialUpdates + 1)
        #expect(view.numericTransitionCount == 0)
    }

    @Test
    func hiddenBalancesOnlyRenderWhenRevealed() {
        let view = MtwCardBalanceLabelView()
        configure(view, amount: 100, hidden: true)
        configure(view, amount: 200, hidden: true)
        #expect(view.hostingConfigurationUpdateCount == 0)
        #expect(view.displayedBalance == .fromDouble(200, .USD))

        configure(view, amount: 200)
        #expect(view.hostingConfigurationUpdateCount == 1)
        configure(view, amount: 200, hidden: true)
        configure(view, amount: 300, hidden: true)
        #expect(view.hostingConfigurationUpdateCount == 1)

        configure(view, amount: 350)
        #expect(view.hostingConfigurationUpdateCount == 2)
        #expect(view.displayedBalance == .fromDouble(350, .USD))
        #expect(view.numericTransitionCount == 0)
    }

    @Test
    func swipesCoalesceUpdatesAndReuseDiscardsThePreviousBalance() {
        let view = MtwCardBalanceLabelView()
        configure(view, amount: 100)
        for amount in [120.0, 140, 170] {
            configure(view, amount: amount, scrolling: true)
            #expect(view.displayedBalance == .fromDouble(100, .USD))
            #expect(view.numericTransitionCount == 0)
        }

        configure(view, amount: 170)
        #expect(view.displayedBalance == .fromDouble(170, .USD))
        #expect(view.numericTransitionCount == 1)
        configure(view, amount: 170)
        #expect(view.numericTransitionCount == 1)

        configure(view, amount: 190, scrolling: true)
        view.prepareForReuse()
        configure(view, amount: 500, scrolling: true)
        #expect(view.displayedBalance == .fromDouble(500, .USD))
        #expect(view.numericTransitionCount == 0)
    }

    private func configure(_ view: MtwCardBalanceLabelView, amount: Double,
                           style: MtwCardBalanceView.Style = .homeCard, scrolling: Bool = false, hidden: Bool = false) {
        view.configure(balance: .fromDouble(amount, .USD), style: style, nft: nil,
                       usesCardGradient: true, isHidden: hidden, isScrolling: scrolling, animates: true)
    }

    @Test
    func privacyMasksStayCenteredThroughInsertionResizeAndReuse() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let balance = MtwCardBalanceLabelView()
        let change = MtwCardChangeView()
        host.addSubview(balance)
        host.addSubview(change)

        for style in [MtwCardBalanceView.Style.homeNavigationBarCollapsed, .homeCard, .homeCollaped] {
            for hidden in [false, true] {
                balance.configure(balance: .fromDouble(3100, .USD), style: style, nft: nil,
                                  usesCardGradient: false, isHidden: hidden, isScrolling: false, animates: false)
                change.configure(balance: .fromDouble(3100, .USD), previous: .fromDouble(3000, .USD),
                                 percent: 3, nft: nil, isHidden: hidden)
                for width in [210.0, 305.0] {
                    balance.frame = CGRect(x: 30, y: 170, width: width, height: balance.lineHeight)
                    change.frame = CGRect(x: 16, y: 240, width: width + 65, height: 26)
                    host.setNeedsLayout()
                    host.layoutIfNeeded()
                    guard hidden else { continue }
                    for view in [balance, change] as [UIView] {
                        let mask = try #require(descendants(of: view).compactMap { $0 as? ShyMask }.first)
                        #expect(!mask.hasAmbiguousLayout)
                        let frame = mask.convert(mask.bounds, to: view)
                        #expect(abs(frame.midX - view.bounds.midX) < 0.5)
                        #expect(abs(frame.midY - view.bounds.midY) < 0.5)
                    }
                }
            }
            balance.prepareForReuse()
            change.prepareForReuse()
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @Test
    func privacyCrossfadeKeepsMasksAtTheirFinalSizeAndPosition() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        let animationsWereEnabled = AppStorageHelper.animations
        AppStorageHelper.animations = true
        defer {
            window.isHidden = true
            AppStorageHelper.animations = animationsWereEnabled
        }
        let balance = MtwCardBalanceLabelView()
        let change = MtwCardChangeView()
        balance.frame = CGRect(x: 40, y: 170, width: 300, height: 54)
        change.frame = CGRect(x: 40, y: 240, width: 300, height: 26)
        host.view.addSubview(balance)
        host.view.addSubview(change)
        func configure(hidden: Bool) {
            balance.configure(balance: .fromDouble(3100, .USD), style: .homeCard, nft: nil,
                              usesCardGradient: true, isHidden: hidden, isScrolling: false, animates: true)
            change.configure(balance: .fromDouble(3100, .USD), previous: .fromDouble(3000, .USD),
                             percent: 3, nft: nil, isHidden: hidden)
        }
        configure(hidden: false)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        configure(hidden: true)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(60))
        for view in [balance, change] as [UIView] {
            let mask = try #require(descendants(of: view).compactMap { $0 as? ShyMask }.first)
            let presented = try #require(mask.layer.presentation())
            #expect(abs(presented.bounds.width - mask.bounds.width) < 0.5)
            #expect(abs(presented.bounds.height - mask.bounds.height) < 0.5)
            #expect(abs(presented.position.x - mask.layer.position.x) < 0.5)
            #expect(abs(presented.position.y - mask.layer.position.y) < 0.5)
        }
    }

    @Test
    func cardActionsYieldToScrollingAndSupportAccessibilityActivation() {
        let content = MtwCardContentView(mode: .expanded)
        let scrollView = UIScrollView()
        let actions: [MtwCardTapView] = [content.balance, content.change, content.accountLine.addressesButton,
                                       content.accountLine.saveButton, content.promotionButton]
        for action in actions {
            #expect(scrollView.touchesShouldCancel(in: action))
            var activations = 0
            action.onTap = { activations += 1 }
            #expect(action.accessibilityActivate())
            #expect(activations == 1)
        }
    }
}
