import UIKit
import XCTest
import UIActivityList
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class ContentUpdateAnimationTests: XCTestCase {
    func testSilentReconfigurationWinsInEitherCoalescingOrder() async {
        _ = WalletResourcesBundle.bundle.load()
        let fixture = ContentUpdateFixture()
        let window = show(fixture)
        defer { window.isHidden = true }
        await apply(fixture, animated: false, expectsAnimation: false)

        for silentFirst in [false, true] {
            let applied = expectation(description: "coalesced snapshot")
            fixture.applyContentReplacementSnapshot(fixture.makeSnapshot(), animatingDifferences: true, alongside: {
                XCTAssertFalse(UIView.areAnimationsEnabled)
            }, completion: { applied.fulfill() })
            fixture.reconfigureCustomSection(id: "fixture", animated: !silentFirst)
            fixture.reconfigureCustomSection(id: "fixture", animated: silentFirst)
            await fulfillment(of: [applied], timeout: 3)
        }
    }

    func testDeferredUpdatePreservesPerformWithoutAnimation() async {
        _ = WalletResourcesBundle.bundle.load()
        let fixture = ContentUpdateFixture()
        let window = show(fixture)
        defer { window.isHidden = true }
        await apply(fixture, animated: false, expectsAnimation: false)
        let applied = expectation(description: "deferred silent snapshot")
        UIView.performWithoutAnimation {
            fixture.applyContentReplacementSnapshot(fixture.makeSnapshot(), animatingDifferences: true, alongside: {
                XCTAssertFalse(UIView.areAnimationsEnabled)
            }, completion: { applied.fulfill() })
        }
        fixture.reconfigureCustomSection(id: "fixture", animated: true)
        await fulfillment(of: [applied], timeout: 3)
    }

    func testPreparationAndDisappearanceStaySilentButVisibleUpdatesAnimate() async {
        _ = WalletResourcesBundle.bundle.load()
        let fixture = ContentUpdateFixture()
        fixture.loadViewIfNeeded()
        await apply(fixture, animated: true, expectsAnimation: false)

        let window = show(fixture)
        defer { window.isHidden = true }
        let allowsAnimation = AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
        await apply(fixture, animated: true, expectsAnimation: allowsAnimation)

        let applied = expectation(description: "snapshot after disappearance")
        fixture.applyContentReplacementSnapshot(fixture.makeSnapshot(), animatingDifferences: true, alongside: {
            XCTAssertFalse(UIView.areAnimationsEnabled)
        }, completion: { applied.fulfill() })
        fixture.beginAppearanceTransition(false, animated: false)
        fixture.endAppearanceTransition()
        await fulfillment(of: [applied], timeout: 3)
    }

    private func show(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func apply(_ fixture: ContentUpdateFixture, animated: Bool, expectsAnimation: Bool) async {
        let applied = expectation(description: "snapshot")
        fixture.applyContentReplacementSnapshot(fixture.makeSnapshot(), animatingDifferences: animated, alongside: {
            XCTAssertEqual(UIView.areAnimationsEnabled, expectsAnimation)
            if expectsAnimation { XCTAssertGreaterThan(UIView.inheritedAnimationDuration, 0) }
        }, completion: { applied.fulfill() })
        await fulfillment(of: [applied], timeout: 3)
    }
}

private final class ContentUpdateFixture: ActivityListViewController {
    override var usesBackgroundSnapshotDiffing: Bool { false }
    override var displaysActivitySections: Bool { false }
    override var headerPlaceholderHeight: CGFloat { 1 }
    override var customSections: [any CustomSectionDataProvider] {
        [CustomSectionDescriptor(id: "fixture") { collection, indexPath in
            collection.dequeueReusableCell(withReuseIdentifier: "fixture", for: indexPath)
        }]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "fixture")
        setupCollectionView(collectionViewBottomConstraint: 0)
    }
}
