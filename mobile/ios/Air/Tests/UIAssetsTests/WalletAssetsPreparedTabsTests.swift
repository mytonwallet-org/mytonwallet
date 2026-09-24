import GRDB
import XCTest
@testable import UIAssets

@MainActor
final class WalletAssetsPreparedTabsTests: XCTestCase {
    func testPreparedOrderIsAppliedWithTheAccountReplacement() async throws {
        let database = try makeDatabase()
        let prepared = await WalletAssetsViewModel.prepareTabs(accountId: "prepared-tabs", database: database)
        let model = WalletAssetsViewModel(accountSource: .accountId("initial-tabs"))

        model.switchAccountTo("prepared-tabs", preparedTabs: prepared)

        XCTAssertEqual(model.displayTabs, [.nfts, .tokens])
    }

    func testMissingSettingsResetThePreviousAccountOrder() async throws {
        let database = try makeDatabase()
        let custom = await WalletAssetsViewModel.prepareTabs(accountId: "prepared-tabs", database: database)
        let defaults = await WalletAssetsViewModel.prepareTabs(accountId: "default-tabs", database: database)
        let model = WalletAssetsViewModel(accountSource: .accountId("initial-tabs"))
        model.switchAccountTo("prepared-tabs", preparedTabs: custom)

        model.switchAccountTo("default-tabs", preparedTabs: defaults)

        XCTAssertEqual(model.displayTabs, [.tokens, .nfts])
    }

    func testPreparedSettingsCannotBeAppliedToAnotherAccount() async throws {
        let database = try makeDatabase()
        let prepared = await WalletAssetsViewModel.prepareTabs(accountId: "prepared-tabs", database: database)
        let model = WalletAssetsViewModel(accountSource: .accountId("initial-tabs"))

        model.switchAccountTo("different-tabs", preparedTabs: prepared)

        XCTAssertEqual(model.displayTabs, [.tokens, .nfts])
    }

    private func makeDatabase() throws -> DatabaseQueue {
        let database = try DatabaseQueue()
        try database.write { db in
            try db.execute(sql: "CREATE TABLE asset_tabs (account_id TEXT PRIMARY KEY, tabs TEXT, auto_telegram_gifts_hidden BOOLEAN)")
            try db.execute(sql: "INSERT INTO asset_tabs (account_id, tabs) VALUES (?, ?)",
                           arguments: ["prepared-tabs", "[\"nfts\",\"tokens\"]"])
        }
        return database
    }
}
