import UIKit
import XCTest
@testable import UIComponents

@MainActor
final class SegmentedControlRootHeaderTests: XCTestCase {
    func testFiveRootTabsKeepTheirTitlesAndPaddingAcrossWidthsAndLocalizations() throws {
        let titlesByLocale = [
            ["Wallet", "Market", "Futures", "Agent", "Explore"],
            ["Кошелёк", "Рынок", "Фьючерсы", "Агент", "Обзор"],
            ["المحفظة", "السوق", "العقود الآجلة", "المساعد", "استكشاف"],
            ["Wallet", "Global Futures Markets", "X", "Y", "Z"],
        ]
        for titles in titlesByLocale {
            for headerWidth: CGFloat in [234, 289, 316, 600] {
                let (control, model) = makeControl(titles: titles, width: headerWidth)
                let scroll = try XCTUnwrap(descendants(control).compactMap { $0 as? UIScrollView }.first)
                let layouts = try XCTUnwrap(model.itemLayouts())
                let naturalWidth = model.calculateContentWidth(includeBackground: false)
                XCTAssertEqual(scroll.isScrollEnabled, naturalWidth > scroll.bounds.width)
                for (layout, title) in zip(layouts, titles) {
                    let textWidth = (title as NSString).size(withAttributes: [.font: model.font]).width
                    XCTAssertGreaterThanOrEqual(layout.labelFrame.width, textWidth + 2 * model.constants.innerPadding, title)
                }
            }
        }
    }

    func testOverflowScrollsSelectedTabIntoViewAndAdaptsToResizingInBothDirections() throws {
        for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
            let (control, model) = makeControl(titles: ["Wallet", "Market", "Futures", "Agent", "Explore"], width: 234)
            control.semanticContentAttribute = direction
            control.setNeedsLayout()
            control.layoutIfNeeded()
            let scroll = try XCTUnwrap(descendants(control).compactMap { $0 as? UIScrollView }.first)
            XCTAssertTrue(scroll.isScrollEnabled)

            for index in [4, 0, 3] {
                control.setPagingProgress(CGFloat(index))
                let selected = try XCTUnwrap(control.contextMenuActivationView(forItemId: String(index)))
                let frame = selected.convert(selected.bounds, to: scroll)
                XCTAssertGreaterThanOrEqual(frame.minX, scroll.bounds.minX - 0.5)
                XCTAssertLessThanOrEqual(frame.maxX, scroll.bounds.maxX + 0.5)
                XCTAssertEqual(model.selectedItem?.id, String(index))
            }

            control.frame.size.width = 600
            control.layoutIfNeeded()
            XCTAssertFalse(scroll.isScrollEnabled)
            control.frame.size.width = 234
            control.layoutIfNeeded()
            XCTAssertTrue(scroll.isScrollEnabled)
            let selected = try XCTUnwrap(control.contextMenuActivationView(forItemId: "3"))
            let frame = selected.convert(selected.bounds, to: scroll)
            XCTAssertGreaterThanOrEqual(frame.minX, scroll.bounds.minX - 0.5)
            XCTAssertLessThanOrEqual(frame.maxX, scroll.bounds.maxX + 0.5)
        }
    }

    func testRootTabsAreSizedByTheirTitlesAndScrollOnNarrowPhoneHeader() throws {
        for phoneWidth: CGFloat in [320, 375] {
            let model = SegmentedControlModel(
                items: ["Wallet", "Market", "Agent", "Explore"].map {
                    SegmentedControlItem(id: $0, title: $0, viewController: Content())
                },
                selection: .init(item1: "Wallet"),
                style: .compactRootHeader
            )
            let control = WSegmentedControl(model: model)
            let headerWidth = phoneWidth - 32 - 44 - 10
            control.frame = CGRect(x: 0, y: 0, width: headerWidth, height: 40)
            control.layoutIfNeeded()

            let layouts = try XCTUnwrap(model.itemLayouts())
            XCTAssertEqual(layouts.map(\.id), ["Wallet", "Market", "Agent", "Explore"])
            var previousMaxX: CGFloat = 0
            for layout in layouts {
                let textWidth = (layout.id as NSString).size(withAttributes: [.font: model.font]).width
                XCTAssertEqual(layout.labelFrame.width, textWidth + 2 * model.constants.innerPadding, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(layout.labelFrame.minX, previousMaxX - 0.5)
                previousMaxX = layout.labelFrame.maxX
            }
            let scrollView = try XCTUnwrap(descendants(control).compactMap { $0 as? UIScrollView }.first)
            let contentWidth = model.calculateContentWidth(includeBackground: true)
            XCTAssertEqual(scrollView.isScrollEnabled, contentWidth > headerWidth)
            if contentWidth > headerWidth {
                XCTAssertGreaterThan(scrollView.contentSize.width, scrollView.bounds.width)
            }
        }
    }

    private func makeControl(titles: [String], width: CGFloat) -> (WSegmentedControl, SegmentedControlModel) {
        let model = SegmentedControlModel(
            items: titles.enumerated().map {
                SegmentedControlItem(id: String($0.offset), title: $0.element, viewController: Content())
            },
            selection: .init(item1: "0"),
            style: .compactRootHeader
        )
        let control = WSegmentedControl(model: model)
        control.frame = CGRect(x: 0, y: 0, width: width, height: 40)
        control.layoutIfNeeded()
        return (control, model)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private final class Content: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 0 }
    }
}
