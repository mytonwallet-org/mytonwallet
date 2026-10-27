import Dependencies
import Foundation
import GRDB
import Testing
@testable import WalletCore

@MainActor
struct AccountBannersTests {
    @Test func submittedProvidersHideOnlyTheirLinkedHomeOfferUntilTheyDisappear() {
        withDependencies {
            $0[AccountSettingsStore.self] = AccountSettingsStore()
        } operation: {
            let state = AccountConfig(accountId: "first").banners
            let first = banner("first", link: "home")
            let second = banner("second", link: "home")
            let home = [banner("home"), banner("unrelated")]
            state.replace(home: home, staking: [first, second])
            state.didSubmitUnstake(id: first.id)
            #expect(state.staking.map(\.id) == [second.id])
            #expect(state.home.map(\.id) == ["home", "unrelated"])
            state.didSubmitUnstake(id: second.id)
            state.replace(home: home, staking: [first, second])
            #expect(state.staking.isEmpty)
            #expect(state.home.map(\.id) == ["unrelated"])
            state.replace(home: [banner("unrelated")], staking: [])
            state.didSubmitUnstake(id: first.id)
            state.replace(home: home, staking: [first])
            #expect(state.staking == [first])
            #expect(state.home == home)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func closingHomeSurvivesReloadWithoutAffectingOtherAccountsOrStaking() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            for accountId in ["first", "second"] {
                try MAccount(id: accountId, title: accountId, type: .mnemonic, byChain: ["ton": AccountChain(address: "test-address")]).insert(db)
            }
        }
        let store = AccountSettingsStore()
        await store.use(db: db)
        let home = [banner("home"), banner("next")]
        let staking = [banner("provider", link: "home")]
        withDependencies {
            $0[AccountSettingsStore.self] = store
        } operation: {
            let firstAccount = AccountConfig(accountId: "first").banners
            let secondAccount = AccountConfig(accountId: "second").banners
            firstAccount.replace(home: home, staking: staking)
            secondAccount.replace(home: home, staking: staking)
            firstAccount.dismissHome(id: "next")
            #expect(firstAccount.home == home)
            firstAccount.dismissHome(id: "home")
            firstAccount.replace(home: [], staking: [])
            firstAccount.replace(home: home, staking: staking)
            #expect(firstAccount.home.map(\.id) == ["next"])
            #expect(firstAccount.staking == staking)
            #expect(secondAccount.home == home)
        }

        // Wait for the real asynchronous settings write before recreating the stores.
        let saved = try await ValueObservation.tracking {
            try MAccountSettings.fetchOne($0, key: "first")
        }.values(in: db).first { $0?.dismissedHomeBannerIds == ["home"] }
        #expect(saved != nil)

        let reloaded = AccountSettingsStore()
        await reloaded.use(db: db)
        withDependencies {
            $0[AccountSettingsStore.self] = reloaded
        } operation: {
            let firstAccount = AccountConfig(accountId: "first").banners
            let secondAccount = AccountConfig(accountId: "second").banners
            firstAccount.replace(home: home, staking: staking)
            secondAccount.replace(home: home, staking: staking)
            #expect(firstAccount.home.map(\.id) == ["next"])
            #expect(firstAccount.staking == staking)
            #expect(secondAccount.home == home)
        }
    }

    @Test func olderSettingsWritesCannotRestoreDismissedHomeBanners() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            try MAccount(id: "first", title: "First", type: .mnemonic, byChain: ["ton": AccountChain(address: "test-address")]).insert(db)
        }
        let store = AccountSettingsStore()
        await store.use(db: db)
        for ids in [["home", "next"], ["home"], []] {
            await store.persist(MAccountSettings(accountId: "first", settingsDict: ["dismissedHomeBannerIds": ids]))
        }

        let reloaded = AccountSettingsStore()
        await reloaded.use(db: db)
        #expect(reloaded.for(accountId: "first").dismissedHomeBannerIds == ["home", "next"])
    }

    @Test func migrationPreservesExistingSettingsAndImportsClassicDismissals() throws {
        let db = try DatabaseQueue()
        let migrator = makeMigrator()
        try migrator.migrate(db, upTo: "v28")
        try db.write { db in
            try MAccount(id: "first", title: "First", type: .mnemonic, byChain: ["ton": AccountChain(address: "test-address")]).insert(db)
            try db.execute(sql: "INSERT INTO account_settings (accountId, portfolioTimeRange) VALUES ('first', '1M')")
        }
        try migrator.migrate(db)
        let existing = try #require(db.read { try MAccountSettings.fetchOne($0, key: "first") })
        #expect(existing.portfolioTimeRange == "1M")
        #expect(existing.dismissedHomeBannerIds == nil)

        let imported = MAccountSettings(accountId: "first", settingsDict: ["dismissedHomeBannerIds": ["home"]])
        #expect(imported.hasData)
        try db.write { try imported.upsert($0) }
        #expect(try db.read { try MAccountSettings.fetchOne($0, key: "first")?.dismissedHomeBannerIds } == ["home"])
    }

    private func banner(_ id: String, link: String? = nil) -> ApiPromotion {
        ApiPromotion(id: id, infoBanner: .init(title: "Title", description: "Body", actionButton: .init(title: "Earn", onClickAction: .openEarn)), linkedBannerId: link)
    }
}
