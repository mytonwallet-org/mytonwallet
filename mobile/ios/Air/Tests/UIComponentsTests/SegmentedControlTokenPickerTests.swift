import UIKit
import XCTest
@testable import UIComponents

@MainActor
final class SegmentedControlTokenPickerTests: XCTestCase {
    func testTokenTabsUseEqualWidthsWhenEveryTitleFits() throws {
        for titles in [["All", "Stablecoins", "Tokens"], ["Все", "Стейблкоины", "Токены"]] {
            let (_, model) = makeControl(titles: titles, width: 370)
            let layouts = try XCTUnwrap(model.itemLayouts())
            for layout in layouts {
                XCTAssertEqual(layout.labelFrame.width, 364 / 3, accuracy: 0.01)
            }
            XCTAssertEqual(try XCTUnwrap(layouts.last).labelFrame.maxX, 364, accuracy: 0.01)
        }
    }

    func testFiatTabsSwitchBetweenProportionalAndEqualWidthsWhenResized() throws {
        let (control, model) = makeControl(titles: ["All", "Fiat", "Stablecoins", "Tokens"], width: 370)
        control.setPagingProgress(2)

        for width: CGFloat in [370, 600, 370] {
            control.frame.size.width = width
            control.layoutIfNeeded()
            let layouts = try XCTUnwrap(model.itemLayouts())
            let availableWidth = width - 2 * model.constants.backgroundPadding
            if width == 600 {
                for layout in layouts {
                    XCTAssertEqual(layout.labelFrame.width, availableWidth / 4, accuracy: 0.01)
                }
            } else {
                XCTAssertGreaterThan(layouts[2].labelFrame.width, layouts[3].labelFrame.width)
                XCTAssertGreaterThan(layouts[3].labelFrame.width, layouts[1].labelFrame.width)
                XCTAssertGreaterThan(layouts[1].labelFrame.width, layouts[0].labelFrame.width)
            }
            for (layout, item) in zip(layouts, model.items) {
                let textWidth = (item.title as NSString).size(withAttributes: [.font: model.font]).width
                XCTAssertGreaterThanOrEqual(layout.labelFrame.width, textWidth + 2 * model.constants.innerPadding)
            }
            XCTAssertEqual(try XCTUnwrap(layouts.last).labelFrame.maxX, availableWidth, accuracy: 0.01)
            XCTAssertEqual(model.selectedItem?.id, "2")
            XCTAssertEqual(model.selectionFrame, layouts[2].labelFrame)
        }
    }

    private func makeControl(titles: [String], width: CGFloat) -> (WSegmentedControl, SegmentedControlModel) {
        let model = SegmentedControlModel(
            items: titles.enumerated().map {
                SegmentedControlItem(id: String($0.offset), title: $0.element, viewController: Content())
            },
            selection: .init(item1: "0"),
            style: .tokenPicker
        )
        let control = WSegmentedControl(model: model)
        control.frame = CGRect(x: 0, y: 0, width: width, height: 40)
        control.layoutIfNeeded()
        return (control, model)
    }

    private final class Content: UIViewController, WSegmentedControllerContent {
        var onScroll: ((CGFloat) -> Void)?
        var scrollingView: UIScrollView? { nil }
        func scrollToTop(animated: Bool) {}
        func calculateHeight(isHosted: Bool) -> CGFloat { 0 }
    }
}
