import Dependencies
import GRDB
import IssueReportingTestSupport
import UIKit
import XCTest
import WalletContext
import WalletResources
@testable import UIAssets
@testable import WalletCore

@MainActor
final class HomeWalletTokenReuseTests: XCTestCase {
    private let accountIDs = ["810001-mainnet", "810002-mainnet", "810003-mainnet", "810004-mainnet"]

    private func prepareAccounts() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        AppStorageHelper.hideNoCostTokens = false
        AppStorageHelper.homeWalletVisibleTokensLimit = .top30
        for (accountIndex, id) in accountIDs.enumerated() {
            BalancesStore.for(accountId: id).replace(chain: .ton, balances: Dictionary(
                uniqueKeysWithValues: (0..<30).map { ("ton-reuse-fixture-\($0)", BigInt((accountIndex + 1) * 1000 + $0)) }
            ))
            withDependencies { $0.context = .live } operation: {
                BalanceDataStore.walletCore(event: .rawBalancesChanged(accountId: id))
            }
        }
        for _ in 0..<100 where accountIDs.contains(where: {
            (BalanceDataStore.walletTokensData(accountId: $0)?.orderedTokenBalances.count ?? 0) < 30
        }) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    override func tearDown() async throws {
        for id in accountIDs {
            BalancesStore.for(accountId: id).replaceAll(byChain: [:])
        }
        await BalanceDataStore.clean()
        SettingsStore.liveValue.clean()
        try await super.tearDown()
    }

    func testReorderingAndReconfiguringTokensKeepsTheirRegistration() async throws {
        try await prepareAccounts()
        let provider = makeProvider()
        let fixture = Fixture(provider: provider)
        let identifiers = Array(provider.itemIdentifiers.prefix(30))
        XCTAssertEqual(identifiers.count, 30)
        await fixture.apply(identifiers)
        fixture.collection.layoutIfNeeded()
        let originalCell = try XCTUnwrap(fixture.source.indexPath(for: identifiers[0]).flatMap {
            fixture.collection.cellForItem(at: $0)
        })
        var reordered = identifiers
        reordered.swapAt(0, 1)
        await fixture.apply(reordered, reconfigure: true)
        fixture.collection.layoutIfNeeded()
        XCTAssertTrue(fixture.collection.cellForItem(at: IndexPath(item: 1, section: 0)) === originalCell)
        try fixture.assertContent()
    }

    func testOutgoingSnapshotCanStillConfigureCellsAfterAccountChanges() async throws {
        try await prepareAccounts()
        let provider = makeProvider()
        let fixture = Fixture(provider: provider)
        let oldItems = provider.itemIdentifiers
        await fixture.apply(oldItems)
        provider.switchAccountTo(accountIDs[1])
        // UIKit may reconfigure or prefetch the displayed snapshot before the queued replacement applies.
        await fixture.apply(oldItems, reconfigure: true)
        try fixture.assertContent()
        await fixture.apply(provider.itemIdentifiers)
        try fixture.assertContent()
    }

    func testLongListsSurviveAccountSwitchesScrollingAndLimitChanges() async throws {
        try await prepareAccounts()
        let provider = makeProvider()
        let fixture = Fixture(provider: provider, visible: true)
        defer { fixture.window?.isHidden = true }
        for limit in [HomeWalletVisibleTokensLimit.top5, .top10, .top30, .top5] {
            AppStorageHelper.homeWalletVisibleTokensLimit = limit
            provider.walletCore(event: .homeWalletVisibleTokensLimitChanged)
            for account in accountIDs + accountIDs.reversed() {
                provider.switchAccountTo(account)
                await fixture.apply(provider.itemIdentifiers)
                XCTAssertEqual(provider.itemIdentifiers.count, limit.rawValue + 1)
                for offset in [max(0, fixture.collection.contentSize.height - fixture.collection.bounds.height), 0] {
                    fixture.collection.contentOffset.y = offset
                    fixture.collection.layoutIfNeeded()
                    try fixture.assertContent()
                }
            }
        }
    }

    func testOutgoingRowsCanBePreparedAfterTheViewCacheIsDiscarded() async throws {
        try await prepareAccounts()
        let provider = makeProvider()
        let identifiers = provider.itemIdentifiers
        provider.switchAccountTo(accountIDs[1])
        provider.discardPreparedContent()
        let fixture = Fixture(provider: provider)
        await fixture.apply(identifiers)
        try fixture.assertContent()
    }

