import Dependencies
import GRDB
import IssueReportingTestSupport
import UIKit
import Testing
import UIActivityList
import WalletContext
import WalletResources
@testable import UIToken
@testable import WalletCore

@MainActor
@Suite("Token Background Updates", .serialized, .settingsStoreIsolation)
struct TokenBackgroundUpdateTests {
    private static var hasPreparedPrivacyDependency = false

    @Test
    func testPreloadedToolbarActionsStillConfigureTheReceiveButton() async throws {
        try await withFixture(beforeLoad: { controller in
            #expect(!controller.isViewLoaded)
            controller.setSharedBottomToolbarHosted(true)
            controller.setSharedBottomToolbarHosted(false)
            #expect(!controller.isViewLoaded)
        }) { controller in
            func buttonTitles(in view: UIView) -> [String] {
                guard !view.isHidden else { return [] }
                let title = (view as? UIButton)?.title(for: .normal)
                return (title.map { [$0] } ?? []) + view.subviews.flatMap { buttonTitles(in: $0) }
            }
            let titles = buttonTitles(in: controller.view)
            #expect(titles.suffix(2) == [lang("Receive"), lang("Buy")])
            #expect(!titles.contains(lang("Sell")))
            #expect(controller.sharedBottomToolbarActions.map(\.style) == [.neutral, .positive])
        }
    }

    @Test
    func testRepeatedBackgroundEventsDoNotApplySnapshotsOrResetScrollGeometry() async throws {
        try await withFixture { controller in
            let collection = controller.collectionView
            collection.contentInset.bottom += 100
            collection.contentOffset.y = -collection.adjustedContentInset.top - 50
            collection.layoutIfNeeded()
            let offset = collection.contentOffset
            let inset = collection.contentInset
            let originalCells = collection.visibleCells
            let configurationCount = controller.configurationCount
            let applyCount = controller.snapshots.count
            let menu = controller.navigationItem.rightBarButtonItem
            var toolbarUpdates = 0
            controller.onSharedBottomToolbarActionsChange = { toolbarUpdates += 1 }

            for _ in 0..<10 {
                controller.dataUpdated()
                controller.priceDataUpdated()
                controller.activityViewModelChanged()
                controller.walletCore(event: .configChanged)
                controller.viewSafeAreaInsetsDidChange()
            }
            try await Task.sleep(for: .milliseconds(100))
            collection.layoutIfNeeded()

            #expect(controller.snapshots.count == applyCount)
            #expect(controller.configurationCount == configurationCount)
            #expect(collection.contentInset == inset)
            #expect(collection.contentOffset == offset)
            #expect(Set(collection.visibleCells) == Set(originalCells))
            #expect(controller.navigationItem.rightBarButtonItem === menu)
            #expect(toolbarUpdates == 0)
        }
    }

