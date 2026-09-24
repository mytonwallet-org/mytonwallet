import XCTest
import UIComponents
import UIKit
import WalletCore
@testable import UIHome

@MainActor
final class HomeCardEffectsTests: XCTestCase {
    func testEffectsOnlyRunOnVisibleExpandedIdleCards() {
        let model = HomeHeaderViewModel(accountSource: .accountId("preview"))
        XCTAssertFalse(model.allowsCardEffects(for: "preview"))
        model.isVisible = true
        XCTAssertTrue(model.allowsCardEffects(for: "preview"))
        XCTAssertFalse(model.allowsCardEffects(for: "neighbor"))
        model.isAccountScrolling = true
        XCTAssertFalse(model.allowsCardEffects(for: "preview"))
        model.isAccountScrolling = false
        model.state = .collapsed
        XCTAssertFalse(model.allowsCardEffects(for: "preview"))
        model.state = .expanded
        XCTAssertTrue(model.allowsCardEffects(for: "preview"))
        model.isVisible = false
        XCTAssertFalse(model.allowsCardEffects(for: "preview"))
    }
}
