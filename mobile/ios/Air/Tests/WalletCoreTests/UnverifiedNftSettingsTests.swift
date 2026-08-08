import GRDB
import Testing
@testable import WalletCore

@Suite("Unverified NFT Settings")
struct UnverifiedNftSettingsTests {
    @Test
    func `setting is global defaults on and persists`() throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)

        let settings = SettingsStore()
        settings.use(db: db)
        #expect(settings.areUnverifiedNftsHidden)

        settings.setAreUnverifiedNftsHidden(false)

        let reloadedSettings = SettingsStore()
        reloadedSettings.use(db: db)
        #expect(!reloadedSettings.areUnverifiedNftsHidden)
    }

    @Test
    func `v23 migration enables setting in existing database`() throws {
        let db = try DatabaseQueue()
        let migrator = makeMigrator()
        try migrator.migrate(db, upTo: "v22")
        try db.write { db in
            try db.execute(sql: "UPDATE settings SET canPlaySounds = 0 WHERE id = 0")
        }

        try migrator.migrate(db)

        let settings = SettingsStore()
        settings.use(db: db)
        #expect(settings.areUnverifiedNftsHidden)
        #expect(!settings.canPlaySounds)
    }
}
