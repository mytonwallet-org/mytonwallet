import Dependencies
import GRDB
import UIKit
import XCTest
import WalletContext
import WalletResources
@testable import WalletCore
@testable import AirAsFramework

@MainActor
final class SplitHomeAccountCrossfadeTests: XCTestCase {
    override func invokeTest() {
        withDependencies { $0.context = .live } operation: { super.invokeTest() }
    }

    func testCrossfadeLeavesGlassActionsLiveAndOpaque() async throws {
        try await withHome { home, window in
            let actions = try XCTUnwrap(home.visibleCustomSectionCell(id: "actions"))
            let assetsFrame = try XCTUnwrap(home.firstItemFrame(inCustomSection: "assets"))
            let snapshot = try XCTUnwrap(home.prepareAccountSwitchCrossfade())
            let actionsFrame = actions.convert(actions.bounds, to: home.view)
            XCTAssertGreaterThanOrEqual(snapshot.frame.minY, actionsFrame.maxY)
            XCTAssertEqual(snapshot.frame.minY, home.collectionView.convert(assetsFrame, to: home.view).minY, accuracy: 0.5)
            XCTAssertEqual(snapshot.backgroundColor, home.view.backgroundColor)
            XCTAssertEqual(home.collectionView.alpha, 1)

            home.finishAccountSwitchCrossfade(snapshot: snapshot)
            for _ in 0..<8 {
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(home.collectionView.alpha, 1)
                XCTAssertEqual(home.collectionView.layer.presentation()?.opacity ?? 1, 1)
                XCTAssertTrue(home.visibleCustomSectionCell(id: "actions") === actions)
            }
            XCTAssertNil(snapshot.superview)
            window.layoutIfNeeded()
        }
    }

    func testInterruptedCrossfadeCannotRemoveReplacement() async throws {
        try await withHome { home, _ in
            let first = try XCTUnwrap(home.prepareAccountSwitchCrossfade())
            home.finishAccountSwitchCrossfade(snapshot: first)
            try await Task.sleep(for: .milliseconds(50))
            let second = try XCTUnwrap(home.prepareAccountSwitchCrossfade())
            XCTAssertNil(first.superview)
            home.cleanupAccountSwitchCrossfade(snapshot: first)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertTrue(second.superview === home.view)
            XCTAssertEqual(home.collectionView.alpha, 1)
            home.finishAccountSwitchCrossfade(snapshot: second)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertNil(second.superview)
        }
    }

    func testSkippedSnapshotCleanupCannotRemoveReplacement() async throws {
        try await withHome { home, _ in
            var skippedSnapshot: UIView?
            UIView.performWithoutAnimation {
                skippedSnapshot = home.prepareAccountSwitchCrossfade()
            }
            XCTAssertNil(skippedSnapshot)
            let replacement = try XCTUnwrap(home.prepareAccountSwitchCrossfade())
            let staleCleanup = Task { @MainActor in
                home.cleanupAccountSwitchCrossfade(snapshot: skippedSnapshot)
            }
            await staleCleanup.value
            XCTAssertTrue(replacement.superview === home.view)
            XCTAssertEqual(home.collectionView.alpha, 1)
            home.finishAccountSwitchCrossfade(snapshot: replacement)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertNil(replacement.superview)
        }
    }

    func testChangingActionVisibilitySkipsCrossfadeInBothDirections() async throws {
        var regularSnapshot: NSDiffableDataSourceSnapshot<SplitHomeVC.Section, SplitHomeVC.Row>?
        try await withHome { home, window in
            var snapshot = home.makeSnapshot()
            regularSnapshot = snapshot
            snapshot.deleteSections([.custom("actions")])
            let applied = expectation(description: "regular account with outgoing view-only layout")
            home.applyContentReplacementSnapshot(snapshot, completion: { applied.fulfill() })
            await fulfillment(of: [applied], timeout: 3)
            window.layoutIfNeeded()
            XCTAssertNil(home.firstItemFrame(inCustomSection: "actions"))
            XCTAssertNotNil(home.firstItemFrame(inCustomSection: "assets"))
            XCTAssertNil(home.prepareAccountSwitchCrossfade())
        }
        try await withHome(isView: true) { home, window in
            let matchingSnapshot = try XCTUnwrap(home.prepareAccountSwitchCrossfade())
            home.cleanupAccountSwitchCrossfade(snapshot: matchingSnapshot)
            let snapshot = try XCTUnwrap(regularSnapshot)
            let applied = expectation(description: "view-only account with outgoing regular layout")
            home.applyContentReplacementSnapshot(snapshot, completion: { applied.fulfill() })
            await fulfillment(of: [applied], timeout: 3)
            window.layoutIfNeeded()
            XCTAssertNotNil(home.firstItemFrame(inCustomSection: "actions"))
            XCTAssertNotNil(home.firstItemFrame(inCustomSection: "assets"))
            XCTAssertNil(home.prepareAccountSwitchCrossfade())
        }
    }

    func testScrolledContentUsesVisibleBoundsAndDisabledAnimationsSkipSnapshot() async throws {
        try await withHome { home, window in
            let assets = try XCTUnwrap(home.firstItemFrame(inCustomSection: "assets"))
            home.collectionView.contentOffset.y = assets.minY + 20
            window.layoutIfNeeded()
            let snapshot = try XCTUnwrap(home.prepareAccountSwitchCrossfade())
            XCTAssertEqual(snapshot.frame, home.collectionView.convert(home.collectionView.bounds, to: home.view))
            home.cleanupAccountSwitchCrossfade(snapshot: snapshot)
            UIView.performWithoutAnimation {
                XCTAssertNil(home.prepareAccountSwitchCrossfade())
            }
            XCTAssertEqual(home.collectionView.alpha, 1)
        }
    }

    private func withHome(isView: Bool = false, _ operation: (SplitHomeVC, UIWindow) async throws -> Void) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let account = MAccount(id: "13741-mainnet", title: "Crossfade", type: isView ? .view : .mnemonic,
                               byChain: [.ton: .init(address: "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c")])
        try await db.write { db in
            try account.insert(db)
            try _ActivityStore.AccountState(accountId: account.id, byId: [:], idsMain: [],
                idsBySlug: [:], isMainHistoryEndReached: true, isHistoryEndReachedBySlug: [:]).insert(db)
        }
        SettingsStore.liveValue.use(db: db)
        await _ActivityStore.shared.use(db: db)
        let animations = AppStorageHelper.animations
        AppStorageHelper.animations = true
        defer {
            AppStorageHelper.animations = animations
            SettingsStore.liveValue.clean()
        }
        try await withDependencies {
            $0.context = .live
            $0.accountStore = _AccountStore(db: db)
        } operation: {
            let home = SplitHomeVC(accountSource: .constant(account))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
            window.rootViewController = home
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            for _ in 0..<100 where home.activityViewModel == nil || home.visibleCustomSectionCell(id: "assets") == nil {
                try await Task.sleep(for: .milliseconds(10))
                window.layoutIfNeeded()
            }
            try await Task.sleep(for: .milliseconds(300))
            try await operation(home, window)
        }
    }
}
