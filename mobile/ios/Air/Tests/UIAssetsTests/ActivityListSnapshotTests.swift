import UIActivityList
import UIKit
import XCTest

@MainActor
final class ActivityListSnapshotTests: XCTestCase {
    func testReentrantSectionUpdateDuringAccountReplacementCannotRestoreOutgoingRows() async throws {
        let controller = try await makeController()
        let window = UIWindow(frame: controller.view.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for (account, count, showsAssets) in [("b", 10, true), ("c", 30, false), ("d", 5, true), ("a", 30, true)] {
            controller.providers[0].itemIdentifiers = (0..<count).map { "account-\(account)-token-\($0)" }
            controller.providers[1].itemIdentifiers = ["account-\(account)-activity"]
            controller.showsAssets = showsAssets
            let incoming = controller.makeSnapshot(reconfiguringCustomSections: [])
            let applyCount = controller.applyCount
            let completed = expectation(description: "Account \(account) replacement completed")

            controller.applyContentReplacementSnapshot(incoming, animatingDifferences: true, alongside: {
                // Home's coordinated height update takes this path when the NFT cell
                // is offscreen, or when the incoming account has no NFT section.
                controller.reconfigureCustomSection(id: "assets")
                controller.reconfigureCustomSection(id: "tokens")
            }) { completed.fulfill() }

            await fulfillment(of: [completed], timeout: 3)
            // Include any second apply queued synchronously by the coordinated updates.
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(try controller.currentSnapshot().itemIdentifiers, incoming.itemIdentifiers)
            XCTAssertEqual(try controller.currentSnapshot().sectionIdentifiers, incoming.sectionIdentifiers)
            XCTAssertEqual(controller.applyCount, applyCount + 1, "Section updates must be folded into the replacement")
        }
    }

    func testAccountReplacementSupersedesPendingSectionUpdatesInOneApply() async throws {
        let controller = try await makeController()
        let oldRows = Set(try controller.currentSnapshot().itemIdentifiers.filter { $0 != .headerPlaceholder })
        let applied = expectation(description: "Account replacement applied")
        controller.onDidApply = { applied.fulfill() }
        let applyCount = controller.applyCount

        controller.reconfigureCustomSection(id: "tokens")
        controller.applyContentReplacementSnapshot(controller.makeSnapshot()) {
            XCTFail("A superseded account must not reveal its content")
        }
        for provider in controller.providers {
            provider.itemIdentifiers = ["account-b-\(provider.id)"]
        }
        let replacement = controller.makeSnapshot()
        let revealed = expectation(description: "Only the final account is revealed")
        controller.applyContentReplacementSnapshot(replacement) { revealed.fulfill() }

        await fulfillment(of: [applied, revealed], timeout: 3)
        XCTAssertEqual(controller.applyCount, applyCount + 1)
        XCTAssertEqual(try controller.currentSnapshot().itemIdentifiers, replacement.itemIdentifiers)
        XCTAssertTrue(oldRows.isDisjoint(with: replacement.itemIdentifiers))
    }

    func testReplacementUsesOnlyTheLatestCoordinatedLayoutUpdates() async throws {
        let controller = try await makeController()
        var updates = 0
        controller.applyContentReplacementSnapshot(controller.makeSnapshot(), alongside: {
            XCTFail("Superseded layout updates must not run")
        })
        controller.providers[0].itemIdentifiers = ["replacement-token"]
        let snapshot = controller.makeSnapshot()
        let applied = expectation(description: "Coordinated replacement")
        controller.applyContentReplacementSnapshot(snapshot, alongside: {
            updates += 1
            controller.headerHeight = 180
            controller.reconfigureHeaderPlaceholder(animated: false)
        }) { applied.fulfill() }
        XCTAssertEqual(updates, 0)
        await fulfillment(of: [applied], timeout: 3)
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(try controller.currentSnapshot().itemIdentifiers, snapshot.itemIdentifiers)
    }

    func testActivityRefreshOnlyReconfiguresActivityRows() async throws {
        let controller = try await makeController()
        let snapshot = controller.makeSnapshot(reconfiguringCustomSections: ["activities"])

        XCTAssertEqual(
            Set(snapshot.reconfiguredItemIdentifiers),
            Set(snapshot.itemIdentifiers(inSection: .custom("activities")))
        )
        XCTAssertEqual(snapshot.numberOfItems, 4)
    }

    func testBurstCombinesAppliesAndPreservesBothSectionUpdates() async throws {
        let controller = try await makeController()
        controller.providers.forEach { $0.configurationCount = 0 }
        let applied = expectation(description: "Combined snapshot applied")
        controller.onDidApply = { applied.fulfill() }
        let applyCount = controller.applyCount

        for _ in 0..<3 {
            controller.applySnapshot(
                controller.makeSnapshot(reconfiguringCustomSections: ["activities"]),
                animatingDifferences: false
            )
        }
        controller.reconfigureCustomSection(id: "tokens")
        controller.applySnapshot(controller.makeSnapshot(reconfiguringCustomSections: []), animatingDifferences: false)

        await fulfillment(of: [applied], timeout: 3)
        controller.collectionView.layoutIfNeeded()
        XCTAssertEqual(controller.applyCount, applyCount + 1)
        XCTAssertEqual(controller.providers[0].configurationCount, 1)
        XCTAssertEqual(controller.providers[1].configurationCount, 1)
        XCTAssertEqual(controller.providers[2].configurationCount, 0)
    }

    func testReconfigurationCannotRestoreRowsFromPreviousAccount() async throws {
        let controller = try await makeController()
        let oldRows = Set(try controller.currentSnapshot().itemIdentifiers.filter { $0 != .headerPlaceholder })
        let applied = expectation(description: "Latest account applied")
        controller.onDidApply = { applied.fulfill() }

        controller.reconfigureCustomSection(id: "tokens")
        controller.providers[0].itemIdentifiers = ["account-b-token"]
        controller.providers[1].itemIdentifiers = ["account-b-activity"]
        controller.providers[2].itemIdentifiers = []
        controller.applySnapshot(controller.makeSnapshot(reconfiguringCustomSections: ["activities"]), animatingDifferences: false)
        controller.reconfigureCustomSection(id: "tokens")
        controller.reconfigureCustomSection(id: "assets")

        await fulfillment(of: [applied], timeout: 3)
        let actual = try controller.currentSnapshot()
        XCTAssertEqual(actual.itemIdentifiers, controller.makeSnapshot().itemIdentifiers)
        XCTAssertTrue(oldRows.isDisjoint(with: actual.itemIdentifiers))
        XCTAssertEqual(actual.numberOfItems, 3)
    }

    func testHistoryCanStillApplyOnBackgroundQueue() async throws {
        let controller = try await makeController(usesBackgroundDiffing: true)
        let applied = expectation(description: "Background snapshot applied")
        controller.onDidApply = { applied.fulfill() }
        controller.providers[0].itemIdentifiers = ["new-token", "another-token"]
        let snapshot = controller.makeSnapshot()
        controller.applySnapshot(snapshot, animatingDifferences: false)

        await fulfillment(of: [applied], timeout: 3)
        XCTAssertEqual(try controller.currentSnapshot().itemIdentifiers, snapshot.itemIdentifiers)
    }

    func testPlaybackVisibilityCheckDoesNotForcePendingLayout() async throws {
        let controller = try await makeController()
        let layout = LayoutCountingFlowLayout()
        layout.itemSize = CGSize(width: 380, height: 50)
        controller.collectionView.setCollectionViewLayout(layout, animated: false)
        controller.collectionView.layoutIfNeeded()
        controller.viewDidAppear(false)
        let preparations = layout.preparations

        layout.invalidateLayout()
        controller.collectionView.setNeedsLayout()
        controller.updateVisibleActivityNftAnimationPlayback()

        XCTAssertEqual(layout.preparations, preparations)
        controller.collectionView.layoutIfNeeded()
        XCTAssertGreaterThan(layout.preparations, preparations)
        controller.viewWillDisappear(false)
    }

    func testHeaderResizeMovesSectionsWithoutReconfiguringTheirCells() async throws {
        let controller = try await makeController()
        controller.collectionView.contentInset.top = 80
        controller.collectionView.contentOffset.y = -80
        controller.collectionView.layoutIfNeeded()
        let originalFrames = try controller.providers.map {
            try XCTUnwrap(controller.firstItemFrame(inCustomSection: $0.id))
        }
        let originalContentHeight = controller.collectionView.contentSize.height
        let originalOffset = controller.collectionView.contentOffset
        controller.providers.forEach { $0.configurationCount = 0 }

        for requestedHeight: CGFloat in [121, 0, 181, 1] {
            controller.headerHeight = requestedHeight
            controller.reconfigureHeaderPlaceholder(animated: false)
            controller.collectionView.layoutIfNeeded()
            let height = max(requestedHeight, 1 / max(controller.traitCollection.displayScale, 1))

            for (provider, originalFrame) in zip(controller.providers, originalFrames) {
                let frame = try XCTUnwrap(controller.firstItemFrame(inCustomSection: provider.id))
                XCTAssertEqual(frame.minY, originalFrame.minY + height - 1, accuracy: 0.5)
                XCTAssertEqual(frame.height, originalFrame.height, accuracy: 0.5)
                XCTAssertEqual(provider.configurationCount, 0)
            }
            XCTAssertEqual(controller.collectionView.contentSize.height, originalContentHeight + height - 1, accuracy: 0.5)
            XCTAssertEqual(controller.collectionView.contentOffset, originalOffset)
        }
    }

    func testUnchangedHeaderDoesNotRebuildSections() async throws {
        let controller = try await makeController()
        let layoutCounts = controller.providers.map(\.layoutCount)

        for _ in 0..<10 {
            controller.reconfigureHeaderPlaceholder(animated: false)
            controller.collectionView.layoutIfNeeded()
        }

        XCTAssertEqual(controller.providers.map(\.layoutCount), layoutCounts)
    }

    func testHeaderCanResizeWhileOffscreen() async throws {
        let controller = try await makeController()
        controller.collectionView.contentOffset.y = 100
        controller.collectionView.layoutIfNeeded()
        let original = try XCTUnwrap(controller.firstItemFrame(inCustomSection: "tokens"))

        controller.headerHeight = 61
        controller.reconfigureHeaderPlaceholder(animated: false)
        controller.collectionView.layoutIfNeeded()

        let updated = try XCTUnwrap(controller.firstItemFrame(inCustomSection: "tokens"))
        XCTAssertEqual(updated.minY, original.minY + 60, accuracy: 0.5)
        controller.collectionView.contentOffset.y = 0
        controller.collectionView.layoutIfNeeded()
        let header = try XCTUnwrap(controller.collectionView.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(header.size.height, 61, accuracy: 0.5)
    }

    func testAssetsResizePreservesHeaderAndOtherSections() async throws {
        let controller = try await makeController()
        let headerIndexPath = IndexPath(item: 0, section: 0)
        let layout = controller.collectionView.collectionViewLayout
        let originalHeader = try XCTUnwrap(layout.layoutAttributesForItem(at: headerIndexPath)).frame
        let originalTokens = try XCTUnwrap(controller.firstItemFrame(inCustomSection: "tokens"))
        let originalAssets = try XCTUnwrap(controller.firstItemFrame(inCustomSection: "assets"))
        let originalContentHeight = controller.collectionView.contentSize.height
        let assetsCell = try XCTUnwrap(controller.visibleCustomSectionCell(id: "assets") as? FirstRowCell)

        assetsCell.configure(height: 150)
        controller.invalidateCustomSectionLayout(id: "assets")
        controller.collectionView.layoutIfNeeded()

        let assets = try XCTUnwrap(controller.firstItemFrame(inCustomSection: "assets"))
        XCTAssertEqual(assets.minY, originalAssets.minY, accuracy: 0.5)
        XCTAssertEqual(assets.height, 150, accuracy: 0.5)
        XCTAssertEqual(layout.layoutAttributesForItem(at: headerIndexPath)?.frame, originalHeader)
        XCTAssertEqual(controller.firstItemFrame(inCustomSection: "tokens"), originalTokens)
        XCTAssertEqual(controller.collectionView.contentSize.height, originalContentHeight + 100, accuracy: 0.5)
    }

    private func makeController(usesBackgroundDiffing: Bool = false) async throws -> SnapshotTestController {
        let controller = SnapshotTestController()
        controller.backgroundDiffing = usesBackgroundDiffing
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        controller.setupCollectionView(collectionViewBottomConstraint: 0)
        controller.view.layoutIfNeeded()
        let applied = expectation(description: "Initial snapshot applied")
        controller.onDidApply = { applied.fulfill() }
        controller.applySnapshot(controller.makeSnapshot(), animatingDifferences: false)
        await fulfillment(of: [applied], timeout: 3)
        controller.onDidApply = nil
        controller.collectionView.layoutIfNeeded()
        XCTAssertEqual(controller.collectionView.visibleCells.count, 4)
        return controller
    }
}

@MainActor
private final class LayoutCountingFlowLayout: UICollectionViewFlowLayout {
    var preparations = 0

    override func prepare() {
        preparations += 1
        super.prepare()
    }
}

@MainActor
private final class SnapshotTestController: ActivityListViewController {
    let providers = ["tokens", "activities", "assets"].map { SnapshotSection(id: $0) }
    var backgroundDiffing = false
    var applyCount = 0
    var onDidApply: (() -> Void)?

    var headerHeight: CGFloat = 1
    var showsAssets = true
    override var headerPlaceholderHeight: CGFloat { headerHeight }
    override var displaysActivitySections: Bool { false }
    override var usesBackgroundSnapshotDiffing: Bool { backgroundDiffing }
    override var customSections: [any CustomSectionDataProvider] { providers }
    override var activeCustomSectionIDs: [String] { providers.map(\.id).filter { showsAssets || $0 != "assets" } }

    override func didApplySnapshot() {
        XCTAssertTrue(Thread.isMainThread)
        applyCount += 1
        onDidApply?()
    }

    func currentSnapshot() throws -> NSDiffableDataSourceSnapshot<Section, Row> {
        let source = try XCTUnwrap(collectionView.dataSource as? UICollectionViewDiffableDataSource<Section, Row>)
        return source.snapshot()
    }
}

@MainActor
private final class SnapshotSection: ActivityListViewController.CustomSectionDataProvider {
    let id: String
    var itemIdentifiers: [String]
    var configurationCount = 0
    var layoutCount = 0
    private lazy var registration = UICollectionView.CellRegistration<FirstRowCell, String> { [weak self] cell, _, _ in
        self?.configurationCount += 1
        cell.configure(height: 50)
    }

    init(id: String) {
        self.id = id
        self.itemIdentifiers = ["account-a-\(id)"]
    }

    func prepareForUse() { _ = registration }

    func makeLayoutSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        layoutCount += 1
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(50))
        return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
    }

    func dequeueCell(_ collectionView: UICollectionView, _ indexPath: IndexPath, itemIdentifier: String) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemIdentifier)
    }
}