    @Test(arguments: [false, true])
    func testActivityChangesDoNotReconfigureTokenSections(hasBalance: Bool) async throws {
        try await withFixture(balance: hasBalance ? 1_000_000_000 : 0) { controller in
            let model = try #require(controller.activityViewModel)
            let accountId = model.accountId
            let section = ActivityListViewModel.Section.transactions(accountId, Date(timeIntervalSince1970: 0))
            let row = ActivityListViewModel.Row.transaction(accountId, "new")
            let activity = try JSONDecoder().decode(ApiActivity.self, from: Data("""
                {"kind":"transaction","id":"new","timestamp":1000,"amount":"1000000000",
                "fromAddress":"from","toAddress":"to","fee":"0","slug":"toncoin","isIncoming":true,"status":"confirmed"}
                """.utf8))
            model.activitiesById = ["new": activity]
            var snapshot = try #require(model.snapshot)
            snapshot.deleteSections([.emptyPlaceholder])
            snapshot.appendSections([section])
            snapshot.appendItems([row], toSection: section)
            model.snapshot = snapshot
            let applyCount = controller.snapshots.count
            controller.activityViewModelChanged()
            #expect(controller.snapshots.count == applyCount + 1)
            #expect(try #require(controller.snapshots.last).reconfiguredItemIdentifiers.isEmpty)
            #expect(controller.displaysActivitySections)
            #expect(controller.snapshots.last?.itemIdentifiers.contains(row) == true)

            snapshot.reconfigureItems([row])
            model.snapshot = snapshot
            controller.activityViewModelChanged()
            #expect(controller.snapshots.count == applyCount + 2)
            #expect(controller.snapshots.last?.reconfiguredItemIdentifiers == [row])
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test
    func testZeroBalanceHidesEmptyAndLoadingStatesButRevealsLoadedTransactions() async throws {
        try await withFixture { controller in
            let model = try #require(controller.activityViewModel)
            let chart = controller.visibleCustomSectionCell(id: "chart")
            let applyCount = controller.snapshots.count
            var snapshot = try #require(model.snapshot)
            snapshot.deleteSections([.emptyPlaceholder])
            snapshot.appendSections([.loadingPlaceholder])
            snapshot.appendItems([.loadingMore], toSection: .loadingPlaceholder)
            snapshot.reconfigureItems([.loadingMore])
            model.idsByDate = nil
            model.isEndReached = nil
            model.snapshot = snapshot
            controller.activityViewModelChanged()
            #expect(controller.snapshots.count == applyCount)
            #expect(controller.skeletonState == .loadedAll)
            #expect(!controller.displaysActivitySections)

            let activity = try makeHistoricalActivity()
            let section = ActivityListViewModel.Section.transactions(model.accountId, activity.timestampDate)
            let row = ActivityListViewModel.Row.transaction(model.accountId, activity.id)
            model.activitiesById = [activity.id: activity]
            model.isEndReached = false
            snapshot.insertSections([section], beforeSection: .loadingPlaceholder)
            snapshot.appendItems([row], toSection: section)
            model.snapshot = snapshot
            controller.activityViewModelChanged()
            #expect(controller.snapshots.count == applyCount + 1)
            #expect(controller.snapshots.last?.itemIdentifiers.contains(row) == true)
            #expect(controller.snapshots.last?.sectionIdentifiers.contains(.loadingPlaceholder) == false)
            #expect(controller.snapshots.last?.itemIdentifiers.contains(.loadingMore) == false)
            #expect(controller.skeletonState == .loadedAll)
            #expect(controller.sharedBottomToolbarActions.map(\.id) == ["token.receive", "token.buy"])
            #expect(controller.visibleCustomSectionCell(id: "chart") === chart)

            snapshot.deleteSections([section, .loadingPlaceholder])
            snapshot.appendSections([.emptyPlaceholder])
            snapshot.appendItems([.emptyPlaceholder], toSection: .emptyPlaceholder)
            model.snapshot = snapshot
            model.activitiesById = [:]
            model.isEndReached = true
            controller.activityViewModelChanged()
            #expect(!controller.displaysActivitySections)
            #expect(controller.snapshots.last?.sectionIdentifiers.contains(.emptyPlaceholder) == false)
            #expect(controller.skeletonState == .loadedAll)
        }
    }

    @Test
    func testCachedHistoryRemainsVisibleWhenTheBalanceReachesZero() async throws {
        let activity = try makeHistoricalActivity()
        try await withFixture(activities: [activity]) { controller in
            let accountId = try #require(controller.activityViewModel).accountId
            let row = ActivityListViewModel.Row.transaction(accountId, activity.id)
            #expect(controller.displaysActivitySections)
            #expect(controller.snapshots.last?.itemIdentifiers.contains(row) == true)
            #expect(controller.headerPlaceholderHeight == 8)

            BalancesStore.for(accountId: accountId).replace(chain: .ton, balances: [TONCOIN_SLUG: 1_000_000_000])
            controller.dataUpdated()
            BalancesStore.for(accountId: accountId).replace(chain: .ton, balances: [TONCOIN_SLUG: 0])
            controller.dataUpdated()
            #expect(controller.displaysActivitySections)
            #expect(controller.snapshots.last?.itemIdentifiers.contains(row) == true)
            #expect(controller.snapshots.last?.sectionIdentifiers.contains(.emptyPlaceholder) == false)
            #expect(controller.activeCustomSectionIDs == ["chart", "info"])
            #expect(controller.headerPlaceholderHeight == 8)
        }
    }

    @Test
    func testOwnershipChangesSwitchLayoutAndActionsWhileKeepingTheChart() async throws {
        try await withFixture { controller in
            let accountId = try #require(controller.activityViewModel).accountId
            defer { BalancesStore.for(accountId: accountId).replaceAll(byChain: [:]) }
            let applyCount = controller.snapshots.count
            let chart = controller.visibleCustomSectionCell(id: "chart")
            #expect(controller.sharedBottomToolbarActions.map(\.id) == ["token.receive", "token.buy"])
            #expect(controller.activeCustomSectionIDs == ["chart", "info"])
            #expect(!controller.displaysActivitySections)
            #expect(controller.headerPlaceholderHeight == 8)
            #expect(controller.snapshots.last?.sectionIdentifiers.contains(.emptyPlaceholder) == false)
            var toolbarUpdates = 0
            controller.onSharedBottomToolbarActionsChange = { toolbarUpdates += 1 }

            BalancesStore.for(accountId: accountId).replace(chain: .ton, balances: [TONCOIN_SLUG: 1_000_000_000])
            controller.dataUpdated()
            try await Task.sleep(for: .milliseconds(100))
            #expect(controller.sharedBottomToolbarActions.map(\.id) == ["token.buy", "token.sell"])
            #expect(toolbarUpdates == 1)
            #expect(controller.activeCustomSectionIDs == ["actions", "chart", "info"])
            #expect(controller.displaysActivitySections)
            #expect(controller.headerPlaceholderHeight == 164)
            #expect(controller.visibleCustomSectionCell(id: "chart") === chart)
            controller.dataUpdated()
            #expect(toolbarUpdates == 1)
            #expect(controller.snapshots.count == applyCount + 1)

            BalancesStore.for(accountId: accountId).replace(chain: .ton, balances: [TONCOIN_SLUG: 0])
            controller.dataUpdated()
            try await Task.sleep(for: .milliseconds(100))
            #expect(controller.sharedBottomToolbarActions.map(\.id) == ["token.receive", "token.buy"])
            #expect(controller.activeCustomSectionIDs == ["chart", "info"])
            #expect(!controller.displaysActivitySections)
            #expect(controller.snapshots.count == applyCount + 2)
            #expect(controller.visibleCustomSectionCell(id: "chart") === chart)
            #expect(controller.snapshots.last?.sectionIdentifiers.contains(.emptyPlaceholder) == false)
        }
    }

    @Test
    func testVisibleOwnershipTransitionAnimatesTheExistingChart() async throws {
        try await withFixture(visible: true) { controller in
            #expect(controller.shouldAnimateContentUpdates)
            let chart = try #require(controller.visibleCustomSectionCell(id: "chart"))
            let accountId = try #require(controller.activityViewModel).accountId
            let initialY = chart.frame.minY

            BalancesStore.for(accountId: accountId).replace(chain: .ton, balances: [TONCOIN_SLUG: 1_000_000_000])
            controller.dataUpdated()
            // Sample the chart's presentation until it has left its start, counting 16 ms samples rather than wall
            // time, so a busy machine that delays the animation's first frames does not read the start as the middle.
            var intermediateY = initialY
            for _ in 0..<40 {
                try await Task.sleep(for: .milliseconds(16))
                intermediateY = try #require(chart.layer.presentation()).frame.minY
                if intermediateY > initialY + 1 { break }
            }
            try await Task.sleep(for: .milliseconds(500))
            let finalY = chart.frame.minY
            #expect(intermediateY > initialY + 1)
            #expect(intermediateY < finalY - 1)
            #expect(controller.visibleCustomSectionCell(id: "chart") === chart)

            BalancesStore.for(accountId: accountId).replace(chain: .ton, balances: [TONCOIN_SLUG: 0])
            controller.dataUpdated()
            try await Task.sleep(for: .milliseconds(600))
            #expect(abs(chart.frame.minY - initialY) < 1)
            #expect(controller.visibleCustomSectionCell(id: "chart") === chart)
        }
    }

    private func makeHistoricalActivity() throws -> ApiActivity {
        try JSONDecoder().decode(ApiActivity.self, from: Data("""
            {"kind":"transaction","id":"historical","timestamp":1000,"amount":"-1000000000",
            "fromAddress":"from","toAddress":"to","fee":"0","slug":"toncoin","isIncoming":false,"status":"confirmed"}
            """.utf8))
    }

    private func withFixture(balance: BigInt = 0, visible: Bool = false, activities: [ApiActivity] = [],
                             beforeLoad: @MainActor (TokenUpdateTestController) -> Void = { _ in },
                             _ body: @MainActor (TokenUpdateTestController) async throws -> Void) async throws {
        if !Self.hasPreparedPrivacyDependency {
            // UIKit renders outside Swift Testing's task-local dependency cache.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    prepareDependencies {
                        $0.sensitiveData = SensitiveData.liveValue
                        $0[_TokenStore.self] = _TokenStore.liveValue
                    }
                    continuation.resume()
                }
            }
            Self.hasPreparedPrivacyDependency = true
        }
        _ = WalletResourcesBundle.bundle.load()
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let account = MAccount(id: UUID().uuidString + "-mainnet", title: "Token updates", type: .mnemonic,
                               byChain: ["ton": AccountChain(address: "test")])
        try await db.write { db in
            try account.insert(db)
            let activityIds = activities.map(\.id)
            try _ActivityStore.AccountState(accountId: account.id, byId: Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) }), idsMain: activityIds,
                idsBySlug: [TONCOIN_SLUG: activityIds], isMainHistoryEndReached: true,
                isHistoryEndReachedBySlug: [TONCOIN_SLUG: true]).insert(db)
        }
        SettingsStore.liveValue.use(db: db)
        defer { SettingsStore.liveValue.clean() }
        await _ActivityStore.shared.use(db: db)
        BalancesStore.for(accountId: account.id).replace(chain: .ton, balances: [TONCOIN_SLUG: balance])
        defer { BalancesStore.for(accountId: account.id).replaceAll(byChain: [:]) }
        try await withDependencies {
            $0.context = .live
            $0.accountStore = _AccountStore(db: db)
        } operation: {
            let controller = await TokenUpdateTestController(accountSource: .constant(account), token: .TONCOIN, isInModal: false)
            beforeLoad(controller)
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            let window = visible ? UIWindow(frame: controller.view.frame) : nil
            window?.rootViewController = UINavigationController(rootViewController: controller)
            window?.isHidden = false
            defer { window?.isHidden = true }
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            controller.collectionView.layoutIfNeeded()
            #expect(controller.visibleCustomSectionCell(id: "chart") != nil)
            try await body(controller)
        }
    }
}

