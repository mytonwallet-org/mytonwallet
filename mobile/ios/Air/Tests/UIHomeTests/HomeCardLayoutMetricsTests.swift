import XCTest
import UIKit
@testable import UIHome

final class HomeCardLayoutMetricsTests: XCTestCase {
    func testAsymmetricMarginsAlignCardsAndKeepPagingStride() {
        for margins in [
            NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 84),
            NSDirectionalEdgeInsets(top: 0, leading: 84, bottom: 0, trailing: 20),
        ] {
            let metrics = HomeCardLayoutMetrics.forContainerWidth(466, contentMargins: margins)
            XCTAssertEqual(metrics.itemWidth, 362)
            XCTAssertEqual(metrics.leadingInset, margins.leading)
            XCTAssertEqual(metrics.trailingInset, margins.trailing)
            // The final page can rest at the same position as the first page.
            let contentWidth = metrics.leadingInset + 3 * metrics.itemWidth + 2 * metrics.spacing + metrics.trailingInset
            XCTAssertEqual(contentWidth - 466, 2 * metrics.itemWidthWithSpacing)
        }
    }

    func testWideCardsStayCenteredWithinContentMargins() {
        let metrics = HomeCardLayoutMetrics.forContainerWidth(800, contentMargins: .init(top: 0, leading: 20, bottom: 0, trailing: 84))
        XCTAssertEqual(metrics.itemWidth, 450)
        XCTAssertEqual(metrics.leadingInset - 20, metrics.trailingInset - 84)
        XCTAssertEqual(metrics.leadingInset + metrics.itemWidth + metrics.trailingInset, 800)
    }

    func testDefaultSelectorKeepsExistingSymmetricGeometry() {
        let metrics = HomeCardLayoutMetrics.forContainerWidth(402)
        XCTAssertEqual(metrics.itemWidth, 370)
        XCTAssertEqual(metrics.leadingInset, 16)
        XCTAssertEqual(metrics.trailingInset, 16)
        XCTAssertEqual(metrics.spacing, 8)
    }
}
