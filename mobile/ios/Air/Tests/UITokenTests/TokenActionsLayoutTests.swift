import Dependencies
import UIKit
import XCTest
import WalletContext
import WalletCore
import WalletResources
@testable import UIToken

@MainActor
final class TokenActionsLayoutTests: XCTestCase {
    func testActionRowFitsAndCompressesWithoutConflictingHeights() async throws {
        _ = WalletResourcesBundle.bundle.load()
        try await withDependencies { $0.context = .live } operation: {
            let account = MAccount(id: "layout-mainnet", title: "Layout", type: .mnemonic,
                                   byChain: [.ton: AccountChain(address: "fixture")])
            let context = AccountContext(source: .constant(account))
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(300))
            let layout = UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: .vertical(
                layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]
            )))
            let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), collectionViewLayout: layout)
            let root = UIViewController()
            let window = UIWindow(frame: collection.bounds)
            window.rootViewController = root
            root.view.addSubview(collection)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let registration = UICollectionView.CellRegistration<TokenActionsCell, Int> { cell, _, _ in
                cell.setup(accountContext: context, token: .TONCOIN)
                cell.configure(token: .TONCOIN, sendAvailable: true, swapAvailable: true, earnAvailable: true)
            }
            let source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collection) { collection, path, item in
                collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
            }
            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            snapshot.appendSections([0])
            snapshot.appendItems([0])
            await source.apply(snapshot, animatingDifferences: false)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let cell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? TokenActionsCell)
            let actions = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? TokenActionsView }.first)
            XCTAssertEqual(cell.bounds.height, actions.rowHeight + 16, accuracy: 0.5)
            XCTAssertEqual(cell.contentView.bounds.height, cell.bounds.height, accuracy: 0.5)
            XCTAssertEqual(actions.bounds.height, actions.rowHeight, accuracy: 0.5)

            for delta in [-20.0, -50, 0] {
                cell.reduceButtonHeightFor(delta)
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                XCTAssertEqual(actions.bounds.height, actions.rowHeight + delta, accuracy: 0.5)
                XCTAssertEqual(cell.bounds.height, actions.rowHeight + 16, accuracy: 0.5)
                for constraint in actions.constraints where constraint.isActive
                    && constraint.priority == .required && constraint.firstAttribute == .height
                    && constraint.firstItem === actions && constraint.secondItem == nil {
                    XCTAssertEqual(actions.bounds.height, constraint.constant, accuracy: 0.5,
                                   "The action height must satisfy every required height constraint")
                }
            }
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
