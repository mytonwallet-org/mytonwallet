import XCTest
import UIKit
import GRDB
import WalletContext
@testable import WalletCore
import WalletResources
@testable import UIComponents

@MainActor
final class SensitiveDataRevealTests: XCTestCase {
    private var originalPrivacy = false
    private var originalAnimations = true
    private var originalUIViewAnimations = true

    override func setUp() async throws {
        try await super.setUp()
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        _ = WalletResourcesBundle.bundle.load()
        originalPrivacy = AppStorageHelper.isSensitiveDataHidden
        originalAnimations = AppStorageHelper.animations
        originalUIViewAnimations = UIView.areAnimationsEnabled
        AppStorageHelper.isSensitiveDataHidden = true
        AppStorageHelper.animations = false
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() async throws {
        AppStorageHelper.isSensitiveDataHidden = originalPrivacy
        AppStorageHelper.animations = originalAnimations
        UIView.setAnimationsEnabled(originalUIViewAnimations)
        SettingsStore.liveValue.clean()
        try await super.tearDown()
    }

    private func makeBalance(hero: Bool) -> (UIView, WSensitiveData<UILabel>) {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        let balance = WSensitiveData<UILabel>(cols: 12, rows: 3, cellSize: 10,
            cornerRadius: 5, theme: .adaptive, alignment: .center, usesHeroParticles: hero)
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "0"
        balance.addContent(label)
        balance.translatesAutoresizingMaskIntoConstraints = true
        balance.frame = CGRect(x: 175, y: 50, width: 40, height: 48)
        host.addSubview(balance)
        host.layoutIfNeeded()
        balance.layoutIfNeeded()
        return (host, balance)
    }

    func testEntireHiddenMaskReceivesTouchesForShortBalances() throws {
        for hero in [false, true] {
            let (host, balance) = makeBalance(hero: hero)
            let target: UIView = hero ? balance : try XCTUnwrap(balance.shyMask)
            for offset in [-55.0, 0, 55] {
                let point = CGPoint(x: balance.frame.midX + offset, y: balance.frame.midY)
                XCTAssertTrue(host.hitTest(point, with: nil) === target,
                    "Both the center and edges of the visible mask must receive taps")
            }
            XCTAssertTrue(host.hitTest(CGPoint(x: balance.frame.midX + 70, y: balance.frame.midY), with: nil) === host)
        }
    }

    func testHeroOnlyInterceptsTouchesWhileRevealIsAvailable() {
        let (host, balance) = makeBalance(hero: true)
        let center = CGPoint(x: balance.frame.midX, y: balance.frame.midY)
        balance.isTapToRevealEnabled = false
        XCTAssertTrue(host.hitTest(center, with: nil) === host)
        balance.isTapToRevealEnabled = true
        XCTAssertTrue(host.hitTest(center, with: nil) === balance)

        balance.performTap()
        XCTAssertTrue(host.hitTest(center, with: nil) === host)
        balance.resetReveal()
        XCTAssertTrue(host.hitTest(center, with: nil) === balance)

        balance.isHidden = true
        XCTAssertTrue(host.hitTest(center, with: nil) === host)
        balance.isHidden = false
        balance.isUserInteractionEnabled = false
        XCTAssertTrue(host.hitTest(center, with: nil) === host)
        balance.isUserInteractionEnabled = true
        AppStorageHelper.isSensitiveDataHidden = false
        balance.resetReveal()
        XCTAssertTrue(host.hitTest(center, with: nil) === host)
    }

    func testBothMaskStylesRevealLocallyAndHideAgainAfterFiveSeconds() async throws {
        let balances = [makeBalance(hero: false), makeBalance(hero: true)]
        var maskStates = [true, true]
        for (index, (_, balance)) in balances.enumerated() {
            balance.onMaskStateChanged = { maskStates[index] = $0 }
            balance.performTap()
        }
        XCTAssertEqual(maskStates, [false, false])
        XCTAssertTrue(AppStorageHelper.isSensitiveDataHidden)

        try await Task.sleep(for: .milliseconds(5300))

        XCTAssertEqual(maskStates, [true, true])
        XCTAssertTrue(AppStorageHelper.isSensitiveDataHidden)
        for (_, balance) in balances {
            balance.performTap()
            balance.resetReveal()
        }
        XCTAssertEqual(maskStates, [true, true], "Reusing a cell must immediately restore privacy")
    }
}
