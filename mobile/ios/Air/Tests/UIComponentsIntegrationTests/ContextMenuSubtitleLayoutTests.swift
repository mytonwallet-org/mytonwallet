import UIKit
import XCTest
@testable import ContextMenuKit

@MainActor
final class ContextMenuSubtitleLayoutTests: XCTestCase {
    func testTwoLineDescriptionsFitCompactMenuRowsWithoutChangingDefaultRows() throws {
        let subtitle = "Торгуйте криптовалютой и реальными активами"
        for width: CGFloat in [288, 340] {
            for direction in [UIUserInterfaceLayoutDirection.leftToRight, .rightToLeft] {
                let defaultRow = makeRow(subtitle: subtitle, style: ContextMenuStyle(), direction: direction)
                let wrappedRow = makeRow(subtitle: subtitle, style: ContextMenuStyle(subtitleNumberOfLines: 2), direction: direction)
                let defaultHeight = defaultRow.measuredSize(maxWidth: width).height
                let wrappedHeight = wrappedRow.measuredSize(maxWidth: width).height
                defaultRow.frame.size = CGSize(width: width, height: defaultHeight)
                wrappedRow.frame.size = CGSize(width: width, height: wrappedHeight)
                defaultRow.applyLayout(size: defaultRow.bounds.size)
                wrappedRow.applyLayout(size: wrappedRow.bounds.size)

                let defaultSubtitle = try XCTUnwrap(defaultRow.subviews.compactMap { $0 as? UILabel }.first { $0.text == subtitle })
                let wrappedSubtitle = try XCTUnwrap(wrappedRow.subviews.compactMap { $0 as? UILabel }.first { $0.text == subtitle })
                let title = try XCTUnwrap(wrappedRow.subviews.compactMap { $0 as? UILabel }.first { $0.text == "Рынок" })
                XCTAssertEqual(defaultSubtitle.numberOfLines, 1)
                XCTAssertEqual(defaultSubtitle.lineBreakMode, .byTruncatingTail)
                XCTAssertEqual(defaultSubtitle.frame.height, defaultSubtitle.font.lineHeight, accuracy: 1)

                let fullText = UILabel()
                fullText.font = wrappedSubtitle.font
                fullText.text = subtitle
                fullText.numberOfLines = 0
                fullText.lineBreakMode = .byWordWrapping
                let requiredHeight = fullText.sizeThatFits(CGSize(width: wrappedSubtitle.bounds.width, height: .greatestFiniteMagnitude)).height
                XCTAssertEqual(wrappedSubtitle.frame.height, requiredHeight, accuracy: 1)
                XCTAssertLessThanOrEqual(requiredHeight, wrappedSubtitle.font.lineHeight * 2 + 1)
                XCTAssertGreaterThanOrEqual(wrappedSubtitle.frame.minY, title.frame.maxY)
                XCTAssertLessThanOrEqual(wrappedSubtitle.frame.maxY, wrappedRow.bounds.maxY)
                XCTAssertGreaterThanOrEqual(wrappedHeight, defaultHeight)
                if width == 288 { XCTAssertGreaterThan(wrappedHeight, defaultHeight) }
            }
        }
    }

    private func makeRow(subtitle: String, style: ContextMenuStyle, direction: UIUserInterfaceLayoutDirection) -> ContextMenuRowView {
        ContextMenuRowView(
            presentation: ContextMenuRowPresentation(
                title: "Рынок", subtitle: subtitle, icon: .system("chart.line.uptrend.xyaxis"),
                badgeText: nil, role: .normal, isEnabled: true, accessory: .none
            ),
            style: style,
            sourceUserInterfaceLayoutDirection: direction
        )
    }
}
