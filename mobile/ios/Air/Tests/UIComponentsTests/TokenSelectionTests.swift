import Dependencies
import XCTest
import IssueReportingTestSupport
import UIKit
import WalletCore
import WalletContext
import WalletResources
@testable import UIComponents

@MainActor
final class TokenSelectionTests: XCTestCase {
    func testDisabledAssetRemainsVisibleAndCannotBeSelected() throws {
        try checkSelection(isDisabled: true, query: "")
        try checkSelection(isDisabled: true, query: "USDC")
    }

    func testPickerWithoutDisabledAssetAllowsBothChains() throws {
        try checkSelection(isDisabled: false, query: "")
        try checkSelection(isDisabled: false, query: "USDC")
    }

    func testCategoriesRequireStablecoinsAndOtherTokens() {
        let stablecoin = ETH_USDC_MAINNET_SLUG
        let token = ApiChain.ethereum.nativeToken.slug
        XCTAssertEqual(TokenPickerCategory.getAvailableCategories(tokenSlugs: []), [.all])
        XCTAssertEqual(TokenPickerCategory.getAvailableCategories(tokenSlugs: [stablecoin], hasFiat: true), [.all])
        XCTAssertEqual(TokenPickerCategory.getAvailableCategories(tokenSlugs: [token], hasFiat: true), [.all])
        XCTAssertEqual(TokenPickerCategory.getAvailableCategories(tokenSlugs: [stablecoin, token]), [.all, .stablecoins, .tokens])
        XCTAssertEqual(TokenPickerCategory.getAvailableCategories(tokenSlugs: [stablecoin, token], hasFiat: true), [.all, .fiat, .stablecoins, .tokens])
    }

    func testPagesFilterIndependentlyAndKeepSearchWhenSwipingToFiat() throws {
        try withDependencies { $0.context = .live } operation: {
            _ = WalletResourcesBundle.bundle.load()
            var didSelectFiat = false
            let picker = TokenSelectionVC(
                extraWalletTokenSlugs: [ETH_USDC_MAINNET_SLUG, ApiChain.ethereum.nativeToken.slug],
                showOnlyMyAssets: true,
                title: "Tokens",
                delegate: nil,
                isModal: true,
                onlySupportedChains: false,
                fiatOptions: [.init(currency: .USD, subtitle: "Bank card", onSelect: { didSelectFiat = true })]
            )
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = picker
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            let content = try XCTUnwrap(picker.view.subviews.compactMap { $0 as? TokenPickerContentView }.first)
            let pager = try XCTUnwrap(content.subviews.compactMap { $0 as? WSegmentedController }.first)
            let collections = pager.viewControllers.compactMap { $0.scrollingView as? UICollectionView }
            XCTAssertEqual(content.categories, [.all, .fiat, .stablecoins, .tokens])
            XCTAssertEqual(collections.map(countItems), [3, 1, 1, 1])
            XCTAssertTrue(pager.scrollView.isScrollEnabled)

            let searchFrame = content.searchBar.frame
            pager.beginAdditionalPaging()
            pager.updateAdditionalPaging(translation: -pager.scrollView.bounds.width)
            pager.endAdditionalPaging(translation: -pager.scrollView.bounds.width, velocity: 0, cancelled: false)
            XCTAssertEqual(pager.model.selectedItem?.id, "fiat")
            XCTAssertEqual(content.searchBar.frame, searchFrame)
            collections[1].layoutIfNeeded()
            let fiatCell = try XCTUnwrap(collections[1].visibleCells.first as? TokenCell)
            fiatCell.tokenSelected()
            XCTAssertTrue(didSelectFiat)

            content.searchBar.text = "USDC"
            content.searchBar.delegate?.searchBar?(content.searchBar, textDidChange: "USDC")
            XCTAssertEqual(content.categories, [.all, .fiat, .stablecoins, .tokens])
            XCTAssertEqual(collections.map(countItems), [1, 0, 1, 0])
            pager.setSelectedIndex(to: 2, animated: false)
            XCTAssertEqual(content.searchBar.text, "USDC")
            XCTAssertEqual(pager.model.selectedItem?.id, "stablecoins")

            content.updateCategories([.all])
            XCTAssertEqual(pager.model.selectedItem?.id, "all")
            XCTAssertFalse(pager.scrollView.isScrollEnabled)
        }
    }

