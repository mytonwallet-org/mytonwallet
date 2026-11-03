import UIKit
import XCTest
@testable import UIComponents

@MainActor
final class RootTabsPagingScrollTests: XCTestCase {
    /// Swiping from Market to Agent on a header a little narrower than the tabs, the strip scrolls along the whole
    /// swipe, in step with the pager, from Market's resting offset to Agent's, rather than all at once halfway
    func testStripFollowsTheSwipeBetweenTwoTabs() throws {
        for isRightToLeft in [false, true] {
            let model = SegmentedControlModel(
                items: ["Кошелёк", "Маркет", "Агент", "Обзор"].map {
                    SegmentedControlItem(id: $0, title: $0, viewController: TabContent())
                },
                selection: .init(item1: "Маркет"),
                style: .compactRootHeader
            )
            let control = WSegmentedControl(model: model, isGlassInteractive: true)
            control.semanticContentAttribute = isRightToLeft ? .forceRightToLeft : .forceLeftToRight
            let host = UIViewController()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            host.view.addSubview(control)
            control.frame = CGRect(x: 16, y: 70, width: 100, height: 44)
            control.layoutIfNeeded()
            let contentWidth = model.calculateContentWidth(includeBackground: true)
            control.frame.size.width = contentWidth - 20
            control.layoutIfNeeded()
            let scrollView = try XCTUnwrap(findDescendants(of: control).compactMap { $0 as? UIScrollView }.first)
            XCTAssertTrue(scrollView.isScrollEnabled)

            control.setPagingProgress(1)
            let marketOffset = scrollView.contentOffset.x
            control.setPagingProgress(2)
            let agentOffset = scrollView.contentOffset.x
            XCTAssertGreaterThan(abs(agentOffset - marketOffset), 5, "The strip scrolls between the two tabs")

            let stepCount = 20
            for step in 0...stepCount {
                let fraction = CGFloat(step) / CGFloat(stepCount)
                control.setPagingProgress(1 + fraction)
                XCTAssertEqual(
                    scrollView.contentOffset.x,
                    marketOffset + (agentOffset - marketOffset) * fraction,
                    accuracy: 0.5,
                    "\(isRightToLeft ? "RTL" : "LTR") at \(fraction)"
                )
            }
        }
    }

    private func findDescendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + findDescendants(of: $0) }
    }

    private final class TabContent: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 0 }
    }
}
