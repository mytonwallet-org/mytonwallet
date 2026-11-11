import Dependencies
import XCTest
import UIKit
import IssueReportingTestSupport
@testable import UIComponents
import WalletCore
import WalletContext
import WalletResources
@testable import UISend

@MainActor
final class TokenPickerTests: XCTestCase {
    func testSendCategoriesPreserveHiddenSearchAndSelection() throws {
        try withDependencies { $0.context = .live } operation: {
            _ = WalletResourcesBundle.bundle.load()
            let nativeSlug = ApiChain.ethereum.nativeToken.slug
            let visible = [nativeSlug, ETH_USDC_MAINNET_SLUG].map {
                MTokenBalance(tokenSlug: $0, balance: 1_000_000, isStaking: false)
            }
            let hidden = MTokenBalance(tokenSlug: SOLANA_USDC_MAINNET_SLUG, balance: 1_000_000, isStaking: false)
            var selectedSlugs: [String] = []
            let picker = TokenPickerViewController(
                accountId: "token-picker-test",
                isMultichain: true,
                presentation: .init(visible: visible, hidden: [hidden]),
                currentTokenSlug: nativeSlug,
                onSelect: { selectedSlugs.append($0.slug) }
            )
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = picker
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            let content = try XCTUnwrap(picker.view.subviews.compactMap { $0 as? TokenPickerContentView }.first)
            let pager = try XCTUnwrap(content.subviews.compactMap { $0 as? WSegmentedController }.first)
            let collections = pager.viewControllers.compactMap { $0.scrollingView as? UICollectionView }
            XCTAssertEqual(content.categories, [.all, .stablecoins, .tokens])
            XCTAssertEqual(collections.map(countItems), [2, 1, 1])

            content.searchBar.text = "USDC"
            content.searchBar.delegate?.searchBar?(content.searchBar, textDidChange: "USDC")
            XCTAssertEqual(content.categories, [.all, .stablecoins, .tokens])
            XCTAssertEqual(collections.map(countItems), [2, 2, 0])
            pager.setSelectedIndex(to: 1, animated: false)
            picker.view.layoutIfNeeded()
            collections[1].layoutIfNeeded()
            let hiddenCell = try XCTUnwrap(collections[1].cellForItem(at: IndexPath(item: 0, section: 1)) as? TokenCell)
            hiddenCell.tokenSelected()
            XCTAssertEqual(selectedSlugs, [SOLANA_USDC_MAINNET_SLUG])

            content.searchBar.delegate?.searchBarCancelButtonClicked?(content.searchBar)
            XCTAssertEqual(collections.map(countItems), [2, 1, 1])
            XCTAssertEqual(pager.model.selectedItem?.id, "stablecoins")
        }
    }

    private func countItems(in collectionView: UICollectionView) -> Int {
        (0..<collectionView.numberOfSections).reduce(0) { $0 + collectionView.numberOfItems(inSection: $1) }
    }
}