    func testAccountBalancesStayCorrectWhenNeighborPreloadingEvictsEarlierAccounts() async throws {
        try await prepareAccounts()
        let provider = makeProvider()
        let fixture = Fixture(provider: provider, visible: true)
        defer { fixture.window?.isHidden = true }
        for account in accountIDs + accountIDs.reversed() {
            provider.switchAccountTo(account)
            await fixture.apply(provider.itemIdentifiers)
            withDependencies { $0.context = .live } operation: {
                provider.preloadAccounts(accountIDs.filter { $0 != account }, rowWidth: 360, visibleRowCount: 5)
            }
            try await Task.sleep(for: .milliseconds(650))
            await fixture.apply(provider.itemIdentifiers, reconfigure: true)
            try fixture.assertContent()
        }
    }

    func testPreparedContentDoesNotLeaveAnOffscreenCellBlank() async throws {
        try await prepareAccounts()
        let provider = makeProvider()
        let first = Fixture(provider: provider)
        let second = Fixture(provider: provider)
        await first.apply(provider.itemIdentifiers)
        first.collection.layoutIfNeeded()
        let cell = try XCTUnwrap(first.collection.visibleCells.compactMap { $0 as? WalletTokenCell }.first)
        let content = try XCTUnwrap(cell.contentView.subviews.first { $0 is WalletTokenContentView })
        XCTAssertNil(cell.window)
        await second.apply(provider.itemIdentifiers)
        second.collection.layoutIfNeeded()
        XCTAssertTrue(content.superview === cell.contentView, "Detached/prefetched cells still own their content")
        await first.apply(provider.itemIdentifiers, reconfigure: true)
        XCTAssertTrue(cell.tokenContent === content, "A retained cell must reuse its own content even if the cache holds another instance")
        try first.assertContent()
        try second.assertContent()
    }

    private func makeProvider() -> HomeWalletTokensSectionDataProvider {
        withDependencies { $0.context = .live } operation: {
            HomeWalletTokensSectionDataProvider(accountSource: .accountId(accountIDs[0]))
        }
    }

    @MainActor private final class Fixture {
        let collection: UICollectionView
        let source: UICollectionViewDiffableDataSource<Int, String>
        let window: UIWindow?

        init(provider: HomeWalletTokensSectionDataProvider, visible: Bool = false) {
            provider.prepareForUse()
            let layout = UICollectionViewFlowLayout()
            layout.itemSize = CGSize(width: 360, height: 60)
            layout.minimumLineSpacing = 0
            collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 400, height: 640), collectionViewLayout: layout)
            source = UICollectionViewDiffableDataSource(collectionView: collection) { collection, path, identifier in
                withDependencies { $0.context = .live } operation: {
                    provider.dequeueCell(collection, path, itemIdentifier: identifier)
                }
            }
            if visible {
                let window = UIWindow(frame: collection.frame)
                let root = UIViewController()
                window.rootViewController = root
                root.view.addSubview(collection)
                window.makeKeyAndVisible()
                self.window = window
            } else {
                window = nil
            }
        }

        func apply(_ identifiers: [String], reconfigure: Bool = false) async {
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(identifiers)
            if reconfigure { snapshot.reconfigureItems(identifiers) }
            await source.apply(snapshot, animatingDifferences: true)
            collection.layoutIfNeeded()
        }

        func assertContent(file: StaticString = #filePath, line: UInt = #line) throws {
            let cells = collection.visibleCells.compactMap { $0 as? WalletTokenCell }
            XCTAssertFalse(cells.isEmpty, file: file, line: line)
            for cell in cells {
                let path = try XCTUnwrap(collection.indexPath(for: cell), file: file, line: line)
                let identifier = try XCTUnwrap(source.itemIdentifier(for: path), file: file, line: line)
                let token = try XCTUnwrap(cell.walletToken, identifier, file: file, line: line)
                XCTAssertTrue(identifier.hasSuffix(":" + token.tokenSlug), file: file, line: line)
                XCTAssertEqual(cell.tokenContent?.preparedItemIdentifier, identifier, file: file, line: line)
                let accountId = String(identifier.split(separator: ":")[1])
                let expectedBalance = BalancesStore.getAccountBalances(accountId: accountId)[token.tokenSlug] ?? 0
                XCTAssertEqual(token.balance, expectedBalance, "Wrong account balance: \(identifier)", file: file, line: line)
                XCTAssertEqual(cell.contentView.subviews.filter { $0 is WalletTokenContentView }.count, 1, file: file, line: line)
            }
        }
    }
}