    func testPushedPickerRegistersPagingBeforeBackNavigation() throws {
        try withDependencies { $0.context = .live } operation: {
            _ = WalletResourcesBundle.bundle.load()
            for shouldPreloadView in [false, true] {
                let picker = TokenSelectionVC(
                    extraWalletTokenSlugs: [ETH_USDC_MAINNET_SLUG, ApiChain.ethereum.nativeToken.slug],
                    showOnlyMyAssets: true,
                    title: "Add Token",
                    delegate: nil,
                    isModal: false,
                    onlySupportedChains: false
                )
                if shouldPreloadView { picker.loadViewIfNeeded() }
                let navigationController = WNavigationController(rootViewController: UIViewController())
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
                window.rootViewController = navigationController
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                navigationController.pushViewController(picker, animated: false)
                window.layoutIfNeeded()

                let content = try XCTUnwrap(picker.view.subviews.compactMap { $0 as? TokenPickerContentView }.first)
                let pager = try XCTUnwrap(content.subviews.compactMap { $0 as? WSegmentedController }.first)
                let backVelocity = CGPoint(x: 300, y: 0)
                pager.setSelectedIndex(to: 2, animated: false)
                XCTAssertFalse(pager.shouldYieldToBackNavigation(velocity: backVelocity))
                pager.setSelectedIndex(to: 0, animated: false)
                XCTAssertTrue(pager.shouldYieldToBackNavigation(velocity: backVelocity))

                content.updateCategories([.all])
                XCTAssertFalse(pager.scrollView.isScrollEnabled)
                content.updateCategories([.all, .stablecoins, .tokens])
                window.layoutIfNeeded()
                XCTAssertTrue(pager.shouldYieldToBackNavigation(velocity: backVelocity))
            }
        }
    }

    private func checkSelection(isDisabled: Bool, query: String) throws {
        try withDependencies { $0.context = .live } operation: {
            _ = WalletResourcesBundle.bundle.load()
            let delegate = SelectionDelegate()
            let picker = TokenSelectionVC(
                forceAvailable: SOLANA_USDC_MAINNET_SLUG,
                disabledTokenSlug: isDisabled ? SOLANA_USDC_MAINNET_SLUG : nil,
                extraWalletTokenSlugs: [SOLANA_USDC_MAINNET_SLUG, ETH_USDC_MAINNET_SLUG],
                showOnlyMyAssets: true,
                title: "Tokens",
                delegate: delegate,
                isModal: true,
                onlySupportedChains: false
            )
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = picker
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            let content = try XCTUnwrap(picker.view.subviews.compactMap { $0 as? TokenPickerContentView }.first)
            let searchBar = content.searchBar
            searchBar.text = query
            searchBar.delegate?.searchBar?(searchBar, textDidChange: query)
            picker.view.layoutIfNeeded()
            let pager = try XCTUnwrap(content.subviews.compactMap { $0 as? WSegmentedController }.first)
            let collection = try XCTUnwrap(pager.viewControllers.first?.scrollingView as? UICollectionView)
            collection.layoutIfNeeded()
            let cells = collection.visibleCells.compactMap { $0 as? TokenCell }
            XCTAssertEqual(cells.count, 2)
            XCTAssertEqual(cells.filter { visibleLabels(in: $0).contains { $0.text == lang("Unavailable") } }.count, isDisabled ? 1 : 0)
            for cell in cells { cell.tokenSelected() }
            XCTAssertTrue(delegate.selectedSlugs.contains(ETH_USDC_MAINNET_SLUG))
            XCTAssertEqual(delegate.selectedSlugs.contains(SOLANA_USDC_MAINNET_SLUG), !isDisabled)
            XCTAssertEqual(delegate.selectedSlugs.count, isDisabled ? 1 : 2)
        }
    }

    private func countItems(in collectionView: UICollectionView) -> Int {
        (0..<collectionView.numberOfSections).reduce(0) { $0 + collectionView.numberOfItems(inSection: $1) }
    }

    private func visibleLabels(in view: UIView) -> [UILabel] {
        guard !view.isHidden else { return [] }
        return (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { visibleLabels(in: $0) }
    }
}

@MainActor private final class SelectionDelegate: TokenSelectionVCDelegate {
    var selectedSlugs: [String] = []

    func didSelect(token: MTokenBalance) { selectedSlugs.append(token.tokenSlug) }
    func didSelect(token: ApiToken) { selectedSlugs.append(token.slug) }
}
