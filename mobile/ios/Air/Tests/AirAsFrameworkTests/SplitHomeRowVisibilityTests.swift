import Dependencies
import UIKit
import XCTest
import UIActivityList
import WalletResources
@testable import AirAsFramework

@MainActor
final class SplitHomeRowVisibilityTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
        } operation: {
            super.invokeTest()
        }
    }

    @available(iOS 17, *)
    func testRowsDisplayItemsInMarginsAndPreserveGroupedAlignmentWhenResized() async throws {
        _ = WalletResourcesBundle.bundle.load()
        for isRTL in [false, true] {
            let controller = UIViewController()
            controller.view.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
            controller.traitOverrides.layoutDirection = isRTL ? .rightToLeft : .leftToRight
            let actions = SplitHomeRowSection<SplitHomeActionsSectionCell>(id: "actions") {
                $0.configure(layout: SplitHomeActionsLayout(windowHeight: 744, traitCollection: controller.traitCollection))
            }
            let assets = SplitHomeRowSection<SplitHomeAssetsSectionCell>(id: "assets") { _ in }
            let referenceRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Int> { _, _, _ in }
            let reference = ActivityListViewController.CustomSectionDescriptor(id: "reference", usesInsetGroupedMargins: true) {
                $0.dequeueConfiguredReusableCell(using: referenceRegistration, for: $1, item: 0)
            }
            let providers: [any ActivityListViewController.CustomSectionDataProvider] = [actions, assets, reference]
            let layout = UICollectionViewCompositionalLayout { index, environment in
                providers[index].makeLayoutSection(layoutEnvironment: environment)
            }
            let outer = UICollectionView(frame: .zero, collectionViewLayout: layout)
            outer.semanticContentAttribute = controller.view.semanticContentAttribute
            controller.view.addSubview(outer)
            let source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: outer) { collection, indexPath, _ in
                providers[indexPath.section].dequeueCell(collection, indexPath, itemIdentifier: providers[indexPath.section].id)
            }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 1100))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            outer.frame = CGRect(x: 0, y: 0, width: 731, height: 1000)
            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            for index in providers.indices {
                snapshot.appendSections([index])
                snapshot.appendItems([index])
            }
            await source.apply(snapshot, animatingDifferences: false)
            try await settle(window)

            let rows = try [0, 1].map { index in
                let cell = try XCTUnwrap(outer.cellForItem(at: IndexPath(item: 0, section: index)))
                return try XCTUnwrap(nestedCollection(in: cell))
            }
            // Use enough items to exercise both pane edges independently of wallet contents.
            var rowSources: [UICollectionViewDiffableDataSource<Int, Int>] = []
            for row in rows {
                let registration = UICollectionView.CellRegistration<UICollectionViewCell, Int> { _, _, _ in }
                let rowSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: row) { collection, path, item in
                    collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
                }
                var items = NSDiffableDataSourceSnapshot<Int, Int>()
                items.appendSections([0])
                items.appendItems(Array(0..<20))
                await rowSource.apply(items, animatingDifferences: false)
                rowSources.append(rowSource)
            }

            for (width, left, right): (CGFloat, CGFloat, CGFloat) in [(731, 64, 4), (550, 4, 64), (900, 4, 4)] {
                controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: left, bottom: 0, right: right)
                outer.frame.size.width = width
                layout.invalidateLayout()
                try await settle(window)
                let referenceCell = try XCTUnwrap(outer.cellForItem(at: IndexPath(item: 0, section: 2)))
                let referenceOnScreen = referenceCell.convert(referenceCell.bounds, to: controller.view)

                for row in rows {
                    let viewport = row.convert(row.bounds, to: outer)
                    XCTAssertEqual(viewport.minX, outer.bounds.minX, accuracy: 0.5)
                    XCTAssertEqual(viewport.maxX, outer.bounds.maxX, accuracy: 0.5)
                    XCTAssertEqual(row.adjustedContentInset, row.contentInset)

                    row.scrollToItem(at: IndexPath(item: 0, section: 0), at: isRTL ? .right : .left, animated: false)
                    row.layoutIfNeeded()
                    let firstCell = try XCTUnwrap(row.cellForItem(at: IndexPath(item: 0, section: 0)))
                    let firstOnScreen = firstCell.convert(firstCell.bounds, to: controller.view)
                    if isRTL {
                        XCTAssertEqual(firstOnScreen.maxX, referenceOnScreen.maxX, accuracy: 0.5)
                    } else {
                        XCTAssertEqual(firstOnScreen.minX, referenceOnScreen.minX, accuracy: 0.5)
                    }
                }

                // Changing margins must preserve leading alignment without another scrollToItem.
                for (leftDelta, rightDelta): (CGFloat, CGFloat) in [(20, 20), (0, 30), (0, 0)] {
                    controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: left + leftDelta, bottom: 0, right: right + rightDelta)
                    layout.invalidateLayout()
                    try await settle(window)
                    let referenceOnScreen = referenceCell.convert(referenceCell.bounds, to: controller.view)
                    for row in rows {
                        let firstCell = try XCTUnwrap(row.cellForItem(at: IndexPath(item: 0, section: 0)))
                        let firstOnScreen = firstCell.convert(firstCell.bounds, to: controller.view)
                        if isRTL {
                            XCTAssertEqual(firstOnScreen.maxX, referenceOnScreen.maxX, accuracy: 0.5)
                        } else {
                            XCTAssertEqual(firstOnScreen.minX, referenceOnScreen.minX, accuracy: 0.5)
                        }
                    }
                }

                for row in rows {
                    let path = IndexPath(item: 5, section: 0)
                    let item = try XCTUnwrap(row.collectionViewLayout.layoutAttributesForItem(at: path))
                    // Only eight points of the incoming cell are on screen, entirely within the margin.
                    row.setContentOffset(CGPoint(x: item.frame.minX - width + 8, y: 0), animated: false)
                    row.layoutIfNeeded()
                    XCTAssertEqual(item.frame.intersection(row.bounds).width, 8, accuracy: 0.5)
                    XCTAssertNotNil(row.cellForItem(at: path), "Incoming cell must exist before it reaches the right margin")
                    row.setContentOffset(CGPoint(x: item.frame.maxX - 8, y: 0), animated: false)
                    row.layoutIfNeeded()
                    XCTAssertEqual(item.frame.intersection(row.bounds).width, 8, accuracy: 0.5)
                    XCTAssertNotNil(row.cellForItem(at: path), "Outgoing cell must remain while visible in the left margin")
                }
            }
            withExtendedLifetime(rowSources) { }
        }
    }

    private func nestedCollection(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { self.nestedCollection(in: $0) }.first
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
    }
}
