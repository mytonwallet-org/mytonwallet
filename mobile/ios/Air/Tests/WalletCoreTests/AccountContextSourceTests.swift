import Dependencies
import XCTest
@testable import WalletCore

@MainActor
final class AccountContextSourceTests: XCTestCase {
    func testExplicitSwitchUpdatesTheAccountPassedToNewScreens() {
        withDependencies {
            $0.accountStore = .shared
            $0[DomainsStore.self] = DomainsStore.liveValue
        } operation: {
            let context = AccountContext(source: .accountId("first"))
            context.accountId = "second"
            XCTAssertEqual(context.source, .accountId("second"))
        }
    }

    func testCurrentAndConstantBindingsRetainTheirSource() {
        withDependencies {
            $0.accountStore = .shared
            $0[DomainsStore.self] = DomainsStore.liveValue
        } operation: {
            let current = AccountContext(source: .current)
            XCTAssertEqual(current.source, .current)
            let constant = AccountContext(source: .constant(DUMMY_ACCOUNT))
            XCTAssertEqual(constant.source, .constant(DUMMY_ACCOUNT))
        }
    }
}
