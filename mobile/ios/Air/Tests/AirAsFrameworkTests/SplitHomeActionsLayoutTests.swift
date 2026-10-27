import Dependencies
import UIKit
import XCTest
import UIComponents
import WalletContext
import WalletResources
@testable import WalletCore
@testable import AirAsFramework

@MainActor
final class SplitHomeActionsLayoutTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
        } operation: {
            super.invokeTest()
        }
    }

    override func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    func testMiniFitsSevenActionsAndRegularWindowKeepsDesignSize() {
        withMessageLanguage("en") {
            let traits = UITraitCollection(preferredContentSizeCategory: .large)
            let compact = SplitHomeActionsLayout(windowHeight: 744, traitCollection: traits)
            let regular = SplitHomeActionsLayout(windowHeight: 1024, traitCollection: traits)
            XCTAssertLessThanOrEqual(compact.itemSize.width * 7 + 16 * 6, 731)
            XCTAssertLessThan(compact.itemSize.height, regular.itemSize.height)
            XCTAssertEqual(compact.titleFont.pointSize, 14)
            XCTAssertEqual(regular.itemSize, CGSize(width: 96, height: 96))
            XCTAssertEqual(regular.titleFont.pointSize, 16)
            XCTAssertEqual(SplitHomeActionsLayout(windowHeight: 800, traitCollection: traits), compact)
            XCTAssertEqual(SplitHomeActionsLayout(windowHeight: 801, traitCollection: traits), regular)
        }
    }

    func testLocalizedTitlesFitAtEveryDynamicTypeSize() throws {
        let categories: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
            .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
            .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
        ]
        for language in Language.supportedLanguages {
            try withMessageLanguage(language.langCode) {
                for height: CGFloat in [744, 1024] {
                    for category in categories {
                        let layout = SplitHomeActionsLayout(
                            windowHeight: height,
                            traitCollection: UITraitCollection(preferredContentSizeCategory: category)
                        )
                        for item in SplitHomeActionItem.allCases {
                            let image = try XCTUnwrap(item.image)
                            XCTAssertEqual(image.size, CGSize(width: 32, height: 32))
                            let button = WActionTileButton(title: item.title, image: image)
                            button.semanticContentAttribute = language.isRtl ? .forceRightToLeft : .forceLeftToRight
                            button.titleLabel.font = layout.titleFont
                            NSLayoutConstraint.activate([
                                button.widthAnchor.constraint(equalToConstant: layout.itemSize.width),
                                button.heightAnchor.constraint(equalToConstant: layout.itemSize.height),
                            ])
                            button.layoutIfNeeded()
                            let fitting = button.titleLabel.sizeThatFits(CGSize(width: 10_000, height: 10_000))
                            let context = "\(language.langCode), \(item), \(height), \(category.rawValue), tile=\(button.bounds), title=\(button.titleLabel.frame), image=\(button.imageView.frame)"
                            XCTAssertGreaterThanOrEqual(button.titleLabel.bounds.width + 0.5, fitting.width, context)
                            XCTAssertGreaterThanOrEqual(button.bounds.width - fitting.width, 28, context)
                            XCTAssertGreaterThanOrEqual(button.titleLabel.bounds.height + 0.5, fitting.height, context)
                            XCTAssertGreaterThanOrEqual(button.titleLabel.frame.minY - button.imageView.frame.maxY, 8, context)
                        }
                    }
                }
            }
        }
    }

    func testResizingUpdatesRowCellsAndSectionHeight() async throws {
        let account = MAccount(
            id: "split-home-layout-mainnet", title: "Layout", type: .mnemonic,
            byChain: [.ton: .init(address: "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c")]
        )
        let context = AccountContext(source: .constant(account))
        let row = SplitHomeActionsRowView()
        row.configure(accountContext: context)
        let controller = UIViewController()
        controller.view.backgroundColor = .air.groupedBackground
        controller.view.addSubview(row)
        controller.view.frame = CGRect(x: 0, y: 0, width: 771, height: 240)
        let section = SplitHomeActionsSectionCell()
        let collection = try XCTUnwrap(row.subviews.first as? UICollectionView)

        for (height, category): (CGFloat, UIContentSizeCategory) in [
            (1024, .large), (744, .large), (550, .accessibilityExtraExtraExtraLarge), (1024, .large),
        ] {
            let layout = SplitHomeActionsLayout(
                windowHeight: height,
                traitCollection: UITraitCollection(preferredContentSizeCategory: category)
            )
            row.configure(layout: layout)
            section.configure(layout: layout)
            row.frame = CGRect(x: 20, y: 20, width: 731, height: layout.itemSize.height)
            row.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            collection.layoutIfNeeded()
            let flow = try XCTUnwrap(collection.collectionViewLayout as? UICollectionViewFlowLayout)
            XCTAssertEqual(flow.itemSize, layout.itemSize)
            XCTAssertFalse(collection.visibleCells.isEmpty)
            for cell in collection.visibleCells {
                let button = try XCTUnwrap(cell.contentView.subviews.first as? WActionTileButton)
                XCTAssertEqual(button.bounds.size, layout.itemSize)
                XCTAssertEqual(button.titleLabel.font, layout.titleFont)
            }
            let fitted = section.contentView.systemLayoutSizeFitting(
                CGSize(width: 731, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            XCTAssertEqual(fitted.height, layout.itemSize.height + SplitHomeActionsSectionCell.bottomSpacing)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 763, height: row.bounds.height + 32)).image { context in
                UIColor.systemGroupedBackground.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 763, height: row.bounds.height + 32))
                context.cgContext.translateBy(x: 16, y: 16)
                row.layer.render(in: context.cgContext)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Actions-\(Int(height))-\(category.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
