import GRDB
import Testing
@testable import WalletCore

@Suite("Localized Token Name Settings")
struct LocalizedTokenNameSettingsTests {
    @Test
    func `setting is global defaults on and persists`() throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)

        let settings = SettingsStore()
        settings.use(db: db)
        #expect(settings.useLocalizedTokenNames)

        settings.setUseLocalizedTokenNames(false)

        let reloadedSettings = SettingsStore()
        reloadedSettings.use(db: db)
        #expect(!reloadedSettings.useLocalizedTokenNames)
    }

    @Test
    func `v20 migration adds enabled setting to existing database`() throws {
        let db = try DatabaseQueue()
        let migrator = makeMigrator()
        try migrator.migrate(db, upTo: "v19")
        try db.write { db in
            try db.execute(sql: "UPDATE settings SET canPlaySounds = 0 WHERE id = 0")
        }

        try migrator.migrate(db)

        let settings = SettingsStore()
        settings.use(db: db)
        #expect(settings.useLocalizedTokenNames)
        #expect(!settings.canPlaySounds)
    }
}
