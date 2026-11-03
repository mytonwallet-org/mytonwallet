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
            picker.loadViewIfNeeded()
            picker.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            let search = UISearchController()
            search.searchBar.text = query
            picker.updateSearchResults(for: search)
            picker.view.layoutIfNeeded()
            let collection = try XCTUnwrap(picker.view.subviews.compactMap { $0 as? UICollectionView }.first)
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
