import UIKit
import XCTest
@testable import AirAsFramework
@testable import UIComponents

@MainActor
final class AgentHeaderPlatterTransitionTests: XCTestCase {
    private struct Header {
        let window: UIWindow
        let chat: AgentHeaderPlatterTransition.Bar
        let list: AgentHeaderPlatterTransition.Bar
        let tabsFrame: CGRect
    }

    /// The list's tabs, with no avatar beside them, turn back into the chat's threads button, title pill and more
    /// button: the side buttons collapse into the tabs, and the merged glass keeps to the tabs' width, swelling and
    /// bouncing only by the tabs' own spring
    func testPoppingKeepsTheMergedGlassWithinTheTabs() async throws {
        let header = makeHeader()
        defer { header.window.isHidden = true }
        let extent = try await measure(AgentHeaderPlatterTransition(
            outgoing: { header.chat },
            incoming: { header.list },
            pillSwellStrength: CGSize(width: 1.0 / 3, height: 1)
        ), in: header.window)

        XCTAssertGreaterThanOrEqual(extent.minX, header.tabsFrame.minX - 6)
        XCTAssertLessThanOrEqual(extent.maxX, header.tabsFrame.maxX + 6)
        XCTAssertGreaterThan(extent.widestCapsule, header.tabsFrame.width + 1, "The tabs keep their slight bounce")
    }

    /// The side buttons grow out of the tabs as they turn into the title pill, without the glass reaching past the
    /// screen's edges
    func testPushingKeepsTheGlassOnScreen() async throws {
        let header = makeHeader()
        defer { header.window.isHidden = true }
        let extent = try await measure(AgentHeaderPlatterTransition(
            outgoing: { header.list },
            incoming: { header.chat }
        ), in: header.window)

        XCTAssertGreaterThanOrEqual(extent.minX, 0)
        XCTAssertLessThanOrEqual(extent.maxX, header.window.bounds.width)
    }

    /// The copy of the tabs the transition draws in their place shows the selection as the lens shows it at rest, in
    /// both appearances: the lens's own tint over the glass and the selected title alike, which colors the title
    /// without blurring it, rather than a picture of the screen, whose glass shows the title through it
    func testTabsCopyShowsTheSelectedTitleUnderTheLensRestingTint() throws {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            let model = SegmentedControlModel(
                items: ["Wallet", "Market", "Agent", "Explore"].map {
                    SegmentedControlItem(id: $0, title: $0, viewController: TabContent())
                },
                selection: .init(item1: "Agent"),
                primaryColor: .tintColor,
                capsuleColor: .systemGray5,
                style: .compactRootHeader
            )
            let tabs = WSegmentedControl(model: model, isGlassInteractive: true)
            let host = UIViewController()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 420, height: 912))
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            tabs.frame = CGRect(x: 20, y: 70, width: 320, height: 44)
            host.view.addSubview(tabs)
            tabs.layoutIfNeeded()

            let copy = try XCTUnwrap(tabs.makeContentSnapshot())
            host.view.addSubview(copy)
            let content = try XCTUnwrap(copy.subviews.first)
            XCTAssertEqual(content.subviews.count, 3, "The titles, the selected titles and the selection")
            XCTAssertFalse(findDescendants(of: copy).contains { String(describing: type(of: $0)).contains("Replicant") })
            guard NSClassFromString("_UILiquidLensView") != nil else {
                XCTAssertNotNil(content.subviews[1].backgroundColor)
                XCTAssertTrue(content.subviews[2].subviews.contains { ($0 as? UILabel)?.text == "Agent" })
                continue
            }
            let selected = content.subviews[1]
            let capsule = content.subviews[2]
            XCTAssertTrue(selected.subviews.contains { ($0 as? UILabel)?.text == "Agent" })
            let tint = try XCTUnwrap(capsule.subviews.first as? UIVisualEffectView)
            XCTAssertEqual(tint.frame, capsule.bounds)
            let filters = (tint.layer.sublayers?.first?.filters ?? []).compactMap {
                ($0 as? NSObject)?.value(forKey: "name") as? String
            }
            XCTAssertEqual(filters, ["colorMatrix"])
        }
    }

    private func makeHeader() -> Header {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 420, height: 912))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let host = window.rootViewController!.view!
        func makeCapsule(x: CGFloat, width: CGFloat) -> UIView {
            let view = UIView(frame: CGRect(x: x, y: 70, width: width, height: 44))
            host.addSubview(view)
            return view
        }
        func makeContent(width: CGFloat) -> UIView {
            UIView(frame: CGRect(x: 0, y: 0, width: width, height: 24))
        }
        let tabs = makeCapsule(x: 20, width: 380)
        let chat = AgentHeaderPlatterTransition.Bar(
            leading: .init(view: makeCapsule(x: 21, width: 44), makeItem: { makeContent(width: 24) }),
            pill: .init(view: makeCapsule(x: 85, width: 250), makeItem: { makeContent(width: 200) }),
            trailing: .init(view: makeCapsule(x: 356, width: 44), makeItem: { makeContent(width: 24) })
        )
        let list = AgentHeaderPlatterTransition.Bar(
            pill: .init(view: tabs, makeItem: { makeContent(width: 360) }, shouldSwapOnHandOff: true, shouldKeepContentScale: true),
            isTrailingGrowingFromPill: true
        )
        return Header(window: window, chat: chat, list: list, tabsFrame: tabs.frame)
    }

    /// The leftmost and rightmost edges the transition's glass reaches as it runs, and the widest single capsule
    private func measure(
        _ transition: AgentHeaderPlatterTransition,
        in window: UIWindow
    ) async throws -> (minX: CGFloat, maxX: CGFloat, widestCapsule: CGFloat) {
        let start = CACurrentMediaTime()
        transition.run(in: window) {}
        defer { transition.cancel() }
        var extent = (minX: CGFloat.greatestFiniteMagnitude, maxX: -CGFloat.greatestFiniteMagnitude, widestCapsule: CGFloat(0))
        while CACurrentMediaTime() - start < 0.8 {
            try await Task.sleep(for: .milliseconds(5))
            let glass = window.subviews.flatMap { overlay in
                overlay.subviews.compactMap { $0 as? UIVisualEffectView }.flatMap {
                    $0.contentView.subviews.compactMap { $0 as? UIVisualEffectView }
                }
            }
            for frame in glass.map(\.frame) {
                extent.minX = min(extent.minX, frame.minX)
                extent.maxX = max(extent.maxX, frame.maxX)
                extent.widestCapsule = max(extent.widestCapsule, frame.width)
            }
        }
        XCTAssertLessThan(extent.minX, extent.maxX, "The transition draws its glass")
        return extent
    }

    private final class TabContent: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 0 }
    }

    private func findDescendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + findDescendants(of: $0) }
    }
}
