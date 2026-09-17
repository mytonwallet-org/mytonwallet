import UIActivityList
import UIKit
import XCTest

@MainActor
final class ActivityListSnapshotTests: XCTestCase {
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

    override var headerPlaceholderHeight: CGFloat { 1 }
    override var displaysActivitySections: Bool { false }
    override var usesBackgroundSnapshotDiffing: Bool { backgroundDiffing }
    override var customSections: [any CustomSectionDataProvider] { providers }

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
    private lazy var registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] _, _, _ in
        self?.configurationCount += 1
    }

    init(id: String) {
        self.id = id
        self.itemIdentifiers = ["account-a-\(id)"]
    }

    func prepareForUse() { _ = registration }

    func makeLayoutSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(50))
        return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
    }

    func dequeueCell(_ collectionView: UICollectionView, _ indexPath: IndexPath, itemIdentifier: String) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemIdentifier)
    }
}
