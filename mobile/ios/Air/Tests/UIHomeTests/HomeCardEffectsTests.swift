import XCTest
import Dependencies
@testable import UIComponents
import UIKit
import WalletCore
import WalletResources
@testable import UIHome

@MainActor
final class HomeCardEffectsTests: XCTestCase {
    func testBadgeFinishIsReadyBeforeSelectionAndSurvivesScrollSettle() async throws {
        _ = WalletResourcesBundle.bundle.load()
        try await withDependencies { $0.context = .live } operation: {
            let account = MAccount(id: "badge-scroll-mainnet", title: "View wallet", type: .view,
                byChain: [.ton: AccountChain(address: "UQDQ7EXuEywyezyEWzfNkHZTSbe8qbPKETFYHr_KTZnnJ-xL")])
            for isSelected in [false, true] {
                let model = HomeHeaderViewModel(accountSource: .accountId(isSelected ? account.id : "neighbor"))
                model.isVisible = true
                model.isAccountScrolling = true
                let layout = HomeCardLayoutMetrics.forContainerWidth(402)
                let card = HomeCard(frame: .zero)
                card.configure(headerViewModel: model, accountContext: AccountContext(source: .constant(account)), layout: layout)
                let line = try XCTUnwrap(descendants(card.cardContentMaskingContainer).compactMap { $0 as? MtwCardAccountLineView }.first)
                let badge = try XCTUnwrap(descendants(line).compactMap { $0 as? CardBadgeBackground }.first)
                let gradients = try XCTUnwrap(badge.layer.sublayers?.compactMap { $0 as? CAGradientLayer })
                XCTAssertEqual(gradients.count, 2)
                XCTAssertTrue(gradients.allSatisfy { !$0.isHidden }, "Finish must exist in the first configured frame, before selection or a motion callback")
                let colors = gradients.map { $0.colors as? [CGColor] }
                for scrolling in [false, true, false] {
                    model.isAccountScrolling = scrolling
                    try await Task.sleep(for: .milliseconds(30))
                    card.layoutIfNeeded()
                    XCTAssertEqual(model.allowsCardEffects(for: account.id), isSelected && !scrolling)
                    XCTAssertTrue(gradients.allSatisfy { !$0.isHidden }, "Scrolling must pause input without replacing the badge finish")
                    XCTAssertEqual(gradients.map { $0.colors as? [CGColor] }, colors)
                    XCTAssertEqual(line.layer.shadowOpacity, 0)
                }
                card.prepareForReuse()
            }
        }
    }

    func testSidebarUsesCoverFlowAndGradientsFollowScrollResizeAndDirection() async throws {
        _ = WalletResourcesBundle.bundle.load()
        try await withDependencies { $0.context = .live } operation: {
            let account = MAccount(id: "sidebar-motion-mainnet", title: "View wallet", type: .view,
                byChain: [.ton: AccountChain(address: "UQDQ7EXuEywyezyEWzfNkHZTSbe8qbPKETFYHr_KTZnnJ-xL")])
            for mode: HomeAccountSelector.Mode in [.home, .sidebar] {
                let model = HomeHeaderViewModel(accountSource: .constant(account))
                let selector = HomeAccountSelector(viewModel: model, mode: mode)
                XCTAssertTrue(selector.usesCoverFlow)
                let leading = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 200))
                let trailing = UIView(frame: leading.frame)
                selector.setEdgeGradients(leading: leading, trailing: trailing)
                for rtl in [false, true] {
                    selector.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
                    model.isAccountScrolling = true
                    try await Task.sleep(for: .milliseconds(40))
                    for width: CGFloat in [16, 24] {
                        leading.bounds.size.width = width
                        trailing.bounds.size.width = width
                        selector.setNeedsLayout()
                        selector.layoutIfNeeded()
                        XCTAssertEqual(leading.transform.tx, rtl ? width : -width)
                        XCTAssertEqual(trailing.transform.tx, rtl ? -width : width)
                    }
                    model.isAccountScrolling = false
                    try await Task.sleep(for: .milliseconds(40))
                    XCTAssertEqual(leading.transform, .identity)
                    XCTAssertEqual(trailing.transform, .identity)
                }
                model.state = .collapsed
                model.isAccountScrolling = true
                try await Task.sleep(for: .milliseconds(40))
                XCTAssertFalse(selector.usesCoverFlow)
                XCTAssertEqual(leading.transform, .identity)
                XCTAssertEqual(trailing.transform, .identity)
            }
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    func testEffectsOnlyRunOnVisibleExpandedIdleCards() {
        let model = HomeHeaderViewModel(accountSource: .accountId("preview"))
        XCTAssertFalse(model.allowsCardEffects(for: "preview"))
        model.isVisible = true
        XCTAssertTrue(model.allowsCardEffects(for: "preview"))
        XCTAssertFalse(model.allowsCardEffects(for: "neighbor"))
        model.isAccountScrolling = true
        XCTAssertFalse(model.allowsCardEffects(for: "preview"))
        model.isAccountScrolling = false
        model.state = .collapsed
        XCTAssertFalse(model.allowsCardEffects(for: "preview"))
        model.state = .expanded
        XCTAssertTrue(model.allowsCardEffects(for: "preview"))
        model.isVisible = false
        XCTAssertFalse(model.allowsCardEffects(for: "preview"))
    }
}
