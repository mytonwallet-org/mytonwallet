import Testing
import UIKit
import UIComponents
import WalletResources
@testable import UIToken

@Suite(.serialized) @MainActor
struct PerpsDetailsViewportTests {
    @Test
    func closePreparationSurvivesRefreshAndPreventsConflictingActions() throws {
        _ = WalletResourcesBundle.bundle.load()
        let market = PerpsMarketDisplayData(title: "Bitcoin Futures", token: .ETH, price: 80_000,
            percentChange24h: 0, history: [], description: "", fundingRate: "0.001%", maxLeverage: "40x", volume24h: "$1B", openInterest: "$2B")
        var data = PerpsPositionDisplayData(id: "position", market: market, direction: .long, leverage: 2,
            equity: .fromDouble(25, .USD), profitLoss: .init("$0"), invested: "$25", entryPrice: "$80 000",
            liquidationPrice: "$40 000", positionSize: "$50", fundingPayments: .init("$0"), canEdit: true, canClose: true)
        var actions: [PerpsPositionAction] = []
        let controller = PerpsPositionVC(data: data, onSelectPeriod: { _ in }, onAction: { actions.append($0) })
        controller.loadViewIfNeeded()
        func button(_ id: String, in view: UIView) -> WButton? {
            if let button = view as? WButton, button.accessibilityIdentifier == id { return button }
            return view.subviews.lazy.compactMap { button(id, in: $0) }.first
        }
        let close = try #require(button("perps.position.close", in: controller.view))
        let edit = try #require(button("perps.position.edit", in: controller.view))
        close.sendActions(for: .touchUpInside)
        #expect(actions.count == 1)

        controller.isPreparingClose = true
        data.equity = .fromDouble(26, .USD)
        controller.update(data: data)
        #expect(close.showLoading)
        #expect(!close.isUserInteractionEnabled)
        #expect(close.accessibilityTraits.contains(.notEnabled))
        #expect(!edit.isEnabled)
        close.sendActions(for: .touchUpInside)
        edit.sendActions(for: .touchUpInside)
        #expect(actions.count == 1)

        controller.isPreparingClose = false
        #expect(!close.showLoading)
        #expect(close.isUserInteractionEnabled && edit.isEnabled)
        close.sendActions(for: .touchUpInside)
        #expect(actions.count == 2)

        data.canClose = false
        controller.update(data: data)
        close.sendActions(for: .touchUpInside)
        #expect(actions.count == 2)
    }

    @Test(arguments: [false, true], [false, true])
    func cardsScrollBehindBothBarsAndRemainReachable(isPosition: Bool, isRightToLeft: Bool) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let controller = makeController(isPosition: isPosition)
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        controller.loadViewIfNeeded()
        func setLayoutDirection(_ view: UIView) {
            view.semanticContentAttribute = isRightToLeft ? .forceRightToLeft : .forceLeftToRight
            view.subviews.forEach(setLayoutDirection)
        }
        setLayoutDirection(controller.view)
        let layout = try #require(controller.view.subviews.compactMap { $0 as? AssetDetailsView }.first)
        let actions = try #require(layout.subviews.compactMap { $0 as? WActionButtonBar }.first)
        let footer = UIView()
        footer.heightAnchor.constraint(equalToConstant: 1_200).isActive = true
        layout.content.addArrangedSubview(footer)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        let scroll = layout.scrollView
        #expect(abs(layout.content.bounds.width - (layout.safeAreaLayoutGuide.layoutFrame.width - 32)) < 0.5)

        func checkInsets() {
            #expect(scroll.frame == layout.bounds)
            #expect(layout.frame == controller.view.bounds)
            #expect(abs(scroll.adjustedContentInset.top - layout.safeAreaInsets.top) < 0.5)
            #expect(abs(scroll.adjustedContentInset.bottom - (layout.bounds.maxY - actions.frame.minY + 12)) < 0.5)
            #expect(scroll.contentSize.width + scroll.adjustedContentInset.left + scroll.adjustedContentInset.right <= scroll.bounds.width + 0.5)
        }
        checkInsets()
        let first = try #require(layout.content.arrangedSubviews.first)
        scroll.contentOffset.y = -scroll.adjustedContentInset.top
        #expect(abs(first.convert(first.bounds, to: layout).minY - layout.safeAreaInsets.top - 8) < 0.5)

        scroll.contentOffset.y = 40
        let firstFrame = first.convert(first.bounds, to: layout)
        #expect(firstFrame.minY < layout.safeAreaInsets.top)
        #expect(firstFrame.maxY > 0)
        #expect(scroll.frame.contains(CGPoint(x: layout.bounds.midX, y: 1)))
        #expect(scroll.frame.contains(CGPoint(x: layout.bounds.midX, y: actions.frame.midY)))
        let behindButtons = try #require(layout.hitTest(CGPoint(x: 20, y: actions.frame.midY), with: nil))
        #expect(behindButtons === scroll || behindButtons.isDescendant(of: scroll))

        scroll.contentOffset.y = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
        #expect(abs(footer.convert(footer.bounds, to: layout).maxY - (actions.frame.minY - 28)) < 0.5)

        controller.additionalSafeAreaInsets = .init(top: 18, left: 40, bottom: 27, right: 8)
        window.layoutIfNeeded()
        checkInsets()
        #expect(layout.content.frame.width <= layout.safeAreaLayoutGuide.layoutFrame.width - 32 + 0.5)
        let contentFrame = layout.content.convert(layout.content.bounds, to: layout)
        #expect(abs(contentFrame.minX - layout.safeAreaInsets.left - 16) < 0.5)
        #expect(abs(contentFrame.maxX - (layout.bounds.maxX - layout.safeAreaInsets.right - 16)) < 0.5)
        scroll.contentOffset.y = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
        #expect(abs(footer.convert(footer.bounds, to: layout).maxY - (actions.frame.minY - 28)) < 0.5)
    }

    private func makeController(isPosition: Bool) -> UIViewController {
        let market = PerpsMarketDisplayData(title: "Ethereum Futures", token: .ETH, price: 2_000,
            percentChange24h: 3, history: [], description: String(repeating: "A futures market description. ", count: 15),
            fundingRate: "0.001%", maxLeverage: "40x", volume24h: "$1.9B", openInterest: "$2.2B")
        if isPosition {
            let data = PerpsPositionDisplayData(id: "position", market: market, direction: .long, leverage: 5,
                equity: .fromDouble(130, .USD), profitLoss: .init("+$30"), invested: "$100", entryPrice: "$2 000",
                liquidationPrice: "$1 600", positionSize: "$500", fundingPayments: .init("$0.1"))
            return PerpsPositionVC(data: data, onSelectPeriod: { _ in }, onAction: { _ in })
        }
        return PerpsMarketVC(data: market, onSelectPeriod: { _ in }, onSelectDirection: { _ in })
    }
}