@MainActor
private final class TokenUpdateTestController: TokenVC {
    var snapshots: [NSDiffableDataSourceSnapshot<Section, Row>] = []
    var configurationCount = 0

    override func viewWillAppear(_ animated: Bool) {
        // The fixture supplies balances and history without starting SDK requests.
    }

    override var customSections: [any CustomSectionDataProvider] {
        super.customSections.map { provider in
            CountingSection(provider: provider) { [weak self] in self?.configurationCount += 1 }
        }
    }

    override func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animatingDifferences: Bool = true) {
        snapshots.append(snapshot)
        super.applySnapshot(snapshot, animatingDifferences: animatingDifferences)
    }
}

@MainActor
private struct CountingSection: ActivityListViewController.CustomSectionDataProvider {
    let provider: any ActivityListViewController.CustomSectionDataProvider
    let onConfigure: () -> Void
    var id: String { provider.id }
    var itemIdentifiers: [String] { provider.itemIdentifiers }

    func makeLayoutSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        provider.makeLayoutSection(layoutEnvironment: layoutEnvironment)
    }

    func dequeueCell(_ collectionView: UICollectionView, _ indexPath: IndexPath, itemIdentifier: String) -> UICollectionViewCell {
        onConfigure()
        return provider.dequeueCell(collectionView, indexPath, itemIdentifier: itemIdentifier)
    }
}
