import UIKit
import XCTest
@testable import WalletContext

final class NativeIdentifierTests: XCTestCase {
    private enum Item: Hashable, Sendable {
        case token(account: String, slug: String)
    }

    func testSnapshotResolvesRecreatedIdentifiersWithoutMergingAccounts() {
        typealias ID = NativeIdentifier<Item>
        let main = ID(.token(account: "main", slug: "ton"))
        let other = ID(.token(account: "other", slug: "ton"))
        var snapshot = NSDiffableDataSourceSnapshot<NativeIdentifier<String>, ID>()
        snapshot.appendSections([NativeIdentifier("tokens")])
        snapshot.appendItems([main, other], toSection: NativeIdentifier("tokens"))

        let recreated = ID(.token(account: "main", slug: "ton"))
        snapshot.reconfigureItems([recreated])
        XCTAssertEqual(snapshot.reconfiguredItemIdentifiers, [main])
        snapshot.deleteItems([recreated])
        XCTAssertEqual(snapshot.itemIdentifiers, [other])
        XCTAssertEqual(snapshot.numberOfItems(inSection: NativeIdentifier("tokens")), 1)
    }
}
